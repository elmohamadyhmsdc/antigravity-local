// What happens to the PC's answer for one photo: faces, bodies, crops and detections stored in one
// transaction, the duplicate rule, and re-scanning without duplicating anything.

import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/repositories/library_repository.dart';
import 'package:antigravity_mobile/domain/scan/photo_result_store.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

void main() {
  late AppDatabase db;
  late Directory tmp;
  late FileStore files;
  late InMemoryEmbeddingIndex index;
  late PhotoResultStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('ag_store_');
    files = FileStore(Directory('${tmp.path}/crops'));
    index = InMemoryEmbeddingIndex();
    store = PhotoResultStore(db: db, files: files, index: index);
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<MediaRow> photo(String asset) async {
    final id = await seedMedia(db, asset: asset, status: 'scanning');
    return (db.select(db.media)..where((m) => m.id.equals(id))).getSingle();
  }

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
          .read<int>('n');

  group('one photo', () {
    test(
      'a face, its body, the crops and the detections are stored together',
      () async {
        final media = await photo('a1');
        final face = unitVec(1);
        final outcome = await store.store(
          media,
          analysis(
            faces: [
              faceJson(face, box: [100, 100, 200, 240]),
            ],
            bodies: [
              bodyJson(box: [50, 60, 400, 700]),
            ],
            pairs: [(0, 0)],
          ),
        );

        expect(
          (
            outcome.newFaces,
            outcome.linkedFaces,
            outcome.newBodies,
            outcome.facesSeen,
          ),
          (1, 0, 1, 1),
        );
        final f = (await db.select(db.faces).get()).single;
        expect(f.mediaId, media.id);
        expect(f.personId, isNull);
        expect(f.modelId, 'buffalo_l@1');
        expect(
          (f.bboxX, f.bboxY, f.bboxW, f.bboxH),
          (0.1, 0.125, 0.2, 0.3),
          reason: 'normalised to the 1000x800 picture',
        );
        expect(f.qualityScore, 0.8);
        expect(f.qualityVersion, 2);
        expect(f.yaw, 3.0);
        expect(dot(embeddingFromBlob(f.embedding), face), closeTo(1.0, 1e-6));
        expect(
          f.cropPath,
          'faces/${f.id}.jpg',
          reason: 'a relative path, so a backup restores anywhere',
        );
        expect(files.resolve(f.cropPath!).existsSync(), isTrue);

        final b = (await db.select(db.bodies).get()).single;
        expect(b.faceId, f.id, reason: 'the body is tied to its face');
        expect((b.bboxX, b.bboxW), (0.05, 0.4));
        expect(b.extent, 'upper');
        expect(b.appearance!.length, 320, reason: '80 x float32');
        expect(b.cropPath, 'bodies/${b.id}.jpg');
        expect(b.weakFaceEmbedding, isNull);

        final detections = await db.select(db.mediaDetections).get();
        expect(detections.map((d) => (d.kind, d.refId, d.mediaId)).toSet(), {
          ('f', f.id, media.id),
          ('b', b.id, media.id),
        });

        final done = await (db.select(
          db.media,
        )..where((m) => m.id.equals(media.id))).getSingle();
        expect(
          (done.scanStatus, done.scanVersion, done.scanError),
          ('done', scanVersion, isNull),
        );
        expect(done.scannedAt, isNotNull);
        expect(
          (done.width, done.height),
          (1200, 800),
          reason:
              "MediaStore's size stays, or the next listing would see an edit",
        );
        expect(
          await index.size(),
          1,
          reason: 'the new face is searchable at once',
        );
      },
    );

    test(
      'only faces that pass the gate become faces; a refused face still gives its body weak evidence',
      () async {
        final media = await photo('a1');
        final weakFace = unitVec(2);
        final outcome = await store.store(
          media,
          analysis(
            faces: [
              faceJson(unitVec(1), box: [100, 100, 200, 240]),
              faceJson(
                weakFace,
                box: [600, 100, 40, 48],
                quality: 0.2,
                passes: false,
              ),
            ],
            bodies: [
              bodyJson(box: [550, 80, 160, 600]),
            ],
            pairs: [(1, 0)],
          ),
        );
        expect((outcome.newFaces, outcome.facesSeen), (1, 1));
        final b = (await db.select(db.bodies).get()).single;
        expect(b.faceId, isNull, reason: 'its face was too small to keep');
        expect(
          dot(embeddingFromBlob(b.weakFaceEmbedding!), weakFace),
          closeTo(1.0, 1e-6),
        );
        expect(b.weakFaceQuality, 0.2);
      },
    );

    test(
      'scanning the same photo again changes nothing - and keeps what the user did',
      () async {
        final media = await photo('a1');
        final response = analysis(
          faces: [faceJson(unitVec(1))],
          bodies: [bodyJson()],
          pairs: [(0, 0)],
        );
        await store.store(media, response);
        final sara = await seedPerson(db, name: 'Sara');
        await (db.update(
          db.faces,
        )).write(FacesCompanion(personId: Value(sara)));

        final again = await store.store(media, response);
        expect((again.newFaces, again.linkedFaces, again.newBodies), (0, 1, 0));
        expect(await count('faces'), 1);
        expect(await count('bodies'), 1);
        expect(
          await count('media_detections'),
          2,
          reason: 'no duplicate detection rows',
        );
        expect(
          (await db.select(db.faces).get()).single.personId,
          sara,
          reason: 'the correction survives a re-scan',
        );
      },
    );
  });

  group("the PC's duplicate rule across photos", () {
    test(
      'the same face in another photo (cosine >= 0.95) is linked, not stored again - the photo still shows it',
      () async {
        final first = await photo('a1');
        final second = await photo('a2');
        final face = unitVec(1);
        await store.store(first, analysis(faces: [faceJson(face)]));
        final outcome = await store.store(
          second,
          analysis(
            faces: [
              faceJson(near(face, 70, 0.1), box: [300, 200, 180, 220]),
            ],
          ),
        );

        expect((outcome.newFaces, outcome.linkedFaces), (0, 1));
        expect(await count('faces'), 1);
        final faceId = (await db.select(db.faces).get()).single.id;
        final detections = await db.select(db.mediaDetections).get();
        expect(
          detections.map((d) => (d.mediaId, d.refId)).toSet(),
          {(first.id, faceId), (second.id, faceId)},
          reason:
              '"which photos is this person in?" still finds the second photo',
        );
        expect(
          (await db.select(db.faces).get()).single.mediaId,
          first.id,
          reason: 'the face keeps its first photo as home',
        );
      },
    );

    test(
      'the same person on another day (cosine well below 0.95) is a new face',
      () async {
        final first = await photo('a1');
        final second = await photo('a2');
        final face = unitVec(1);
        await store.store(first, analysis(faces: [faceJson(face)]));
        final outcome = await store.store(
          second,
          analysis(faces: [faceJson(near(face, 71, 0.9))]),
        );
        expect((outcome.newFaces, outcome.linkedFaces), (1, 0));
        expect(await count('faces'), 2);
      },
    );

    test(
      'two faces of one photo never both link to the same stored face',
      () async {
        final first = await photo('a1');
        final second = await photo('a2');
        final face = unitVec(1);
        await store.store(first, analysis(faces: [faceJson(face)]));
        final outcome = await store.store(
          second,
          analysis(
            faces: [
              faceJson(near(face, 72, 0.05), box: [100, 100, 150, 180]),
              faceJson(near(face, 73, 0.05), box: [500, 100, 150, 180]),
            ],
          ),
        );
        expect(
          (outcome.linkedFaces, outcome.newFaces),
          (1, 1),
          reason: 'one person cannot appear twice in one photo',
        );
      },
    );

    test(
      'a face the index remembers but the user deleted is stored as a new face, not linked to nothing',
      () async {
        final media = await photo('a1');
        final ghost = unitVec(5);
        await index.addAll([
          (999, ghost),
        ]); // deleted from the database, still in the index
        final outcome = await store.store(
          media,
          analysis(faces: [faceJson(ghost)]),
        );
        expect((outcome.newFaces, outcome.linkedFaces), (1, 0));
        expect(await count('faces'), 1);
        final detection = (await db.select(db.mediaDetections).get()).single;
        expect(detection.refId, (await db.select(db.faces).get()).single.id);
      },
    );

    test(
      'a better view of a known face refreshes its quality, a worse one does not',
      () async {
        final first = await photo('a1');
        final second = await photo('a2');
        final third = await photo('a3');
        final face = unitVec(1);
        await store.store(
          first,
          analysis(faces: [faceJson(face, quality: 0.5)]),
        );
        await store.store(
          second,
          analysis(faces: [faceJson(near(face, 74, 0.05), quality: 0.9)]),
        );
        expect((await db.select(db.faces).get()).single.qualityScore, 0.9);
        await store.store(
          third,
          analysis(faces: [faceJson(near(face, 75, 0.05), quality: 0.6)]),
        );
        expect((await db.select(db.faces).get()).single.qualityScore, 0.9);
      },
    );
  });

  group('faceless bodies', () {
    test(
      'a body that looks like one already kept in the photo adds nothing',
      () async {
        final media = await photo('a1');
        final same = outfit(3);
        await store.store(
          media,
          analysis(
            bodies: [
              bodyJson(box: [10, 10, 200, 600], appearance: same),
              bodyJson(box: [300, 10, 200, 600], appearance: same),
              bodyJson(box: [600, 10, 200, 600], appearance: outfit(77)),
            ],
          ),
        );
        expect(
          await count('bodies'),
          2,
          reason: 'the duplicate outfit is dropped, the different one is kept',
        );
      },
    );

    test('at most 40 faceless bodies per photo', () async {
      final media = await photo('a1');
      final bodies = [
        for (var i = 0; i < 45; i++)
          bodyJson(box: [10.0 + i * 20, 10, 18, 600])..['appearance'] = null,
      ];
      await store.store(media, analysis(bodies: bodies));
      expect(await count('bodies'), 40);
    });

    test('a body with a face of its own is always kept', () async {
      final media = await photo('a1');
      final same = outfit(3);
      await store.store(
        media,
        analysis(
          faces: [
            faceJson(unitVec(1), box: [60, 60, 100, 120]),
            faceJson(unitVec(2), box: [560, 60, 100, 120]),
          ],
          bodies: [
            bodyJson(box: [10, 10, 200, 600], appearance: same),
            bodyJson(box: [500, 10, 200, 600], appearance: same),
          ],
          pairs: [(0, 0), (1, 1)],
        ),
      );
      expect(await count('bodies'), 2);
    });
  });

  test('a photo with nothing in it is still marked scanned', () async {
    final media = await photo('empty');
    final outcome = await store.store(media, analysis());
    expect((outcome.newFaces, outcome.newBodies), (0, 0));
    expect(
      (await (db.select(
        db.media,
      )..where((m) => m.id.equals(media.id))).getSingle()).scanStatus,
      'done',
    );
  });

  test('crops are only written for faces that were stored', () async {
    final media = await photo('a1');
    await store.store(
      media,
      analysis(
        faces: [
          faceJson(unitVec(1), crop: false),
          faceJson(unitVec(2), box: [500, 100, 30, 36], passes: false),
        ],
      ),
    );
    final f = (await db.select(db.faces).get()).single;
    expect(f.cropPath, isNull, reason: 'the PC sent no crop');
    expect(await files.allFiles(), isEmpty);
  });

  test(
    'unit helpers: the bytes of a stored embedding are 512 little-endian float32',
    () async {
      final media = await photo('a1');
      await store.store(media, analysis(faces: [faceJson(unitVec(1))]));
      final blob = (await db.select(db.faces).get()).single.embedding;
      expect(blob.length, embeddingBytes);
      expect(
        ByteData.sublistView(blob).getFloat32(0, Endian.little),
        unitVec(1)[0],
      );
    },
  );
}
