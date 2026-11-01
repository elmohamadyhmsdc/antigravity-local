import 'dart:convert';
import 'dart:ui' as ui;

import 'package:drift/drift.dart';

import '../../data/api/dtos/analyze.dart';
import '../../data/api/equipment_api.dart';
import '../../data/api/mobile_api.dart';
import '../../data/db/app_database.dart';
import '../../data/media/media_library.dart';

const equipmentVersion = 1;

class EquipmentLibrary {
  EquipmentLibrary({required this.db, required this.media, required this.api});
  final AppDatabase db;
  final MediaLibrary media;
  final MobileApi? Function() api;
  bool _running = false;

  Future<List<EquipmentObjectRow>> objects({int? mediaId, String? label}) =>
      (db.select(db.equipmentObjects)
            ..where(
              (o) =>
                  o.state.equals('rejected').not() &
                  (mediaId == null
                      ? const Constant(true)
                      : o.mediaId.equals(mediaId)) &
                  (label == null
                      ? const Constant(true)
                      : o.label.equals(label)),
            )
            ..orderBy([
              (o) => OrderingTerm.desc(o.mediaId),
              (o) => OrderingTerm.asc(o.id),
            ]))
          .get();

  Future<void> correct(
    EquipmentObjectRow object,
    String label,
    int? bodyId,
  ) async {
    final name = label.trim().toLowerCase();
    if (name.isEmpty || name.length > 80) {
      throw ArgumentError('An equipment name is required');
    }
    if (bodyId != null) {
      final body =
          await (db.select(db.bodies)..where(
                (b) => b.id.equals(bodyId) & b.mediaId.equals(object.mediaId),
              ))
              .getSingleOrNull();
      if (body == null) throw ArgumentError('Choose a person from this photo');
    }
    await (db.update(
      db.equipmentObjects,
    )..where((o) => o.id.equals(object.id))).write(
      EquipmentObjectsCompanion(
        label: Value(name),
        bodyId: Value(bodyId),
        state: const Value('confirmed'),
      ),
    );
  }

  Future<void> reject(EquipmentObjectRow object) =>
      (db.update(db.equipmentObjects)..where((o) => o.id.equals(object.id)))
          .write(const EquipmentObjectsCompanion(state: Value('rejected')));

  /// A missed object can be labelled offline without inventing its location.
  Future<void> add(int mediaId, String label, int? bodyId) async {
    final name = label.trim().toLowerCase();
    if (name.isEmpty || name.length > 80) {
      throw ArgumentError('An equipment name is required');
    }
    if (bodyId != null) {
      final body =
          await (db.select(db.bodies)
                ..where((b) => b.id.equals(bodyId) & b.mediaId.equals(mediaId)))
              .getSingleOrNull();
      if (body == null) throw ArgumentError('Choose a person from this photo');
    }
    await db
        .into(db.equipmentObjects)
        .insert(
          EquipmentObjectsCompanion.insert(
            mediaId: mediaId,
            bodyId: Value(bodyId),
            objectKey: 'manual:${DateTime.now().microsecondsSinceEpoch}',
            label: name,
            x: 0,
            y: 0,
            w: 0,
            h: 0,
            state: const Value('confirmed'),
          ),
        );
  }

  /// Manual corrections/rejections survive every subsequent automatic pass.
  Future<void> store(
    int mediaId,
    List<BodyRow> bodies,
    EquipmentResponse response,
  ) => db.transaction(() async {
    final prior = await (db.select(
      db.equipmentObjects,
    )..where((o) => o.mediaId.equals(mediaId))).get();
    await (db.delete(db.equipmentObjects)..where(
          (o) => o.mediaId.equals(mediaId) & o.state.equals('suggested'),
        ))
        .go();
    for (final object in response.objects) {
      final b = object.box;
      if (object.label.trim().isEmpty ||
          object.label.length > 80 ||
          [b.x, b.y, b.w, b.h].any((v) => !v.isFinite) ||
          b.w <= 0 ||
          b.h <= 0 ||
          b.x < 0 ||
          b.y < 0 ||
          b.x + b.w > 1.001 ||
          b.y + b.h > 1.001) {
        continue;
      }
      final corrected = prior.any((p) {
        if (p.state == 'suggested') return false;
        final index = object.bodyIndex;
        final owner = index != null && index >= 0 && index < bodies.length
            ? bodies[index].id
            : null;
        if (p.objectKey.startsWith('manual:') &&
            p.label == object.label &&
            p.bodyId == owner) {
          return true;
        }
        if (p.objectKey == object.key) return true;
        final intersection = (ui.Rect.fromLTWH(
          p.x,
          p.y,
          p.w,
          p.h,
        ).intersect(ui.Rect.fromLTWH(b.x, b.y, b.w, b.h)));
        final area = intersection.isEmpty
            ? 0.0
            : intersection.width * intersection.height;
        return area / (p.w * p.h + b.w * b.h - area) > 0.5;
      });
      if (corrected) continue;
      final index = object.bodyIndex;
      await db
          .into(db.equipmentObjects)
          .insertOnConflictUpdate(
            EquipmentObjectsCompanion.insert(
              mediaId: mediaId,
              bodyId: Value(
                index != null && index >= 0 && index < bodies.length
                    ? bodies[index].id
                    : null,
              ),
              objectKey: object.key,
              label: object.label,
              x: b.x,
              y: b.y,
              w: b.w,
              h: b.h,
            ),
          );
    }
    await db
        .into(db.equipmentPhotos)
        .insertOnConflictUpdate(
          EquipmentPhotosCompanion.insert(
            mediaId: Value(mediaId),
            version: response.version,
          ),
        );
  });

