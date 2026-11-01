import 'dart:convert';
import 'dart:io';

import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/repositories/app_settings.dart';
import 'package:antigravity_mobile/domain/scan/photo_result_store.dart';
import 'package:antigravity_mobile/domain/scan/redetect.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Map<String, dynamic> response({double shift = 0, bool extraFace = false}) {
  final json =
      jsonDecode(
            File(
              '../the app/mobile_api/contract/fixtures/AnalyzeImageResponse.two_faces_one_body.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final key in ['faces', 'bodies']) {
    for (final d in json[key] as List) {
      final box = d['bbox'] as Map<String, dynamic>;
      box['x'] = (box['x'] as num) + shift;
    }
  }
  if (extraFace) {
    final faces = json['faces'] as List;
    final copy = jsonDecode(jsonEncode(faces.first)) as Map<String, dynamic>;
    copy['bbox'] = {'x': 20.0, 'y': 20.0, 'w': 150.0, 'h': 180.0};
    copy['passes_gate'] = true;
    faces.add(copy);
  }
  return json;
}

void main() {
  late AppDatabase db;
  late Directory tmp;
  late PhotoResultStore store;
  late FakeMobileApi api;
  late FakeMediaLibrary media;
  late Redetector redetector;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('gallery_redetect_test_');
    final files = FileStore(Directory('${tmp.path}/crops'));
    final index = InMemoryEmbeddingIndex();
    store = PhotoResultStore(db: db, files: files, index: index);
    api = FakeMobileApi();
    media = FakeMediaLibrary();
    redetector = Redetector(
      db: db,
      files: files,
      index: index,
      store: store,
      media: media,
      settings: AppSettings(db),
      api: () => api,
    );
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<MediaRow> photo(String asset, {String kind = 'photo'}) async {
    final id = await db
        .into(db.media)
        .insert(MediaCompanion.insert(assetId: asset, kind: kind));
    final row = await (db.select(
      db.media,
    )..where((m) => m.id.equals(id))).getSingle();
    if (kind == 'photo') {
      await store.store(row, AnalyzeImageResponse.fromJson(response()));
    }
    return row;
  }

  Future<int> person(String name) => db
      .into(db.persons)
      .insert(PersonsCompanion.insert(name: Value(name), createdAt: 1));

  Future<List<FaceRow>> faces() => db.select(db.faces).get();
  Future<List<BodyRow>> bodies() => db.select(db.bodies).get();

  test(
    'faces and bodies are replaced; names and decisions follow the new box',
    () async {
      final m = await photo('a');
      final ali = await person('Ali'), other = await person('Other');
      final old = (await faces()).single;
      await db.customUpdate(
        'UPDATE faces SET person_id = ?, hidden = 1',
        variables: [Variable.withInt(ali)],
      );
      await db
          .into(db.faceRejections)
          .insert(
            FaceRejectionsCompanion.insert(faceId: old.id, personId: other),
          );
      final oldBody = (await bodies()).single;

      api.analyzeResult = AnalyzeImageResponse.fromJson(response(shift: 6));
      final out = await redetector.photo(m.id, RedetectPart.both);

      expect(out!.faces, 1);
      expect(out.bodies, 1);
      final face = (await faces()).single;
      expect(face.id, isNot(old.id), reason: 'a new box replaced the old one');
      expect(face.personId, ali);
      expect(face.hidden, isTrue);
      expect(face.bboxX, closeTo((412.5 + 6) / 1280, 1e-4));
      final rejections = await db.select(db.faceRejections).get();
      expect(rejections.single.faceId, face.id);
      expect(rejections.single.personId, other);
      final body = (await bodies()).single;
      expect(body.id, isNot(oldBody.id));
      expect(body.faceId, face.id);

      // It looked harder than a scan.
      final sent = api.analyzeOptions.single;
      expect(sent.bodyScore, redetectBodyScore);
      expect(sent.minQuality, redetectMinQuality);
      expect(media.maxSides.single, redetectMaxSide);
    },
  );

  test('bodies only: faces keep their rows, no face is added', () async {
    final m = await photo('b');
    final face = (await faces()).single;
    final oldBody = (await bodies()).single;
    api.analyzeResult = AnalyzeImageResponse.fromJson(
      response(shift: 4, extraFace: true),
    );
    await redetector.photo(m.id, RedetectPart.bodies);
    expect((await faces()).map((f) => f.id), [face.id]);
    final body = (await bodies()).single;
    expect(body.id, isNot(oldBody.id));
    expect(
      body.faceId,
      face.id,
      reason: 'the new body is linked to the kept face',
    );
  });

  test('faces only: bodies keep their rows and link to the new face', () async {
    final m = await photo('c');
    final oldFace = (await faces()).single;
    final body = (await bodies()).single;
    api.analyzeResult = AnalyzeImageResponse.fromJson(
      response(shift: 4, extraFace: true),
    );
    await redetector.photo(m.id, RedetectPart.faces);
    final now = await faces();
    expect(now, hasLength(2), reason: 'the more sensitive pass found one more');
    expect(now.map((f) => f.id), isNot(contains(oldFace.id)));
    final kept = (await bodies()).single;
    expect(kept.id, body.id);
    expect(now.map((f) => f.id), contains(kept.faceId));
  });

  test('a person: every photo again, videos skipped, cancel stops', () async {
    final ali = await person('Ali');
    for (final asset in ['p1', 'p2']) {
      await photo(asset);
    }
    final video = await photo('v', kind: 'video');
    await db.customUpdate(
      'UPDATE faces SET person_id = ?',
      variables: [Variable.withInt(ali)],
    );
    await db
        .into(db.faces)
        .insert(
          FacesCompanion.insert(
            mediaId: Value(video.id),
            frameNumber: const Value(10),
            modelId: 'buffalo_l@1',
            embedding: Uint8List(2048),
            qualityScore: .8,
            qualityVersion: 2,
            detScore: .9,
            facePx: 100,
            sharpness: 1,
            bboxX: .1,
            bboxY: .1,
            bboxW: .1,
            bboxH: .1,
            personId: Value(ali),
            createdAt: 1,
          ),
        );
    final steps = <(int, int)>[];
    final out = await redetector.person(
      ali,
      RedetectPart.both,
      progress: (done, total) => steps.add((done, total)),
    );
    expect(steps, [(0, 2), (1, 2), (2, 2)]);
    expect(out.skippedVideos, 1);
    expect(out.faces, 2);
    expect(api.analyzeCalls, hasLength(2));
    // Both photos show the very same face, so they share one row: each photo still shows
    // it, and it is still Ali.
    final shown = await db
        .customSelect(
          "SELECT d.media_id, f.person_id FROM media_detections d JOIN faces f ON f.id = d.ref_id "
          "WHERE d.kind = 'f' AND d.frame_number IS NULL AND f.frame_number IS NULL",
        )
        .get();
    expect(shown.map((r) => r.read<int>('media_id')).toSet(), hasLength(2));
    expect(shown.every((r) => r.read<int?>('person_id') == ali), isTrue);

    api.analyzeCalls.clear();
    await redetector.person(ali, RedetectPart.faces, cancelled: () => true);
    expect(api.analyzeCalls, isEmpty);
    expect(await redetector.photo(video.id, RedetectPart.both), isNull);
  });
}
