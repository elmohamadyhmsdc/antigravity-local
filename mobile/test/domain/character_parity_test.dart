// Drawn characters get what people get from a scan: exposed / covered regions, body vectors,
// poses (keypoints + action frames) and the user's earlier decisions about a figure.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/domain/scan/photo_result_store.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture() =>
    jsonDecode(
          File(
            '../the app/mobile_api/contract/fixtures/AnalyzeImageResponse.character_face_body.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

String vector384() {
  final v = Float32List(384)..[0] = 1;
  return base64Encode(v.buffer.asUint8List());
}

void main() {
  late AppDatabase db;
  late Directory tmp;
  late PhotoResultStore store;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('ag_char_parity_');
    store = PhotoResultStore(
      db: db,
      files: FileStore(Directory('${tmp.path}/crops')),
      index: InMemoryEmbeddingIndex(),
    );
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<MediaRow> media(String asset) async {
    final id = await db
        .into(db.media)
        .insert(MediaCompanion.insert(assetId: asset, kind: 'photo'));
    return (db.select(db.media)..where((m) => m.id.equals(id))).getSingle();
  }

  Map<String, dynamic> withExtras() {
    final json = fixture();
    final body = ((json['characters'] as List).single as Map)['body'] as Map;
    body['chest_embedding'] = vector384();
    body['morphology'] = {'shoulder_ratio': 1.2};
    json['sensitive_regions'] = [
      {
        'label': 'FEMALE_BREAST_EXPOSED',
        'exposed': true,
        'score': 0.9,
        'bbox': {'x': 50, 'y': 90, 'w': 30, 'h': 30},
        'body_index': null,
        'character_index': 0,
      },
      {
        'label': 'BELLY_EXPOSED',
        'exposed': true,
        'score': 0.8,
        'bbox': {'x': 50, 'y': 130, 'w': 30, 'h': 20},
        'body_index': null,
      },
    ];
    return json;
  }

  test(
    'a character body keeps its exposed regions, vectors and keypoints',
    () async {
      final m = await media('anime-1');
      await store.store(m, AnalyzeImageResponse.fromJson(withExtras()));

      final bodies = await (db.select(
        db.bodies,
      )..where((b) => b.mediaId.equals(m.id))).get();
      expect(bodies, hasLength(1));
      final body = bodies.single;
      expect(body.kind, 'character');
      expect(body.chestEmbedding, isNotNull);
      expect(body.morphology, contains('shoulder_ratio'));
      expect(body.kpts, isNotNull);

      final regions = await db.select(db.sensitiveRegions).get();
      expect(regions, hasLength(2));
      final onBody = regions.firstWhere(
        (r) => r.label == 'FEMALE_BREAST_EXPOSED',
      );
      expect(
        onBody.bodyId,
        body.id,
        reason: 'attached to the character\'s body',
      );
      final loose = regions.firstWhere((r) => r.label == 'BELLY_EXPOSED');
      expect(loose.bodyId, isNull);

      final stored = await (db.select(
        db.media,
      )..where((x) => x.id.equals(m.id))).getSingle();
      expect(stored.bodyEmbeddingVersion, isNonZero);
    },
  );

  test(
    'rescanning keeps one body and refreshes its vectors; poses are rebuilt',
    () async {
      final m = await media('anime-2');
      final first = fixture();
      await store.store(m, AnalyzeImageResponse.fromJson(first));
      final id = (await db.select(db.bodies).getSingle()).id;
      await db
          .into(db.bodyPoseFeatures)
          .insert(
            BodyPoseFeaturesCompanion.insert(
              bodyId: Value(id),
              version: 1,
              feature: Uint8List(136),
              visibleMask: 0,
              scaleSource: 'torso',
            ),
          );

      await store.store(m, AnalyzeImageResponse.fromJson(withExtras()));

      final bodies = await db.select(db.bodies).get();
      expect(bodies, hasLength(1));
      expect(bodies.single.chestEmbedding, isNotNull);
      expect(await db.select(db.bodyPoseFeatures).get(), isEmpty);
    },
  );

  test('a figure the user hid stays hidden when it is scanned again', () async {
    final m = await media('anime-3');
    final response = AnalyzeImageResponse.fromJson(fixture());
    final box = response.characters.single.body!.bbox.normalized(
      response.imageW,
      response.imageH,
    );
    await db
        .into(db.bodyOverrides)
        .insert(
          BodyOverridesCompanion.insert(
            assetId: m.assetId,
            x: box.x,
            y: box.y,
            w: box.w,
            h: box.h,
            ownership: const Value('none'),
            hidden: const Value(true),
          ),
        );

    await store.store(m, response);

    final body = await db.select(db.bodies).getSingle();
    expect(body.hidden, isTrue);
    expect(body.ownership, 'none');
  });
}
