/// One user-owned action catalog for photo examples and video segments.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../domain/pose/action_matcher.dart';
import '../../domain/pose/pose_geometry.dart';
import '../db/app_database.dart';
import '../api/action_api.dart';
import '../api/api_exception.dart';
import 'action_frames.dart';

export '../../domain/pose/action_matcher.dart' show ActionPoseFrame;

class ActionParticipant {
  const ActionParticipant({required this.id, required this.name});
  final int id;
  final String name;
}

class ActionExample {
  const ActionExample({
    required this.id,
    required this.mediaId,
    required this.startMs,
    required this.endMs,
    required this.participantIds,
    required this.frameCount,
    required this.createdAt,
    this.kind = 'video',
    this.assetId = '',
    this.modifiedAt = 0,
    this.frames = const [],
  });
  final String id, kind, assetId;
  final int mediaId, startMs, endMs, frameCount, createdAt, modifiedAt;
  final List<int> participantIds;
  final List<ActionPoseFrame> frames;
  Map<String, dynamic> toJson() => {
    'id': id,
    'media': mediaId,
    'start': startMs,
    'end': endMs,
    'people': participantIds,
    'created': createdAt,
    'kind': kind,
    'asset': assetId,
    'modified': modifiedAt,
    'frames': [for (final f in frames) f.toJson()],
  };
  static ActionExample fromJson(Map<String, dynamic> j) => ActionExample(
    id: j['id'],
    mediaId: j['media'],
    startMs: j['start'],
    endMs: j['end'],
    participantIds: (j['people'] as List).cast<int>(),
    createdAt: j['created'],
    kind: j['kind'],
    assetId: j['asset'],
    modifiedAt: j['modified'],
    frameCount: (j['frames'] as List).length,
    frames: [
      for (final f in j['frames'])
        ActionPoseFrame.fromJson(Map<String, dynamic>.from(f)),
    ],
  );
}

class VideoActionMatch {
  const VideoActionMatch({
    required this.id,
    required this.actionId,
    required this.exampleId,
    required this.mediaId,
    required this.startMs,
    required this.endMs,
    required this.participantIds,
    required this.similarity,
    required this.state,
    this.kind = 'video',
    this.assetId = '',
    this.modifiedAt = 0,
  });
  final String id, actionId, exampleId, state, kind, assetId;
  final int mediaId, startMs, endMs, modifiedAt;
  final List<int> participantIds;
  final double similarity;
  Map<String, dynamic> toJson() => {
    'id': id,
    'action': actionId,
    'example': exampleId,
    'media': mediaId,
    'start': startMs,
    'end': endMs,
    'people': participantIds,
    'similarity': similarity,
    'state': state,
    'kind': kind,
    'asset': assetId,
    'modified': modifiedAt,
  };
  static VideoActionMatch fromJson(Map<String, dynamic> j) => VideoActionMatch(
    id: j['id'],
    actionId: j['action'],
    exampleId: j['example'],
    mediaId: j['media'],
    startMs: j['start'],
    endMs: j['end'],
    participantIds: (j['people'] as List).cast<int>(),
    similarity: (j['similarity'] as num).toDouble(),
    state: j['state'],
    kind: j['kind'],
    assetId: j['asset'],
    modifiedAt: j['modified'],
  );
}

class VideoAction {
  const VideoAction({
    required this.id,
    required this.name,
    required this.examples,
    required this.createdAt,
  });
  final String id, name;
  final List<ActionExample> examples;
  final int createdAt;
}

class _Document {
  _Document(this.action, this.matches);
  final VideoAction action;
  final List<VideoActionMatch> matches;
  Map<String, dynamic> toJson() => {
    'version': 1,
    'id': action.id,
    'name': action.name,
    'created': action.createdAt,
    'examples': [for (final e in action.examples) e.toJson()],
    'matches': [for (final m in matches) m.toJson()],
  };
  static _Document decode(String value) {
    final j = jsonDecode(value) as Map<String, dynamic>;
    if (j['version'] != 1) {
      throw const FormatException('Unknown action catalog version');
    }
    return _Document(
      VideoAction(
        id: j['id'],
        name: j['name'],
        createdAt: j['created'],
        examples: [
          for (final e in j['examples'])
            ActionExample.fromJson(Map<String, dynamic>.from(e)),
        ],
      ),
      [
        for (final m in j['matches'])
          VideoActionMatch.fromJson(Map<String, dynamic>.from(m)),
      ],
    );
  }
}