  Future<void> detectPhoto(int mediaId) async {
    final client = api();
    if (client is! EquipmentApi) {
      throw StateError('Connect to a PC with equipment recognition');
    }
    final row =
        await (db.select(db.media)
              ..where((m) => m.id.equals(mediaId) & m.kind.equals('photo')))
            .getSingleOrNull();
    if (row == null) {
      throw StateError('Equipment recognition currently supports photos');
    }
    final bodies =
        await (db.select(db.bodies)
              ..where((b) => b.mediaId.equals(mediaId) & b.frameNumber.isNull())
              ..orderBy([(b) => OrderingTerm.asc(b.id)])
              ..limit(64))
            .get();
    final bytes = await media.downscaledJpeg(
      row.assetId,
      width: row.width ?? 0,
      height: row.height ?? 0,
      maxSide: 1600,
    );
    if (bytes == null) throw StateError('The original photo is unavailable');
    final codec = await ui.instantiateImageCodec(bytes);
    late final int w, h;
    try {
      final frame = await codec.getNextFrame();
      w = frame.image.width;
      h = frame.image.height;
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
    final response = await (client as EquipmentApi).analyzeEquipment(bytes, [
      for (final b in bodies)
        SensitiveBodyTargetDto(
          bbox: BBox(
            x: b.bboxX * w,
            y: b.bboxY * h,
            w: b.bboxW * w,
            h: b.bboxH * h,
          ),
          kpts: _points(b.kpts, w, h),
        ),
    ]);
    // Body IDs may have been removed by a rescan while the PC was working.
    final current = await (db.select(
      db.bodies,
    )..where((b) => b.mediaId.equals(mediaId))).get();
    if (!bodies.every(
      (b) => current.any((c) => c.id == b.id && c.kpts == b.kpts),
    )) {
      throw StateError('The photo changed during equipment recognition');
    }
    await store(mediaId, bodies, response);
  }

  static List<List<double>>? _points(String? raw, int w, int h) {
    if (raw == null) return null;
    try {
      return [
        for (final p in jsonDecode(raw) as List)
          [
            (p[0] as num).toDouble() * w,
            (p[1] as num).toDouble() * h,
            (p[2] as num).toDouble(),
          ],
      ];
    } catch (_) {
      return null;
    }
  }

  /// Optional capability on the PC. One photo per transaction; failures leave
  /// the photo pending and never block the main person scan.
  Future<int> run({required bool Function() shouldContinue}) async {
    if (_running ||
        api() is! EquipmentApi ||
        await db.setting('equipment.auto') == 'false') {
      return 0;
    }
    _running = true;
    var done = 0;
    try {
      while (shouldContinue()) {
        final next = await db
            .customSelect(
              '''SELECT m.id FROM media m WHERE m.kind = 'photo'
          AND m.illustrated = 0 AND m.scan_status = 'done'
          AND EXISTS (SELECT 1 FROM bodies b WHERE b.media_id = m.id)
          AND NOT EXISTS (SELECT 1 FROM equipment_photos e WHERE e.media_id = m.id AND e.version >= ?)
          ORDER BY m.id LIMIT 1''',
              variables: [Variable.withInt(equipmentVersion)],
              readsFrom: {db.media, db.bodies, db.equipmentPhotos},
            )
            .getSingleOrNull();
        if (next == null) break;
        try {
          await detectPhoto(next.read<int>('id'));
          done++;
        } catch (_) {
          break;
        }
      }
    } finally {
      _running = false;
    }
    return done;
  }
}
