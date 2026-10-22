import 'package:drift/drift.dart';

import '../db/app_database.dart';

class IdentityRepository {
  IdentityRepository(this.db);
  final AppDatabase db;

  Stream<List<IdentitySetRow>> watch() =>
      (db.select(db.identitySets)..orderBy([
            (s) => OrderingTerm.asc(s.name),
            (s) => OrderingTerm.asc(s.id),
          ]))
          .watch();

  Future<List<FaceRow>> faces(int setId) async {
    final set = await (db.select(
      db.identitySets,
    )..where((s) => s.id.equals(setId))).getSingleOrNull();
    if (set == null) {
      throw const FormatException('This identity set was removed.');
    }
    final members = await (db.select(
      db.identitySetFaces,
    )..where((s) => s.setId.equals(setId))).get();
    final faces =
        await (db.select(db.faces)
              ..where((f) => f.id.isIn(members.map((m) => m.faceId)))
              ..orderBy([(f) => OrderingTerm.desc(f.qualityScore)]))
            .get();
    _validate(faces, set.personId, set.modelId);
    return faces;
  }

  static void _validate(List<FaceRow> faces, int personId, String modelId) {
    if (faces.isEmpty ||
        faces.length > 100 ||
        faces.any((f) => f.personId != personId || f.modelId != modelId)) {
      throw const FormatException(
        'Choose 1–100 current faces of the same person and embedding model. '
        'This saved selection may need to be rebuilt after a correction.',
      );
    }
  }

  Future<List<FaceRow>> selection({
    required int personId,
    required Iterable<int> faceIds,
    required String modelId,
  }) async {
    final ids = faceIds.toSet();
    if (ids.isEmpty || ids.length > 100) {
      throw const FormatException('Choose 1–100 source faces.');
    }
    final faces = await (db.select(
      db.faces,
    )..where((f) => f.id.isIn(ids))).get();
    if (faces.length != ids.length) {
      throw const FormatException(
        'A selected face was removed. Choose it again.',
      );
    }
    _validate(faces, personId, modelId);
    return faces;
  }

  Future<int> save({
    required String name,
    required int personId,
    required Iterable<int> faceIds,
  }) => db.transaction(() async {
    final label = name.trim();
    if (label.isEmpty || label.length > 80) {
      throw const FormatException('Use a name of 1–80 characters.');
    }
    final ids = faceIds.toSet();
    if (ids.isEmpty || ids.length > 100) {
      throw const FormatException('Choose 1–100 source faces.');
    }
    final faces = await (db.select(
      db.faces,
    )..where((f) => f.id.isIn(ids))).get();
    if (faces.length != ids.length) {
      throw const FormatException(
        'A selected face was removed. Choose it again.',
      );
    }
    _validate(faces, personId, faces.first.modelId);
    final id = await db
        .into(db.identitySets)
        .insert(
          IdentitySetsCompanion.insert(
            personId: personId,
            name: label,
            modelId: faces.first.modelId,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    await db.batch(
      (b) => b.insertAll(db.identitySetFaces, [
        for (final face in faces)
          IdentitySetFacesCompanion.insert(setId: id, faceId: face.id),
      ]),
    );
    return id;
  });

  Future<void> delete(int id) async {
    await (db.delete(db.identitySets)..where((s) => s.id.equals(id))).go();
  }
}