class _Frame {
  _Frame(this.time, this.poses, this.actorIds, this.people);
  final int time;
  final List<Pose> poses;
  final List<int> actorIds, people;
  late final ActionPoseFrame? feature = actionPoseFrame(time, poses);
}

class VideoActionsRepository {
  VideoActionsRepository(this.db, {this.remoteMatcher});
  final ActionMatchApi? Function()? remoteMatcher;
  final AppDatabase db;
  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${math.Random.secure().nextInt(0x7fffffff).toRadixString(36)}';
  Future<_Document?> _document(String id) async {
    final row = await (db.select(
      db.settings,
    )..where((s) => s.key.equals('$actionCatalogPrefix$id'))).getSingleOrNull();
    return row == null ? null : _Document.decode(row.value);
  }

  Future<void> _put(_Document d) => db.putSetting(
    '$actionCatalogPrefix${d.action.id}',
    jsonEncode(d.toJson()),
  );
  Stream<List<VideoAction>> watchActions() =>
      (db.select(
        db.settings,
      )..where((s) => s.key.like('$actionCatalogPrefix%'))).watch().map(
        (rows) =>
            [for (final r in rows) _Document.decode(r.value).action]
              ..sort((a, b) => a.name.compareTo(b.name)),
      );
  Future<VideoAction?> action(String id) async => (await _document(id))?.action;

  Future<String> saveAction(String name, {String? id}) => db.transaction(
    () async {
      final trimmed = name.trim();
      if (trimmed.isEmpty || trimmed.length > 80) {
        throw const FormatException('Use an action name of 1–80 characters.');
      }
      final old = id == null ? null : await _document(id);
      if (id != null && old == null) {
        throw const FormatException('This action no longer exists.');
      }
      final rows = await (db.select(
        db.settings,
      )..where((s) => s.key.like('$actionCatalogPrefix%'))).get();
      if (rows.any((r) {
        final a = _Document.decode(r.value).action;
        return a.id != id && a.name.toLowerCase() == trimmed.toLowerCase();
      })) {
        throw const FormatException(
          'That name already exists. Add an example to the existing action.',
        );
      }
      final key = id ?? _newId();
      await _put(
        _Document(
          VideoAction(
            id: key,
            name: trimmed,
            createdAt:
                old?.action.createdAt ?? DateTime.now().millisecondsSinceEpoch,
            examples: old?.action.examples ?? [],
          ),
          old?.matches ?? [],
        ),
      );
      return key;
    },
  );

  Future<List<MediaRow>> _media(String kind) =>
      (db.select(db.media)
            ..where((m) => m.kind.equals(kind) & m.scanStatus.equals('done'))
            ..orderBy([(m) => OrderingTerm.desc(m.id)]))
          .get();
  Future<List<MediaRow>> analyzedVideos() => _media('video');
  Future<List<MediaRow>> analyzedPhotos() => _media('photo');

