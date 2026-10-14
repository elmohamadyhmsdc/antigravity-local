import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../api/dtos/embedding.dart';
import '../db/app_database.dart';
import 'embedding_index.dart';

/// Reads every stored face into [index] (pages of [pageSize], oldest first).
Future<void> loadFacesIntoIndex(
  AppDatabase db,
  EmbeddingIndex index, {
  int pageSize = 2000,
}) async {
  var lastId = 0;
  while (true) {
    final rows = await db
        .customSelect(
          'SELECT id, embedding FROM faces WHERE id > ? ORDER BY id LIMIT ?',
          variables: [Variable.withInt(lastId), Variable.withInt(pageSize)],
          readsFrom: {db.faces},
        )
        .get();
    if (rows.isEmpty) return;
    await index.addAll([
      for (final r in rows)
        (r.read<int>('id'), embeddingFromBlob(r.read<Uint8List>('embedding'))),
    ]);
    lastId = rows.last.read<int>('id');
  }
}

/// The index of the library's faces, created and filled the first time something needs it - so the
/// app starts instantly and a 100k-face library loads in the background, not on the UI thread.
class LazyEmbeddingIndex implements EmbeddingIndex {
  LazyEmbeddingIndex(this._create);

  final Future<EmbeddingIndex> Function() _create;
  Future<EmbeddingIndex>? _inner;
  var _disposed = false;

  Future<EmbeddingIndex> get _ready => _inner ??= _create();

  @override
  Future<void> addAll(List<(int, Float32List)> items) async =>
      (await _ready).addAll(items);

  @override
  Future<void> remove(Iterable<int> ids) async => (await _ready).remove(ids);

  @override
  Future<List<IndexHit?>> nearest(List<Float32List> queries) async =>
      (await _ready).nearest(queries);

  @override
  Future<int> size() async => (await _ready).size();

  /// Throws the loaded index away: it is rebuilt from the database on next use (after a restore).
  Future<void> reload() async {
    final old = _inner;
    _inner = null;
    if (old != null) await (await old).dispose();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final inner = _inner;
    _inner = null;
    if (inner != null) await (await inner).dispose();
  }
}
