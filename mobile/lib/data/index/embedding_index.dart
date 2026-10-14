import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../api/dtos/embedding.dart';

/// The faces already in the library, searchable by identity. The scan uses it for the PC's
/// duplicate rule: a detection whose cosine similarity to an existing face is >= 0.95 (cosine
/// distance <= 0.05) is *linked* to that face instead of being stored again.
///
/// Vectors are unit length (InsightFace), so cosine similarity is a plain dot product. They live in
/// one contiguous Float32List; the isolate variant keeps that matrix off the UI isolate.
class IndexHit {
  const IndexHit(this.id, this.cosine);

  final int id;
  final double cosine;

  @override
  String toString() => 'IndexHit($id, ${cosine.toStringAsFixed(4)})';
}

abstract interface class EmbeddingIndex {
  /// Adds vectors (or replaces the vector of an id that is already there).
  Future<void> addAll(List<(int, Float32List)> items);

  Future<void> remove(Iterable<int> ids);

  /// For every query, the most similar stored face (null when the index is empty).
  Future<List<IndexHit?>> nearest(List<Float32List> queries);

  Future<int> size();

  Future<void> dispose();
}

Float32List _unit(Float32List v) {
  if (v.length != embeddingDim) {
    throw ArgumentError(
      'An embedding has $embeddingDim values, got ${v.length}',
    );
  }
  var sum = 0.0;
  for (var i = 0; i < v.length; i++) {
    sum += v[i] * v[i];
  }
  final out = Float32List(embeddingDim);
  if (sum <= 0) return out; // an all-zero vector matches nothing
  final inv = 1.0 / math.sqrt(sum);
  for (var i = 0; i < v.length; i++) {
    out[i] = v[i] * inv;
  }
  return out;
}

/// The matrix and the search. Pure Dart (no isolate), used directly by tests and by the worker.
class EmbeddingMatrix {
  EmbeddingMatrix({int capacity = 256})
    : _data = Float32List(math.max(capacity, 1) * embeddingDim);

  Float32List _data;
  final List<int> _ids = [];
  final Map<int, int> _slot = {};

  int get length => _ids.length;

  bool contains(int id) => _slot.containsKey(id);

  void add(int id, Float32List vector) {
    final unit = _unit(vector);
    final existing = _slot[id];
    if (existing != null) {
      _data.setRange(
        existing * embeddingDim,
        (existing + 1) * embeddingDim,
        unit,
      );
      return;
    }
    if ((_ids.length + 1) * embeddingDim > _data.length) {
      final grown = Float32List(_data.length * 2);
      grown.setRange(0, _ids.length * embeddingDim, _data);
      _data = grown;
    }
    final slot = _ids.length;
    _data.setRange(slot * embeddingDim, (slot + 1) * embeddingDim, unit);
    _ids.add(id);
    _slot[id] = slot;
  }

  void remove(int id) {
    final slot = _slot.remove(id);
    if (slot == null) return;
    final last = _ids.length - 1;
    if (slot != last) {
      _data.setRange(
        slot * embeddingDim,
        (slot + 1) * embeddingDim,
        _data,
        last * embeddingDim,
      );
      final movedId = _ids[last];
      _ids[slot] = movedId;
      _slot[movedId] = slot;
    }
    _ids.removeLast();
  }

  IndexHit? nearest(Float32List query) {
    if (_ids.isEmpty) return null;
    final q = _unit(query);
    var bestSlot = -1;
    var best = -2.0;
    final data = _data;
    final n = _ids.length;
    for (var s = 0; s < n; s++) {
      final base = s * embeddingDim;
      var dot = 0.0;
      for (var i = 0; i < embeddingDim; i++) {
        dot += data[base + i] * q[i];
      }
      if (dot > best) {
        best = dot;
        bestSlot = s;
      }
    }
    return bestSlot < 0 ? null : IndexHit(_ids[bestSlot], best);
  }

  List<IndexHit?> nearestMany(List<Float32List> queries) => [
    for (final q in queries) nearest(q),
  ];
}

/// Runs the search on the calling isolate. Fine for tests and for small libraries.
class InMemoryEmbeddingIndex implements EmbeddingIndex {
  final EmbeddingMatrix _matrix = EmbeddingMatrix();

  @override
  Future<void> addAll(List<(int, Float32List)> items) async {
    for (final (id, vector) in items) {
      _matrix.add(id, vector);
    }
  }

  @override
  Future<void> remove(Iterable<int> ids) async => ids.forEach(_matrix.remove);

  @override
  Future<List<IndexHit?>> nearest(List<Float32List> queries) async =>
      _matrix.nearestMany(queries);