  Future<List<_Frame>> _frames(
    MediaRow media, {
    List<int> selected = const [],
  }) async {
    final rows = await db
        .customSelect(
          '''SELECT b.id, COALESCE(b.track_id,b.id) AS actor,
      COALESCE(f.person_id,b.person_id) AS person, b.kpts, b.extent
      FROM bodies b LEFT JOIN faces f ON f.id=b.face_id
      WHERE b.media_id=? ORDER BY actor,b.id''',
          variables: [Variable.withInt(media.id)],
          readsFrom: {db.bodies, db.faces},
        )
        .get();
    final byId = {for (final r in rows) r.read<int>('id'): r};
    final raw = media.kind == 'video'
        ? await ActionFrameStore(db).load(media)
        : [
            {
              'time': 0,
              'width': media.width,
              'height': media.height,
              'bodies': [
                for (final r in rows)
                  {
                    'body': r.read<int>('id'),
                    'kpts': r.readNullable<String>('kpts') == null
                        ? null
                        : jsonDecode(r.read<String>('kpts')),
                    'extent': r.readNullable<String>('extent'),
                  },
              ],
            },
          ];
    final out = <_Frame>[];
    for (final frame in raw) {
      final entries = <({int actor, int? person, Pose? pose})>[];
      for (final b in frame['bodies'] as List) {
        final row = byId[b['body']];
        if (row == null) continue;
        final person = row.readNullable<int>('person');
        if (selected.isNotEmpty && !selected.contains(person)) continue;
        entries.add((
          actor: row.read<int>('actor'),
          person: person,
          pose: Pose.fromJson(
            jsonEncode(b['kpts']),
            frame['width'] as int?,
            frame['height'] as int?,
            extent: b['extent'] as String?,
          ),
        ));
      }
      entries.sort((a, b) => a.actor.compareTo(b.actor));
      if (entries.isEmpty ||
          entries.length > 6 ||
          entries.any((e) => e.pose == null) ||
          entries.map((e) => e.actor).toSet().length != entries.length ||
          (selected.isNotEmpty &&
              !selected.every((id) => entries.any((e) => e.person == id)))) {
        continue;
      }
      out.add(
        _Frame(
          frame['time'] as int,
          [for (final e in entries) e.pose!],
          [for (final e in entries) e.actor],
          [
            for (final e in entries)
              if (e.person != null) e.person!,
          ],
        ),
      );
    }
    return out;
  }

  Future<List<ActionParticipant>> participants(
    int mediaId,
    int startMs,
    int endMs,
  ) async {
    final m = await (db.select(
      db.media,
    )..where((m) => m.id.equals(mediaId))).getSingleOrNull();
    if (m == null) return [];
    final frames = await _frames(m);
    final ids = {
      for (final f in frames)
        if (m.kind == 'photo' || (f.time >= startMs && f.time <= endMs))
          ...f.people,
    };
    if (ids.isEmpty) return [];
    final people = await (db.select(
      db.persons,
    )..where((p) => p.id.isIn(ids))).get();
    return [
      for (final p in people)
        ActionParticipant(id: p.id, name: p.name ?? 'Person ${p.id}'),
    ];
  }

  Future<String> addPhotoExample({
    required String actionId,
    required int mediaId,
    List<int> participantIds = const [],
  }) => _addExample(actionId, mediaId, 0, 0, participantIds, 'photo');
  Future<String> addExample({
    required String actionId,
    required int mediaId,
    required int startMs,
    required int endMs,
    List<int> participantIds = const [],
  }) => _addExample(actionId, mediaId, startMs, endMs, participantIds, 'video');

  Future<String> _addExample(
    String actionId,
    int mediaId,
    int start,
    int end,
    List<int> selected,
    String kind,
  ) async {
    final media = await (db.select(
      db.media,
    )..where((m) => m.id.equals(mediaId))).getSingleOrNull();
    if (media == null || media.kind != kind || media.scanStatus != 'done') {
      throw const FormatException(
        'Choose analyzed media that is still in the library.',
      );
    }
    if (start < 0 ||
        end < start ||
        (kind == 'video' &&
            (end == start ||
                end - start > 120000 ||
                (media.durationMs != null && end > media.durationMs!)))) {
      throw const FormatException(
        'Choose a video segment of up to two minutes.',
      );
    }
    final source = (await _frames(media, selected: selected.toSet().toList()))
        .where((f) => kind == 'photo' || f.time >= start && f.time <= end)
        .toList();
    final features = [
      for (final f in source)
        if (f.feature != null) f.feature!,
    ];
    if (features.length != source.length ||
        features.isEmpty ||
        (kind == 'video' && (features.length < 3 || !_continuous(source)))) {
      throw const FormatException(
        'Not enough usable pose samples. Rescan this media; video examples need at least three consecutive sampled poses.',
      );
    }
    final id = _newId();
    await db.transaction(() async {
      final doc = await _document(actionId);
      if (doc == null) {
        throw const FormatException('This action no longer exists.');
      }
      if (doc.action.examples.length >= 100) {
        throw const FormatException('This action already has 100 examples.');
      }
      doc.action.examples.add(
        ActionExample(
          id: id,
          mediaId: mediaId,
          startMs: start,
          endMs: end,
          participantIds: {for (final f in source) ...f.people}.toList(),
          frameCount: features.length,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          kind: kind,
          assetId: media.assetId,
          modifiedAt: media.modifiedAt,
          frames: features,
        ),
      );
      await _put(doc);
    });
    return id;
  }

