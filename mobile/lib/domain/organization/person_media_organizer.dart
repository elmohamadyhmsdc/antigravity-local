import 'dart:convert';

import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';
import '../../data/platform/media_organizer.dart';

/// A readable, portable single path component; never accepts a path supplied as a name.
String organizationSegment(String name, {String fallback = 'Unnamed'}) {
  var value = name
      .trim()
      .replaceAll(RegExp(r'[\x00-\x1f/\\:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
  if (value.isEmpty) value = fallback;
  final out = StringBuffer();
  var bytes = 0;
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    final size = utf8.encode(character).length;
    if (bytes + size > 80) break;
    out.write(character);
    bytes += size;
  }
  return out.toString();
}

class PersonOrganizeItem {
  const PersonOrganizeItem({
    required this.media,
    required this.owners,
    required this.source,
    required this.ownerId,
    required this.sequence,
    required this.request,
    required this.status,
  });
  final MediaRow media;
  final List<PersonRow> owners;
  final OriginalMediaInfo? source;
  final int? ownerId;
  final int sequence;
  final OriginalMediaMove? request;
  final String status;
  bool get canApply =>
      request != null && (status == 'ready' || status == 'already');
}

class PersonMediaOrganizer {
  PersonMediaOrganizer({
    required this.db,
    required this.bridge,
    this.beforeMove,
    this.afterMove,
  });
  final AppDatabase db;
  final MediaOrganizerBridge bridge;
  final Future<void> Function()? beforeMove;
  final void Function()? afterMove;
  bool _busy = false;
  bool get isRunning => _busy;

  /// Detection occurrences cover deduplicated faces in other photos/videos.
  /// Direct rows also support older/imported records without occurrence rows.
  static const _links = '''
    SELECT d.media_id, COALESCE(f.person_id, bf.person_id, b.person_id) AS person_id
    FROM media_detections d LEFT JOIN faces f ON d.kind = 'f' AND f.id = d.ref_id
    LEFT JOIN bodies b ON d.kind = 'b' AND b.id = d.ref_id LEFT JOIN faces bf ON bf.id = b.face_id
    UNION SELECT media_id, person_id FROM faces WHERE media_id IS NOT NULL
    UNION SELECT b.media_id, COALESCE(f.person_id, b.person_id) FROM bodies b
      LEFT JOIN faces f ON f.id = b.face_id WHERE b.media_id IS NOT NULL''';

  Future<List<PersonOrganizeItem>> plan(
    Set<int> personIds, {
    Map<int, int?> choices = const {},
  }) async {
    if (personIds.isEmpty) return [];
    final people = await (db.select(
      db.persons,
    )..where((p) => p.id.isIn(personIds))).get();
    final peopleById = {for (final p in people) p.id: p};
    final links = await db
        .customSelect(
          'SELECT * FROM ($_links) WHERE person_id IN (${List.filled(personIds.length, '?').join(',')})',
          variables: [for (final id in personIds) Variable.withInt(id)],
          readsFrom: {db.mediaDetections, db.faces, db.bodies},
        )
        .get();
    final ownersByMedia = <int, Set<int>>{};
    for (final link in links) {
      final person = link.readNullable<int>('person_id');
      if (person != null && peopleById.containsKey(person))
        ownersByMedia
            .putIfAbsent(link.read<int>('media_id'), () => {})
            .add(person);
    }
    final media = <MediaRow>[];
    final ids = ownersByMedia.keys.toList();
    for (var i = 0; i < ids.length; i += 300) {
      media.addAll(
        await (db.select(
          db.media,
        )..where((m) => m.id.isIn(ids.skip(i).take(300)))).get(),
      );
    }
    media.sort((a, b) {
      final date = (a.takenAt ?? a.id).compareTo(b.takenAt ?? b.id);
      return date == 0 ? a.id.compareTo(b.id) : date;
    });
    final originals = <String, OriginalMediaInfo>{};
    for (var i = 0; i < media.length; i += 1000) {
      for (final original in await bridge.inspect([
        for (final m in media.skip(i).take(1000))
          OrganizeAsset(m.assetId, m.kind),
      ])) {
        originals[original.assetId] = original;
      }
    }
    final groups = await db.select(db.identityGroups).get();
    final allPeople = await db.select(db.persons).get();
    final journal = await db.select(db.personMediaMoves).get();
    final oldByMedia = {for (final j in journal) j.mediaId: j};
    final next = <String, int>{};
    for (final j in journal) {
      final key = '${j.personId}:${j.mediaKind}';
      if ((next[key] ?? 0) < j.sequence) next[key] = j.sequence;
    }
    String identityName(PersonRow p) => (p.name ?? '').trim().isNotEmpty
        ? p.name!.trim()
        : '${p.kind == 'character' ? 'Character' : 'Person'} ${p.id}';
    String groupFolder(int id) {
      final group = groups.where((g) => g.id == id).firstOrNull;
      if (group == null) return '';
      final base = organizationSegment(group.name);
      final duplicates = groups
          .where(
            (g) =>
                organizationSegment(g.name).toLowerCase() == base.toLowerCase(),
          )
          .length;
      return duplicates > 1 ? '${base}_$id' : base;
    }

    String personFolder(PersonRow p) {
      final base = organizationSegment(identityName(p));
      final duplicates = allPeople
          .where(
            (other) =>
                other.groupId == p.groupId &&
                organizationSegment(identityName(other)).toLowerCase() ==
                    base.toLowerCase(),
          )
          .length;
      return duplicates > 1 ? '${base}_${p.id}' : base;
    }

    final output = <PersonOrganizeItem>[];
    for (final m in media) {
      final owners = [for (final id in ownersByMedia[m.id]!) peopleById[id]!];
      final owner = choices.containsKey(m.id)
          ? choices[m.id]
          : owners.length == 1
          ? owners.single.id
          : null;
      final selected = owners.where((p) => p.id == owner).firstOrNull;
      final source = originals[m.assetId];
      String status = selected == null
          ? 'choose_owner'
          : source?.available != true
          ? 'missing'
          : 'ready';
      if (status == 'ready' &&
          m.modifiedAt > 0 &&
          source!.modifiedAt != m.modifiedAt)
        status = 'stale_scan';
      final prior = oldByMedia[m.id];
      if (prior?.state == 'pending') status = 'pending';
      var sequence = 0;
      OriginalMediaMove? request;
      if (selected != null && source?.available == true && status == 'ready') {
        final key = '${selected.id}:${m.kind}';
        if (prior != null && prior.personId == selected.id)
          sequence = prior.sequence;
        else {
          sequence = (next[key] ?? 0) + 1;
          next[key] = sequence;
        }
        final extension = source!.name.contains('.')
            ? source.name.split('.').last.toLowerCase()
            : m.kind == 'video'
            ? 'mp4'
            : 'jpg';
        if (!RegExp(r'^[a-z0-9]{1,12}$').hasMatch(extension))
          status = 'unsupported';
        final folder = personFolder(selected);
        final category = selected.groupId == null
            ? ''
            : groupFolder(selected.groupId!);
        final path =
            'DCIM/Your Gallery/${category.isEmpty ? '' : '$category/'}$folder/';
        final base = organizationSegment(
          identityName(selected),
        ).replaceAll(' ', '_');
        final name =
            '${base}_${m.kind == 'video' ? 'video' : 'image'}_${sequence.toString().padLeft(4, '0')}.$extension';
        request = OriginalMediaMove(
          asset: OrganizeAsset(m.assetId, m.kind),
          source: source,
          targetName: name,
          targetPath: path,
        );
      }
      output.add(
        PersonOrganizeItem(
          media: m,
          owners: owners,
          source: source,
          ownerId: selected?.id,
          sequence: sequence,
          request: request,
          status: status,
        ),
      );
    }
    return _preflight(output);
  }

  Future<List<PersonOrganizeItem>> _preflight(
    List<PersonOrganizeItem> items,
  ) async {
    final statuses = <String, String>{};
    final ready = items
        .where((i) => i.request != null && i.status == 'ready')
        .toList();
    for (var i = 0; i < ready.length; i += 1000) {
      for (final result in await bridge.preflight([
        for (final item in ready.skip(i).take(1000)) item.request!,
      ])) {
        statuses[result.assetId] = result.status;
      }
    }
    return [
      for (final item in items)
        PersonOrganizeItem(
          media: item.media,
          owners: item.owners,
          source: item.source,
          ownerId: item.ownerId,
          sequence: item.sequence,
          request: item.request,
          status: item.status == 'ready'
              ? statuses[item.media.assetId] ?? 'failed'
              : item.status,
        ),
    ];
  }

  Future<List<PersonOrganizeItem>> pending() async {
    final records = await (db.select(
      db.personMediaMoves,
    )..where((m) => m.state.equals('pending'))).get();
    final items = <PersonOrganizeItem>[];
    for (final j in records) {
      final media = await (db.select(
        db.media,
      )..where((m) => m.id.equals(j.mediaId))).getSingleOrNull();
      if (media == null || media.assetId != j.assetId) continue;
      final owner = j.personId == null
          ? null
          : await (db.select(
              db.persons,
            )..where((p) => p.id.equals(j.personId!))).getSingleOrNull();
      final source = OriginalMediaInfo(
        assetId: j.assetId,
        name: j.sourceName,
        path: j.sourcePath,
        modifiedAt: j.sourceModifiedAt,
        size: j.sourceSize,
      );
      items.add(
        PersonOrganizeItem(
          media: media,
          owners: [if (owner != null) owner],
          source: source,
          ownerId: j.personId,
          sequence: j.sequence,
          request: OriginalMediaMove(
            asset: OrganizeAsset(j.assetId, j.mediaKind),
            source: source,
            targetName: j.targetName,
            targetPath: j.targetPath,
          ),
          status: 'ready',
        ),
      );
    }
    return _preflight(items);
  }

  /// Only explicit, previewed requests reach the bridge. Unknown outcomes stay
  /// pending and can be reconciled against the unchanged MediaStore asset ID.
  Future<List<OriginalMoveResult>> apply(
    List<PersonOrganizeItem> items, {
    void Function(int, int)? onProgress,
  }) async {
    if (_busy) throw StateError('A media move is already running');
    final selected = items.where((i) => i.canApply).toList();
    if (selected.isEmpty) return [];
    _busy = true;
    final results = <OriginalMoveResult>[];
    try {
      await beforeMove?.call();
      await db.transaction(() async {
        for (final item in selected) {
          final r = item.request!;
          await db
              .into(db.personMediaMoves)
              .insertOnConflictUpdate(
                PersonMediaMovesCompanion.insert(
                  mediaId: Value(item.media.id),
                  personId: Value(item.ownerId),
                  assetId: item.media.assetId,
                  mediaKind: item.media.kind,
                  sourceName: r.source.name,
                  sourcePath: r.source.path,
                  targetName: r.targetName,
                  targetPath: r.targetPath,
                  sourceModifiedAt: r.source.modifiedAt,
                  sourceSize: r.source.size,
                  state: 'pending',
                  sequence: item.sequence,
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                ),
              );
        }
      });
      var done = 0;
      for (var i = 0; i < selected.length; i += 1000) {
        final batch = selected.skip(i).take(1000).toList();
        final response = await bridge.move([
          for (final item in batch) item.request!,
        ]);
        for (final result in response) {
          final item = batch
              .where((i) => i.media.assetId == result.assetId)
              .firstOrNull;
          if (item == null) continue;
          await db.transaction(() async {
            final actual = result.actual;
            if (result.moved &&
                actual != null &&
                actual.assetId == item.media.assetId) {
              await (db.update(db.media)..where(
                    (m) =>
                        m.id.equals(item.media.id) &
                        m.assetId.equals(item.media.assetId),
                  ))
                  .write(MediaCompanion(modifiedAt: Value(actual.modifiedAt)));
            }
            final complete = result.moved && actual != null;
            await (db.update(
              db.personMediaMoves,
            )..where((j) => j.mediaId.equals(item.media.id))).write(
              PersonMediaMovesCompanion(
                state: Value(
                  complete
                      ? 'moved'
                      : result.status == 'uncertain'
                      ? 'pending'
                      : result.status,
                ),
                targetName: complete
                    ? Value(actual.name)
                    : const Value.absent(),
                targetPath: complete
                    ? Value(actual.path)
                    : const Value.absent(),
                detail: Value(result.detail),
                updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
              ),
            );
          });
          results.add(result);
          done++;
          onProgress?.call(done, selected.length);
        }
        if (response.any((r) => r.status == 'cancelled')) break;
      }
    } finally {
      _busy = false;
      afterMove?.call();
    }
    return results;
  }
}
