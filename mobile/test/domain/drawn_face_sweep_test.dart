// Drawn (anime/cartoon) faces that older scans put in People are removed once, with the drawn
// bodies around them and the unnamed people they leave empty.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/domain/scan/drawn_face_sweep.dart';
import 'package:antigravity_mobile/domain/scan/drawn_faces.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

/// [drawnFaceDirection] mixed into a random face so its drawn score is [score].
Float32List withScore(double score, int seed) {
  final r = unitVec(seed);
  final along = drawnFaceScore(r);
  final v = Float32List(r.length);
  var n = 0.0;
  for (var i = 0; i < r.length; i++) {
    v[i] = r[i] - along * drawnFaceDirection[i];
    n += v[i] * v[i];
  }
  final s = math.sqrt(1 - score * score) / math.sqrt(n);
  for (var i = 0; i < v.length; i++) {
    v[i] = v[i] * s + score * drawnFaceDirection[i];
  }
  return v;
}

void main() {
  late AppDatabase db;
  late Directory tmp;
  late FileStore files;
  late InMemoryEmbeddingIndex index;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('ag_drawn_');
    files = FileStore(Directory('${tmp.path}/crops'));
    index = InMemoryEmbeddingIndex();
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  DrawnFaceSweep sweep() => DrawnFaceSweep(db: db, files: files, index: index);

  Future<List<int>> ids(String table) async => [
    for (final r
        in await db.customSelect('SELECT id FROM $table ORDER BY id').get())
      r.read<int>('id'),
  ];

  test('the score is a cosine: drawn faces at or above the threshold', () {
    expect(drawnFaceScore(drawnFaceDirection), closeTo(1, 1e-5));
    expect(drawnFaceScore(withScore(.3, 1)), closeTo(.3, 1e-5));
    expect(isDrawnFace(withScore(drawnFaceMinScore + .005, 2)), isTrue);
    expect(isDrawnFace(withScore(drawnFaceMinScore - .005, 3)), isFalse);
    expect(isDrawnFace(Float32List(512)), isFalse);
    expect(isDrawnFace(Float32List(128)), isFalse);
  });

  test(
    'drawn faces leave People: mixed person keeps its real faces, a drawn person goes',
    () async {
      final media = await seedMedia(db);
      final mixed = await seedPerson(db);
      final anime = await seedPerson(db);
      final named = await seedPerson(db, name: 'Luffy');
      final real = await seedFace(
        db,
        mediaId: media,
        personId: mixed,
        embedding: withScore(.05, 1),
      );
      final drawnInMixed = await seedFace(
        db,
        mediaId: media,
        personId: mixed,
        embedding: withScore(.45, 2),
        cropPath: 'faces/2.jpg',
      );
      final drawnA = await seedFace(
        db,
        mediaId: media,
        personId: anime,
        embedding: withScore(.3, 3),
      );
      final drawnB = await seedFace(
        db,
        mediaId: media,
        personId: anime,
        embedding: withScore(.6, 4),
      );
      final drawnNamed = await seedFace(
        db,
        mediaId: media,
        personId: named,
        embedding: withScore(.4, 5),
      );
      await seedFace(
        db,
        mediaId: media,
        embedding: withScore(.25, 6), // unsorted
      );
      await (db.update(db.persons)..where((p) => p.id.equals(anime))).write(
        PersonsCompanion(avatarFaceId: Value(drawnA)),
      );
      await seedBody(
        db,
        mediaId: media,
        faceId: drawnB,
        cropPath: 'bodies/1.jpg',
      );
      final realBody = await seedBody(db, mediaId: media, faceId: real);
      await files.write('faces/2.jpg', Uint8List(10));
      await files.write('bodies/1.jpg', Uint8List(10));
      await index.addAll([
        for (final id in [real, drawnInMixed, drawnA, drawnB, drawnNamed])
          (id, unitVec(id)),
      ]);

      final result = (await sweep().runOnce())!;
      expect((result.faces, result.bodies, result.people), (5, 1, 1));
      expect(await ids('faces'), [real]);
      expect(await ids('bodies'), [realBody]);
      expect(await ids('persons'), [mixed, named]);
      final detections = await db.select(db.mediaDetections).get();
      expect(detections.map((d) => (d.kind, d.refId)).toSet(), {
        ('f', real),
        ('b', realBody),
      });
      expect(files.resolve('faces/2.jpg').existsSync(), isFalse);
      expect(files.resolve('bodies/1.jpg').existsSync(), isFalse);
      expect(await index.size(), 1);

      expect(await sweep().runOnce(), isNull, reason: 'once per version');
    },
  );

  test('nothing drawn: nothing changes, and it is still marked done', () async {
    final media = await seedMedia(db);
    final p = await seedPerson(db);
    await seedFace(db, mediaId: media, personId: p, embedding: unitVec(1));
    final result = (await sweep().runOnce())!;
    expect((result.faces, result.bodies, result.people), (0, 0, 0));
    expect(await ids('persons'), [p]);
    expect(await db.setting(DrawnFaceSweep.doneKey), DrawnFaceSweep.version);
  });
}