  Future<void> removeExample(String actionId, String exampleId) =>
      db.transaction(() async {
        final doc = await _document(actionId);
        if (doc == null) return;
        doc.action.examples.removeWhere((e) => e.id == exampleId);
        doc.matches.removeWhere(
          (m) => m.exampleId == exampleId && m.state == 'suggested',
        );
        await _put(doc);
      });
  Future<void> deleteAction(String id) => (db.delete(
    db.settings,
  )..where((s) => s.key.equals('$actionCatalogPrefix$id'))).go();
  Future<List<VideoActionMatch>> _validMatches(
    List<VideoActionMatch> matches,
  ) async {
    final ids = matches.map((m) => m.mediaId).toSet().toList();
    final media = <int, MediaRow>{};
    for (var start = 0; start < ids.length; start += 300) {
      final rows = await (db.select(
        db.media,
      )..where((m) => m.id.isIn(ids.skip(start).take(300)))).get();
      media.addAll({for (final m in rows) m.id: m});
    }
    return matches.where((m) {
      final source = media[m.mediaId];
      return source != null &&
          source.assetId == m.assetId &&
          source.modifiedAt == m.modifiedAt;
    }).toList();
  }

  Stream<List<VideoActionMatch>> watchMatches(String id) => db
      .customSelect(
        'SELECT value FROM settings WHERE key=?',
        variables: [Variable.withString('$actionCatalogPrefix$id')],
        readsFrom: {db.settings, db.media},
      )
      .watch()
      .asyncMap(
        (rows) => _validMatches(
          rows.isEmpty
              ? []
              : _Document.decode(rows.single.read<String>('value')).matches,
        ),
      );

  Future<void> reviewMatch(
    String actionId,
    String matchId, {
    required bool accepted,
  }) => db.transaction(() async {
    final doc = await _document(actionId);
    if (doc == null) return;
    final i = doc.matches.indexWhere((m) => m.id == matchId);
    if (i < 0) throw const FormatException('This match no longer exists.');
    final m = doc.matches[i];
    final media = await (db.select(
      db.media,
    )..where((r) => r.id.equals(m.mediaId))).getSingleOrNull();
    if (media == null ||
        media.assetId != m.assetId ||
        media.modifiedAt != m.modifiedAt) {
      throw const FormatException(
        'The source changed or was removed. Search again before reviewing it.',
      );
    }
    doc.matches[i] = VideoActionMatch(
      id: m.id,
      actionId: m.actionId,
      exampleId: m.exampleId,
      mediaId: m.mediaId,
      startMs: m.startMs,
      endMs: m.endMs,
      participantIds: m.participantIds,
      similarity: m.similarity,
      state: accepted ? 'confirmed' : 'rejected',
      kind: m.kind,
      assetId: m.assetId,
      modifiedAt: m.modifiedAt,
    );
    await _put(doc);
  });

