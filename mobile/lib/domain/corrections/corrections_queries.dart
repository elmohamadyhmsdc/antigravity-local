import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';

class ExcludedCounts {
  const ExcludedCounts({
    required this.facesNone,
    required this.facesDismissed,
    required this.bodiesNone,
    required this.bodiesHidden,
    required this.equipmentRejected,
    required this.sensitiveDismissed,
  });

  final int facesNone;
  final int facesDismissed;
  final int bodiesNone;
  final int bodiesHidden;
  final int equipmentRejected;
  final int sensitiveDismissed;

  int get total =>
      facesNone +
      facesDismissed +
      bodiesNone +
      bodiesHidden +
      equipmentRejected +
      sensitiveDismissed;
}

class MediaLinkItem {
  const MediaLinkItem({
    required this.type,
    required this.elementId,
    required this.targetLabel,
    this.methodLabel,
    this.targetId,
  });

  final String type; // 'body_person', 'body_body', 'equipment_owner'
  final int elementId;
  final String targetLabel;
  final String? methodLabel;
  final int? targetId;
}

class CorrectionsQueries {
  const CorrectionsQueries(this.db);
  final AppDatabase db;

  Future<ExcludedCounts> excludedCounts() async {
    final facesNone = await (db.select(
      db.faces,
    )..where((f) => f.ownership.equals('none'))).get();
    final facesDismissed =
        await (db.select(db.faces)..where(
              (f) => f.reviewDismissed.equals(true) & f.ownership.isNull(),
            ))
            .get();
    final bodiesNone = await (db.select(
      db.bodies,
    )..where((b) => b.ownership.equals('none'))).get();
    final bodiesHidden = await (db.select(
      db.bodies,
    )..where((b) => b.hidden.equals(true))).get();
    final equipmentRejected = await (db.select(
      db.equipmentObjects,
    )..where((e) => e.state.equals('rejected'))).get();
    final sensitiveDismissed = await (db.select(
      db.sensitiveRegions,
    )..where((s) => s.userState.equals('dismissed'))).get();

    return ExcludedCounts(
      facesNone: facesNone.length,
      facesDismissed: facesDismissed.length,
      bodiesNone: bodiesNone.length,
      bodiesHidden: bodiesHidden.length,
      equipmentRejected: equipmentRejected.length,
      sensitiveDismissed: sensitiveDismissed.length,
    );
  }

  Future<List<int>> noOwnerIds(String kind) async {
    if (kind == 'face') {
      final rows = await (db.select(
        db.faces,
      )..where((f) => f.ownership.equals('none'))).get();
      return rows.map((r) => r.id).toList();
    } else if (kind == 'body') {
      final rows = await (db.select(
        db.bodies,
      )..where((b) => b.ownership.equals('none'))).get();
      return rows.map((r) => r.id).toList();
    }
    return const [];
  }

  Future<List<MediaLinkItem>> linksForMedia(int mediaId) async {
    final links = <MediaLinkItem>[];

    // Bodies linked to persons
    final bodies = await db
        .customSelect(
          '''
      SELECT b.id, b.person_id, b.link_method, p.name AS person_name
      FROM bodies b
      LEFT JOIN persons p ON p.id = b.person_id
      WHERE b.media_id = ? AND b.person_id IS NOT NULL AND b.hidden = 0
      ''',
          variables: [Variable.withInt(mediaId)],
          readsFrom: {db.bodies, db.persons},
        )
        .get();

    for (final r in bodies) {
      links.add(
        MediaLinkItem(
          type: 'body_person',
          elementId: r.read<int>('id'),
          targetLabel:
              r.read<String?>('person_name') ??
              'Person #${r.read<int>('person_id')}',
          methodLabel: r.read<String?>('link_method'),
          targetId: r.read<int>('person_id'),
        ),
      );
    }

    // Equipment linked to owners
    final equipments = await db
        .customSelect(
          '''
      SELECT e.id, e.label, e.body_id
      FROM equipment_objects e
      WHERE e.media_id = ? AND e.body_id IS NOT NULL AND e.state != 'rejected'
      ''',
          variables: [Variable.withInt(mediaId)],
          readsFrom: {db.equipmentObjects},
        )
        .get();

    for (final r in equipments) {
      links.add(
        MediaLinkItem(
          type: 'equipment_owner',
          elementId: r.read<int>('id'),
          targetLabel: 'Body #${r.read<int>('body_id')}',
          methodLabel: r.read<String>('label'),
          targetId: r.read<int>('body_id'),
        ),
      );
    }

    return links;
  }
}
