import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/repositories/curation_queries.dart';
import 'package:antigravity_mobile/domain/curation/auto_dataset_curator.dart';
import '../support/seed.dart';

void main() {
  late AppDatabase db;
  late int personId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    personId = await seedPerson(db, name: 'Sara');
  });

  tearDown(() async {
    await db.close();
  });

  test('loadCandidatesForPerson loads categorized faces, upper bodies, and full bodies with exposed regions', () async {
    // 1. Photo with Face
    final m1 = await seedMedia(db, asset: 'photo_face');
    await seedFace(db, mediaId: m1, personId: personId, quality: 0.85);

    // 2. Photo with Upper Body
    final m2 = await seedMedia(db, asset: 'photo_upper');
    final b2 = await seedBody(db, mediaId: m2, personId: personId, score: 0.9);
    await (db.update(db.bodies)..where((t) => t.id.equals(b2))).write(
      const BodiesCompanion(extent: Value('upper')),
    );

    // 3. Photo with Full Body and an Exposed Region
    final m3 = await seedMedia(db, asset: 'photo_body_exposed');
    final b3 = await seedBody(db, mediaId: m3, personId: personId, score: 0.95);
    await (db.update(db.bodies)..where((t) => t.id.equals(b3))).write(
      const BodiesCompanion(extent: Value('full')),
    );
    await db.into(db.sensitiveRegions).insert(
      SensitiveRegionsCompanion.insert(
        mediaId: m3,
        bodyId: Value(b3),
        label: 'chest',
        exposed: true,
        score: 0.99,
        x: 0.3,
        y: 0.4,
        w: 0.2,
        h: 0.2,
        modelVersion: 1,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    // 4. Hidden face (should be excluded)
    final m4 = await seedMedia(db, asset: 'photo_hidden');
    final f4 = await seedFace(db, mediaId: m4, personId: personId);
    await (db.update(db.faces)..where((tbl) => tbl.id.equals(f4))).write(
      const FacesCompanion(hidden: Value(true)),
    );

    final queries = CurationQueries(db);
    final candidates = await queries.loadCandidatesForPerson(personId);

    expect(candidates.length, 3);

    final faceCandidate = candidates.firstWhere((c) => c.category == CurationCategory.face);
    expect(faceCandidate.assetId, 'photo_face');
    expect(faceCandidate.quality, closeTo(0.85, 0.01));

    final upperCandidate = candidates.firstWhere((c) => c.category == CurationCategory.upper);
    expect(upperCandidate.assetId, 'photo_upper');
    expect(upperCandidate.extent, 'upper');

    final bodyCandidate = candidates.firstWhere((c) => c.category == CurationCategory.body);
    expect(bodyCandidate.assetId, 'photo_body_exposed');
    expect(bodyCandidate.extent, 'full');
    expect(bodyCandidate.hasExposedRegion, isTrue);
  });
}