  Future<List<VideoActionMatch>> search(
    String actionId, {
    Set<int>? mediaIds,
    double minSimilarity = .82,
    bool allowMirror = false,
  }) async {
    if (!minSimilarity.isFinite || minSimilarity < 0 || minSimilarity > 1) {
      throw ArgumentError.value(minSimilarity);
    }
    final doc = await _document(actionId);
    if (doc == null || doc.action.examples.isEmpty) {
      throw const FormatException('Add an action example first.');
    }
    final media = [
      ...await analyzedPhotos(),
      ...await analyzedVideos(),
    ].where((m) => mediaIds == null || mediaIds.contains(m.id));
    final proposals = <VideoActionMatch>[];
    for (final m in media) {
      final examples = doc.action.examples
          .where((e) => e.kind == m.kind)
          .toList();
      if (examples.isEmpty) continue;
      final frames = await _frames(m);
      final remote = remoteMatcher?.call();
      List<_Hit> ranked;
      try {
        ranked = remote == null
            ? await _rankFramesIsolated(
                frames,
                examples,
                m.kind,
                minSimilarity,
                allowMirror,
              )
            : await _rankFramesRemotely(
                remote,
                frames,
                examples,
                m.kind,
                minSimilarity,
                allowMirror,
              );
      } on ApiException catch (error) {
        if (!error.isOffline) rethrow;
        ranked = await _rankFramesIsolated(
          frames,
          examples,
          m.kind,
          minSimilarity,
          allowMirror,
        );
      }
      for (final hit in ranked) {
        final first = frames[hit.start], last = frames[hit.end];
        if (examples.any(
          (e) =>
              e.assetId == m.assetId &&
              (m.kind == 'photo' ||
                  _overlap(e.startMs, e.endMs, first.time, last.time) > .5),
        )) {
          continue;
        }
        final id = sha256
            .convert(
              utf8.encode(
                '${m.assetId}|${m.modifiedAt}|${first.time}|${last.time}|${first.poses.length}',
              ),
            )
            .toString();
        proposals.add(
          VideoActionMatch(
            id: id,
            actionId: actionId,
            exampleId: hit.exampleId,
            mediaId: m.id,
            startMs: first.time,
            endMs: last.time,
            participantIds: {
              for (final f in frames.sublist(hit.start, hit.end + 1))
                ...f.people,
            }.toList(),
            similarity: hit.score,
            state: 'suggested',
            kind: m.kind,
            assetId: m.assetId,
            modifiedAt: m.modifiedAt,
          ),
        );
      }
    }
    proposals.sort((a, b) => b.similarity.compareTo(a.similarity));
    final kept = <VideoActionMatch>[];
    for (final p in proposals) {
      if (kept.any(
        (k) =>
            k.assetId == p.assetId &&
            (p.kind == 'photo' ||
                _overlap(k.startMs, k.endMs, p.startMs, p.endMs) > .5),
      )) {
        continue;
      }
      kept.add(p);
      if (kept.length == 200) break;
    }
    await db.transaction(() async {
      final latest = await _document(actionId);
      if (latest == null) {
        throw const FormatException('This action was deleted.');
      }
      final validExamples = latest.action.examples.map((e) => e.id).toSet();
      final reviewed = latest.matches
          .where((m) => m.state != 'suggested')
          .toList();
      latest.matches
        ..clear()
        ..addAll(reviewed)
        ..addAll(
          kept.where(
            (p) =>
                validExamples.contains(p.exampleId) &&
                !reviewed.any(
                  (r) =>
                      r.assetId == p.assetId &&
                      r.modifiedAt == p.modifiedAt &&
                      (p.kind == 'photo' ||
                          _overlap(r.startMs, r.endMs, p.startMs, p.endMs) >
                              .5),
                ),
          ),
        );
      await _put(latest);
    });
    return _validMatches(
      (await _document(
        actionId,
      ))!.matches.where((m) => m.state != 'rejected').toList(),
    );
  }
}

bool _continuous(List<_Frame> frames) {
  if (frames.length < 3) return false;
  final actors = frames.first.actorIds.join(',');
  final gaps = [
    for (var i = 1; i < frames.length; i++) frames[i].time - frames[i - 1].time,
  ]..sort();
  if (gaps.first <= 0 ||
      gaps.last > 10000 ||
      gaps.last > math.max(1500, gaps[gaps.length ~/ 2] * 3)) {
    return false;
  }
  return frames.every((f) => f.actorIds.join(',') == actors);
}