  @override
  Future<int> size() async => _matrix.length;

  @override
  Future<void> dispose() async {}
}

// ---- the isolate ------------------------------------------------------------------

/// Keeps the matrix in a background isolate, so adding thousands of faces or searching a big
/// library never janks the UI. Requests are answered in order.
class IsolateEmbeddingIndex implements EmbeddingIndex {
  IsolateEmbeddingIndex._(this._isolate, this._commands, this._receive);

  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _receive;
  final Map<int, Completer<Object?>> _pending = {};
  var _nextRequest = 0;
  var _closed = false;

  static Future<IsolateEmbeddingIndex> spawn() async {
    final receive = ReceivePort();
    final isolate = await Isolate.spawn(_worker, receive.sendPort);
    final ready = Completer<SendPort>();
    late IsolateEmbeddingIndex index;
    receive.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
      } else if (message is List && message.length == 3) {
        final completer = index._pending.remove(message[0] as int);
        if (completer == null) return;
        if (message[1] == true) {
          completer.complete(message[2]);
        } else {
          completer.completeError(StateError('${message[2]}'));
        }
      }
    });
    index = IsolateEmbeddingIndex._(isolate, await ready.future, receive);
    return index;
  }

  Future<Object?> _request(String op, Object? payload) {
    if (_closed) throw StateError('The embedding index is closed');
    final id = _nextRequest++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _commands.send([id, op, payload]);
    return completer.future;
  }

  @override
  Future<void> addAll(List<(int, Float32List)> items) async {
    if (items.isEmpty) return;
    final ids = Int32List(items.length);
    final flat = Float32List(items.length * embeddingDim);
    for (var i = 0; i < items.length; i++) {
      ids[i] = items[i].$1;
      flat.setRange(i * embeddingDim, (i + 1) * embeddingDim, items[i].$2);
    }
    await _request('add', [ids, flat]);
  }

  @override
  Future<void> remove(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await _request('remove', Int32List.fromList(list));
  }

  @override
  Future<List<IndexHit?>> nearest(List<Float32List> queries) async {
    if (queries.isEmpty) return const [];
    final flat = Float32List(queries.length * embeddingDim);
    for (var i = 0; i < queries.length; i++) {
      flat.setRange(i * embeddingDim, (i + 1) * embeddingDim, queries[i]);
    }
    final reply = await _request('nearest', flat) as List;
    final ids = reply[0] as Int32List;
    final cosines = reply[1] as Float64List;
    return [
      for (var i = 0; i < ids.length; i++)
        ids[i] < 0 ? null : IndexHit(ids[i], cosines[i]),
    ];
  }

  @override
  Future<int> size() async => await _request('size', null) as int;

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _commands.send([-1, 'close', null]);
    _receive.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
    for (final c in _pending.values) {
      c.completeError(StateError('The embedding index was closed'));
    }
    _pending.clear();
  }

  static void _worker(SendPort main) {
    final commands = ReceivePort();
    main.send(commands.sendPort);
    final matrix = EmbeddingMatrix();
    commands.listen((message) {
      final request = message as List;
      final id = request[0] as int;
      final op = request[1] as String;
      try {
        switch (op) {
          case 'add':
            final payload = request[2] as List;
            final ids = payload[0] as Int32List;
            final flat = payload[1] as Float32List;
            for (var i = 0; i < ids.length; i++) {
              matrix.add(
                ids[i],
                Float32List.sublistView(
                  flat,
                  i * embeddingDim,
                  (i + 1) * embeddingDim,
                ),
              );
            }
            main.send([id, true, null]);
          case 'remove':
            for (final removed in request[2] as Int32List) {
              matrix.remove(removed);
            }
            main.send([id, true, null]);
          case 'nearest':
            final flat = request[2] as Float32List;
            final count = flat.length ~/ embeddingDim;
            final ids = Int32List(count);
            final cosines = Float64List(count);
            for (var i = 0; i < count; i++) {
              final hit = matrix.nearest(
                Float32List.sublistView(
                  flat,
                  i * embeddingDim,
                  (i + 1) * embeddingDim,
                ),
              );
              ids[i] = hit?.id ?? -1;
              cosines[i] = hit?.cosine ?? -1;
            }
            main.send([
              id,
              true,
              [ids, cosines],
            ]);
          case 'size':
            main.send([id, true, matrix.length]);
          case 'close':
            commands.close();
          default:
            main.send([id, false, 'unknown operation $op']);
        }
      } catch (e) {
        main.send([id, false, '$e']);
      }
    });
  }
}