double _overlap(int a, int b, int c, int d) =>
    math.max(0, math.min(b, d) - math.max(a, c)) /
    math.max(1, math.min(b - a, d - c));
typedef _Hit = ({int start, int end, String exampleId, double score});
typedef _Window = ({int start, int end, List<ActionPoseFrame> features});
List<ActionPoseFrame> _boundedFrames(List<ActionPoseFrame> frames) =>
    frames.length <= 20
    ? frames
    : [
        for (var i = 0; i < 20; i++)
          frames[(i * (frames.length - 1) / 19).round()],
      ];
Iterable<_Window> _windows(
  List<_Frame> frames,
  ActionExample example,
  String kind,
) sync* {
  for (var start = 0; start < frames.length; start++) {
    if (kind == 'photo') {
      final f = frames[start].feature;
      if (f != null) yield (start: start, end: start, features: [f]);
      continue;
    }
    final duration = example.frames.last.timeMs - example.frames.first.timeMs;
    final ends = <int>{};
    for (final tempo in [.65, .85, 1.0, 1.3, 1.7]) {
      final target = frames[start].time + duration * tempo;
      var low = start + 2, high = frames.length - 1;
      while (low < high) {
        final mid = (low + high) ~/ 2;
        if (frames[mid].time < target) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }
      if (low < frames.length) ends.add(low);
    }
    for (final end in ends) {
      final length = frames[end].time - frames[start].time;
      if (length < duration * .6 || length > duration * 1.75) continue;
      final window = frames.sublist(start, end + 1);
      if (!_continuous(window) || window.any((f) => f.feature == null)) {
        continue;
      }
      yield (
        start: start,
        end: end,
        features: _boundedFrames([for (final f in window) f.feature!]),
      );
    }
  }
}

List<_Hit> _rankFrames(
  List<_Frame> frames,
  List<ActionExample> examples,
  String kind,
  double threshold,
  bool mirror,
) {
  final hits = <_Hit>[];
  for (final e in examples) {
    for (final w in _windows(frames, e, kind)) {
      final score = compareActionSequences(
        e.frames,
        w.features,
        allowMirror: mirror,
      );
      if (score != null && score >= threshold) {
        hits.add((start: w.start, end: w.end, exampleId: e.id, score: score));
      }
    }
  }
  return hits;
}

Future<List<_Hit>> _rankFramesRemotely(
  ActionMatchApi api,
  List<_Frame> frames,
  List<ActionExample> examples,
  String kind,
  double threshold,
  bool mirror,
) async {
  final hits = <_Hit>[];
  for (final e in examples) {
    final batch = <_Window>[];
    Future<void> send() async {
      if (batch.isEmpty) return;
      final scores = await api.compareActions(
        kind: kind,
        query: [for (final f in _boundedFrames(e.frames)) f.toJson()],
        allowMirror: mirror,
        candidates: [
          for (var i = 0; i < batch.length; i++)
            (id: '$i', frames: [for (final f in batch[i].features) f.toJson()]),
        ],
      );
      for (var i = 0; i < batch.length; i++) {
        final score = scores['$i'];
        if (score != null && score >= threshold) {
          hits.add((
            start: batch[i].start,
            end: batch[i].end,
            exampleId: e.id,
            score: score,
          ));
        }
      }
      batch.clear();
    }

    for (final window in _windows(frames, e, kind)) {
      batch.add(window);
      if (batch.length == 64) await send();
    }
    await send();
  }
  return hits;
}

Future<List<_Hit>> _rankFramesIsolated(
  List<_Frame> frames,
  List<ActionExample> examples,
  String kind,
  double threshold,
  bool mirror,
) => Isolate.run(() => _rankFrames(frames, examples, kind, threshold, mirror));
