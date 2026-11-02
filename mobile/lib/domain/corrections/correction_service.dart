import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/people_repository.dart';
import 'body_link_guard.dart';
import 'correction_scope.dart';
import 'correction_target.dart';
import 'correction_verb.dart';

class CorrectionPreview {
  const CorrectionPreview({
    required this.itemsCount,
    required this.mediaCount,
    this.consequences = const [],
  });

  final int itemsCount;
  final int mediaCount;
  final List<String> consequences;
}

class CorrectionResult {
  const CorrectionResult({
    required this.undoToken,
    required this.affectedCount,
  });

  final String undoToken;
  final int affectedCount;
}

class _Snapshot {
  _Snapshot({
    required this.facesBefore,
    required this.bodiesBefore,
    this.insertedFaceOverrideIds = const [],
    this.insertedBodyOverrideIds = const [],
    this.insertedBodyDistinct = const [],
    this.insertedFaceRejections = const [],
    this.insertedBodyRejections = const [],
    this.deletedBodyDistinct = const [],
  });

  final Map<int, FaceRow> facesBefore;
  final Map<int, BodyRow> bodiesBefore;
  final List<int> insertedFaceOverrideIds;
  final List<int> insertedBodyOverrideIds;
  final List<(int, int)> insertedBodyDistinct;
  final List<(int, int)> insertedFaceRejections;
  final List<(int, int)> insertedBodyRejections;
  final List<(int, int)> deletedBodyDistinct;
}

class CorrectionService {
  CorrectionService({
    required this.db,
    required this.peopleRepo,
    required this.bodyLinkGuard,
  });

  final AppDatabase db;
  final PeopleRepository peopleRepo;
  final BodyLinkGuard bodyLinkGuard;

  final Map<String, _Snapshot> _undoSnapshots = {};

  List<CorrectionVerb> allowedVerbs(CorrectionTarget target) {
    return switch (target) {
      FaceLinkTarget() => const [
        CorrectionVerb.reassign,
        CorrectionVerb.notThisPerson,
        CorrectionVerb.belongsToNoOne,
        CorrectionVerb.notARealThing,
        CorrectionVerb.unlink,
        CorrectionVerb.confirm,
      ],
      BodyLinkTarget() => const [
        CorrectionVerb.reassign,
        CorrectionVerb.notThisPerson,
        CorrectionVerb.belongsToNoOne,
        CorrectionVerb.notARealThing,
        CorrectionVerb.unlink,
        CorrectionVerb.confirm,
      ],
      BodyPairTarget() => const [
        CorrectionVerb.belongsToNoOne,
        CorrectionVerb.notSamePerson,
        CorrectionVerb.unlink,
        CorrectionVerb.confirm,
      ],
      EquipmentOwnerTarget() => const [
        CorrectionVerb.reassign,
        CorrectionVerb.belongsToNoOne,
        CorrectionVerb.notARealThing,
        CorrectionVerb.unlink,
        CorrectionVerb.confirm,
      ],
      SensitiveRegionTarget() => const [
        CorrectionVerb.notARealThing,
        CorrectionVerb.confirm,
      ],
      PoseMembershipTarget() => const [
        CorrectionVerb.reassign,
        CorrectionVerb.notARealThing,
        CorrectionVerb.unlink,
        CorrectionVerb.confirm,
      ],
      PersonPairTarget() => const [
        CorrectionVerb.reassign,
        CorrectionVerb.notSamePerson,
      ],
      ActionSuggestionTarget() => const [
        CorrectionVerb.notARealThing,
        CorrectionVerb.confirm,
      ],
    };
  }

  Future<CorrectionPreview> preview(
    CorrectionTarget target,
    CorrectionVerb verb, {
    CorrectionScope scope = CorrectionScope.single,
    int? targetPersonId,
  }) async {
    final consequences = <String>[];
    var itemsCount = 1;
    var mediaCount = 1;

    switch (target) {
      case FaceLinkTarget f:
        if (scope == CorrectionScope.track && f.trackId != null) {
          final faces =
              await (db.select(db.faces)..where(
                    (row) =>
                        row.mediaId.equals(f.mediaId) &
                        row.trackId.equals(f.trackId!),
                  ))
                  .get();
          final matchingFaces = f.personId == null
              ? faces.where((row) => row.personId == null).toList()
              : faces.where((row) => row.personId == f.personId).toList();
          itemsCount = math.max(1, matchingFaces.length);
        } else if (scope == CorrectionScope.wholeVideo && f.personId != null) {
          final faces =
              await (db.select(db.faces)..where(
                    (row) =>
                        row.mediaId.equals(f.mediaId) &
                        row.personId.equals(f.personId!),
                  ))
                  .get();
          itemsCount = math.max(1, faces.length);
        }

        if (verb == CorrectionVerb.belongsToNoOne) {
          consequences.add(
            'Faces will remain visible marked as "No owner" and excluded from automatic grouping.',
          );
        } else if (verb == CorrectionVerb.notARealThing) {
          consequences.add(
            'Faces will be hidden and excluded from all views and training.',
          );
        }
        break;

      case BodyLinkTarget b:
        if (scope == CorrectionScope.track && b.trackId != null) {
          final bodies =
              await (db.select(db.bodies)..where(
                    (row) =>
                        row.mediaId.equals(b.mediaId) &
                        row.trackId.equals(b.trackId!),
                  ))
                  .get();
          final matchingBodies = b.personId == null
              ? bodies.where((row) => row.personId == null).toList()
              : bodies.where((row) => row.personId == b.personId).toList();
          itemsCount = math.max(1, matchingBodies.length);
        } else if (scope == CorrectionScope.wholeVideo && b.personId != null) {
          final bodies =
              await (db.select(db.bodies)..where(
                    (row) =>
                        row.mediaId.equals(b.mediaId) &
                        row.personId.equals(b.personId!),
                  ))
                  .get();
          itemsCount = math.max(1, bodies.length);
        }

        if (verb == CorrectionVerb.belongsToNoOne) {
          consequences.add(
            'Bodies will remain visible with "No owner" badge and excluded from suggestions.',
          );
        } else if (verb == CorrectionVerb.notARealThing) {
          consequences.add(
            'Body detection will be marked false and hidden from view.',
          );
        }
        break;

      case BodyPairTarget():
        itemsCount = 2;
        if (verb == CorrectionVerb.notSamePerson) {
          consequences.add(
            'These two bodies will never be linked to the same person.',
          );
        }
        break;

      case PersonPairTarget p:
        final conflicts = await bodyLinkGuard.findMergeConflicts(
          p.personAId,
          p.personBId,
        );
        if (conflicts.isNotEmpty) {
          consequences.add(
            '${conflicts.length} conflicting bodies will remain unassigned after merge.',
          );
        }
        break;

      default:
        break;
    }

    return CorrectionPreview(
      itemsCount: itemsCount,
      mediaCount: mediaCount,
      consequences: consequences,
    );
  }

  Future<CorrectionResult> apply(
    CorrectionTarget target,
    CorrectionVerb verb, {
    CorrectionScope scope = CorrectionScope.single,
    int? targetPersonId,
  }) async {
    final token = 'undo-${DateTime.now().microsecondsSinceEpoch}';
    var affected = 0;

    switch (target) {
      case FaceLinkTarget f:
        affected = await _applyFaceCorrection(
          token,
          f,
          verb,
          scope,
          targetPersonId,
        );
        break;

      case BodyLinkTarget b:
        affected = await _applyBodyCorrection(
          token,
          b,
          verb,
          scope,
          targetPersonId,
        );
        break;

      case BodyPairTarget bp:
        affected = await _applyBodyPairCorrection(token, bp, verb);
        break;

      case EquipmentOwnerTarget eq:
        affected = await _applyEquipmentCorrection(token, eq, verb);
        break;

      case SensitiveRegionTarget sr:
        affected = await _applySensitiveRegionCorrection(token, sr, verb);
        break;

      case PoseMembershipTarget pm:
        affected = await _applyPoseMembershipCorrection(token, pm, verb);
        break;

      case PersonPairTarget pp:
        affected = await _applyPersonPairCorrection(
          token,
          pp,
          verb,
          targetPersonId,
        );
        break;

      case ActionSuggestionTarget():
        affected = 1;
        break;
    }

    return CorrectionResult(undoToken: token, affectedCount: affected);
  }

  Future<bool> undo(String token) async {
    final snapshot = _undoSnapshots.remove(token);
    if (snapshot == null) return false;

    return db.transaction(() async {
      // 1. Check if any row was externally changed since the snapshot
      for (final entry in snapshot.facesBefore.entries) {
        final current = await (db.select(
          db.faces,
        )..where((r) => r.id.equals(entry.key))).getSingleOrNull();
        if (current == null) return false;
      }
      for (final entry in snapshot.bodiesBefore.entries) {
        final current = await (db.select(
          db.bodies,
        )..where((r) => r.id.equals(entry.key))).getSingleOrNull();
        if (current == null) return false;
      }

      // 2. Restore faces
      for (final f in snapshot.facesBefore.values) {
        await (db.update(db.faces)..where((r) => r.id.equals(f.id))).write(
          FacesCompanion(
            personId: Value(f.personId),
            reviewDismissed: Value(f.reviewDismissed),
            ownership: Value(f.ownership),
            hidden: Value(f.hidden),
          ),
        );
      }

      // 3. Restore bodies
      for (final b in snapshot.bodiesBefore.values) {
        await (db.update(db.bodies)..where((r) => r.id.equals(b.id))).write(
          BodiesCompanion(
            personId: Value(b.personId),
            linkMethod: Value(b.linkMethod),
            linkConfidence: Value(b.linkConfidence),
            ownership: Value(b.ownership),
            hidden: Value(b.hidden),
            trackId: Value(b.trackId),
          ),
        );
      }

      // 4. Remove inserted overrides
      for (final id in snapshot.insertedFaceOverrideIds) {
        await (db.delete(db.faceOverrides)..where((r) => r.id.equals(id))).go();
      }
      for (final id in snapshot.insertedBodyOverrideIds) {
        await (db.delete(db.bodyOverrides)..where((r) => r.id.equals(id))).go();
      }

      // 5. Remove inserted rejections and distincts
      for (final (a, b) in snapshot.insertedBodyDistinct) {
        await (db.delete(
          db.bodyDistinct,
        )..where((r) => r.bodyA.equals(a) & r.bodyB.equals(b))).go();
      }
      for (final (f, p) in snapshot.insertedFaceRejections) {
        await (db.delete(
          db.faceRejections,
        )..where((r) => r.faceId.equals(f) & r.personId.equals(p))).go();
      }
      for (final (b, p) in snapshot.insertedBodyRejections) {
        await (db.delete(
          db.bodyRejections,
        )..where((r) => r.bodyId.equals(b) & r.personId.equals(p))).go();
      }

      // 6. Restore deleted distincts
      for (final (a, b) in snapshot.deletedBodyDistinct) {
        await db
            .into(db.bodyDistinct)
            .insert(
              BodyDistinctCompanion.insert(bodyA: a, bodyB: b),
              mode: InsertMode.insertOrIgnore,
            );
      }

      return true;
    });
  }

  Future<int> _applyFaceCorrection(
    String token,
    FaceLinkTarget f,
    CorrectionVerb verb,
    CorrectionScope scope,
    int? targetPersonId,
  ) async {
    return db.transaction(() async {
      // Find all target faces based on scope
      final targetFaceIds = <int>{f.faceId};
      if (scope == CorrectionScope.track && f.trackId != null) {
        final sameTrack =
            await (db.select(db.faces)..where(
                  (row) =>
                      row.mediaId.equals(f.mediaId) &
                      row.trackId.equals(f.trackId!),
                ))
                .get();
        for (final row in sameTrack) {
          if (f.personId == null && row.personId == null) {
            targetFaceIds.add(row.id);
          } else if (f.personId != null && row.personId == f.personId) {
            targetFaceIds.add(row.id);
          }
        }
      } else if (scope == CorrectionScope.wholeVideo && f.personId != null) {
        final sameMedia =
            await (db.select(db.faces)..where(
                  (row) =>
                      row.mediaId.equals(f.mediaId) &
                      row.personId.equals(f.personId!),
                ))
                .get();
        for (final row in sameMedia) {
          targetFaceIds.add(row.id);
        }
      }

      final facesBefore = <int, FaceRow>{};
      for (final id in targetFaceIds) {
        final row = await (db.select(
          db.faces,
        )..where((r) => r.id.equals(id))).getSingleOrNull();
        if (row != null) facesBefore[id] = row;
      }

      final insertedOverrides = <int>[];
      final insertedRejections = <int, int>{};

      final media = await (db.select(
        db.media,
      )..where((m) => m.id.equals(f.mediaId))).getSingleOrNull();
      final assetId = media?.assetId ?? '';

      switch (verb) {
        case CorrectionVerb.reassign:
          if (targetPersonId != null) {
            await peopleRepo.assignFaces(targetFaceIds, targetPersonId);
            for (final id in targetFaceIds) {
              await (db.update(db.faces)..where((r) => r.id.equals(id))).write(
                const FacesCompanion(ownership: Value(null)),
              );
            }
          }
          break;

        case CorrectionVerb.notThisPerson:
          final pid = f.personId ?? facesBefore[f.faceId]?.personId;
          if (pid != null) {
            await peopleRepo.rejectFaces(targetFaceIds, fromPersonId: pid);
            for (final id in targetFaceIds) {
              insertedRejections[id] = pid;
            }
          }
          break;

        case CorrectionVerb.belongsToNoOne:
          // Order: clearAssignments, dismissFaces, ownership = 'none', face_overrides
          await peopleRepo.clearAssignments(targetFaceIds);
          await peopleRepo.dismissFaces(targetFaceIds);
          for (final id in targetFaceIds) {
            await (db.update(db.faces)..where((r) => r.id.equals(id))).write(
              const FacesCompanion(ownership: Value('none')),
            );
            final face = facesBefore[id];
            if (face != null) {
              final insId = await db
                  .into(db.faceOverrides)
                  .insert(
                    FaceOverridesCompanion.insert(
                      assetId: assetId,
                      x: face.bboxX,
                      y: face.bboxY,
                      w: face.bboxW,
                      h: face.bboxH,
                      timestampMs: Value(face.timestampMs),
                      ownership: const Value('none'),
                      scope: Value(scope.name),
                    ),
                  );
              insertedOverrides.add(insId);
            }
          }
          break;

        case CorrectionVerb.notARealThing:
          for (final id in targetFaceIds) {
            await (db.update(db.faces)..where((r) => r.id.equals(id))).write(
              const FacesCompanion(hidden: Value(true), personId: Value(null)),
            );
          }
          break;

        case CorrectionVerb.unlink:
          await peopleRepo.clearAssignments(targetFaceIds);
          for (final id in targetFaceIds) {
            await (db.update(db.faces)..where((r) => r.id.equals(id))).write(
              const FacesCompanion(ownership: Value(null)),
            );
          }
          break;

        case CorrectionVerb.confirm:
          // Keep assigned person, clear dismissed/rejection
          for (final id in targetFaceIds) {
            await (db.update(db.faces)..where((r) => r.id.equals(id))).write(
              const FacesCompanion(
                reviewDismissed: Value(false),
                ownership: Value(null),
              ),
            );
          }
          break;

        default:
          break;
      }

      _undoSnapshots[token] = _Snapshot(
        facesBefore: facesBefore,
        bodiesBefore: const {},
        insertedFaceOverrideIds: insertedOverrides,
        insertedFaceRejections: [
          for (final e in insertedRejections.entries) (e.key, e.value),
        ],
      );

      return targetFaceIds.length;
    });
  }

  Future<int> _applyBodyCorrection(
    String token,
    BodyLinkTarget b,
    CorrectionVerb verb,
    CorrectionScope scope,
    int? targetPersonId,
  ) async {
    return db.transaction(() async {
      final targetBodyIds = <int>{b.bodyId};
      if (scope == CorrectionScope.track && b.trackId != null) {
        final sameTrack =
            await (db.select(db.bodies)..where(
                  (row) =>
                      row.mediaId.equals(b.mediaId) &
                      row.trackId.equals(b.trackId!),
                ))
                .get();
        for (final row in sameTrack) {
          if (b.personId == null && row.personId == null) {
            targetBodyIds.add(row.id);
          } else if (b.personId != null && row.personId == b.personId) {
            targetBodyIds.add(row.id);
          }
        }
      } else if (scope == CorrectionScope.wholeVideo && b.personId != null) {
        final sameMedia =
            await (db.select(db.bodies)..where(
                  (row) =>
                      row.mediaId.equals(b.mediaId) &
                      row.personId.equals(b.personId!),
                ))
                .get();
        for (final row in sameMedia) {
          targetBodyIds.add(row.id);
        }
      }

      final bodiesBefore = <int, BodyRow>{};
      for (final id in targetBodyIds) {
        final row = await (db.select(
          db.bodies,
        )..where((r) => r.id.equals(id))).getSingleOrNull();
        if (row != null) bodiesBefore[id] = row;
      }

      final insertedOverrides = <int>[];
      final insertedRejections = <int, int>{};
      final deletedDistinct = <(int, int)>[];

      final media = await (db.select(
        db.media,
      )..where((m) => m.id.equals(b.mediaId))).getSingleOrNull();
      final assetId = media?.assetId ?? '';

      switch (verb) {
        case CorrectionVerb.reassign:
          if (targetPersonId != null) {
            for (final id in targetBodyIds) {
              await bodyLinkGuard.onManualLink(id, targetPersonId);
              await peopleRepo.linkBody(id, targetPersonId);
              await (db.update(db.bodies)..where((r) => r.id.equals(id))).write(
                const BodiesCompanion(
                  ownership: Value(null),
                  hidden: Value(false),
                ),
              );
            }
          }
          break;

        case CorrectionVerb.notThisPerson:
          final pid = b.personId ?? bodiesBefore[b.bodyId]?.personId;
          if (pid != null) {
            for (final id in targetBodyIds) {
              await peopleRepo.rejectBody(id, personId: pid);
              insertedRejections[id] = pid;
            }
          }
          break;

        case CorrectionVerb.belongsToNoOne:
          for (final id in targetBodyIds) {
            await (db.update(db.bodies)..where((r) => r.id.equals(id))).write(
              const BodiesCompanion(
                personId: Value(null),
                linkMethod: Value(null),
                linkConfidence: Value(null),
                ownership: Value('none'),
                hidden: Value(false),
              ),
            );
            await (db.delete(
              db.reviewBodyLinks,
            )..where((r) => r.bodyId.equals(id))).go();
            final body = bodiesBefore[id];
            if (body != null) {
              final insId = await db
                  .into(db.bodyOverrides)
                  .insert(
                    BodyOverridesCompanion.insert(
                      assetId: assetId,
                      x: body.bboxX,
                      y: body.bboxY,
                      w: body.bboxW,
                      h: body.bboxH,
                      timestampMs: Value(body.timestampMs),
                      ownership: const Value('none'),
                      scope: Value(scope.name),
                    ),
                  );
              insertedOverrides.add(insId);
            }
          }
          break;

        case CorrectionVerb.notARealThing:
          for (final id in targetBodyIds) {
            await (db.update(db.bodies)..where((r) => r.id.equals(id))).write(
              const BodiesCompanion(
                personId: Value(null),
                linkMethod: Value(null),
                linkConfidence: Value(null),
                hidden: Value(true),
              ),
            );
            await (db.delete(
              db.reviewBodyLinks,
            )..where((r) => r.bodyId.equals(id))).go();
            final body = bodiesBefore[id];
            if (body != null) {
              final insId = await db
                  .into(db.bodyOverrides)
                  .insert(
                    BodyOverridesCompanion.insert(
                      assetId: assetId,
                      x: body.bboxX,
                      y: body.bboxY,
                      w: body.bboxW,
                      h: body.bboxH,
                      timestampMs: Value(body.timestampMs),
                      hidden: const Value(true),
                      scope: Value(scope.name),
                    ),
                  );
              insertedOverrides.add(insId);
            }
          }
          break;

        case CorrectionVerb.unlink:
          for (final id in targetBodyIds) {
            await (db.update(db.bodies)..where((r) => r.id.equals(id))).write(
              const BodiesCompanion(
                personId: Value(null),
                linkMethod: Value(null),
                linkConfidence: Value(null),
                ownership: Value(null),
              ),
            );
          }
          break;

        case CorrectionVerb.confirm:
          for (final id in targetBodyIds) {
            await (db.update(db.bodies)..where((r) => r.id.equals(id))).write(
              const BodiesCompanion(
                linkMethod: Value('manual'),
                ownership: Value(null),
              ),
            );
            await (db.delete(
              db.reviewBodyLinks,
            )..where((r) => r.bodyId.equals(id))).go();
          }
          break;

        default:
          break;
      }

      _undoSnapshots[token] = _Snapshot(
        facesBefore: const {},
        bodiesBefore: bodiesBefore,
        insertedBodyOverrideIds: insertedOverrides,
        insertedBodyRejections: [
          for (final e in insertedRejections.entries) (e.key, e.value),
        ],
        deletedBodyDistinct: deletedDistinct,
      );

      return targetBodyIds.length;
    });
  }

  Future<int> _applyBodyPairCorrection(
    String token,
    BodyPairTarget bp,
    CorrectionVerb verb,
  ) async {
    return db.transaction(() async {
      final a = math.min(bp.bodyAId, bp.bodyBId);
      final b = math.max(bp.bodyAId, bp.bodyBId);

      switch (verb) {
        case CorrectionVerb.notSamePerson:
          // Insert into body_distinct
          await db
              .into(db.bodyDistinct)
              .insert(
                BodyDistinctCompanion.insert(bodyA: a, bodyB: b),
                mode: InsertMode.insertOrIgnore,
              );

          // If bodyB shared track with bodyA, clear trackId on bodyB
          final bodyA = await (db.select(
            db.bodies,
          )..where((r) => r.id.equals(a))).getSingleOrNull();
          final bodyB = await (db.select(
            db.bodies,
          )..where((r) => r.id.equals(b))).getSingleOrNull();

          if (bodyA?.trackId != null && bodyA?.trackId == bodyB?.trackId) {
            await (db.update(db.bodies)..where((r) => r.id.equals(b))).write(
              const BodiesCompanion(trackId: Value(null)),
            );
          }
          // If both had same personId, unlink bodyB
          if (bodyA?.personId != null && bodyA?.personId == bodyB?.personId) {
            await (db.update(db.bodies)..where((r) => r.id.equals(b))).write(
              const BodiesCompanion(
                personId: Value(null),
                linkMethod: Value(null),
              ),
            );
          }

          final bodiesMap = <int, BodyRow>{};
          if (bodyA != null) bodiesMap[a] = bodyA;
          if (bodyB != null) bodiesMap[b] = bodyB;
          _undoSnapshots[token] = _Snapshot(
            facesBefore: const {},
            bodiesBefore: bodiesMap,
            insertedBodyDistinct: [(a, b)],
          );
          return 2;

        case CorrectionVerb.belongsToNoOne:
          await _applyBodyCorrection(
            token,
            BodyLinkTarget(bodyId: a, mediaId: bp.mediaId),
            CorrectionVerb.belongsToNoOne,
            CorrectionScope.single,
            null,
          );
          await _applyBodyCorrection(
            '$token-2',
            BodyLinkTarget(bodyId: b, mediaId: bp.mediaId),
            CorrectionVerb.belongsToNoOne,
            CorrectionScope.single,
            null,
          );
          return 2;

        case CorrectionVerb.unlink:
          await (db.delete(
            db.bodyDistinct,
          )..where((r) => r.bodyA.equals(a) & r.bodyB.equals(b))).go();
          return 2;

        case CorrectionVerb.confirm:
          return 2;

        default:
          return 0;
      }
    });
  }

  Future<int> _applyEquipmentCorrection(
    String token,
    EquipmentOwnerTarget eq,
    CorrectionVerb verb,
  ) async {
    return db.transaction(() async {
      switch (verb) {
        case CorrectionVerb.belongsToNoOne:
        case CorrectionVerb.unlink:
          await (db.update(db.equipmentObjects)
                ..where((r) => r.id.equals(eq.objectId)))
              .write(const EquipmentObjectsCompanion(bodyId: Value(null)));
          return 1;

        case CorrectionVerb.confirm:
          await (db.update(db.equipmentObjects)
                ..where((r) => r.id.equals(eq.objectId)))
              .write(const EquipmentObjectsCompanion(state: Value('manual')));
          return 1;

        case CorrectionVerb.notARealThing:
          await (db.update(db.equipmentObjects)
                ..where((r) => r.id.equals(eq.objectId)))
              .write(const EquipmentObjectsCompanion(state: Value('rejected')));
          return 1;

        default:
          return 0;
      }
    });
  }

  Future<int> _applySensitiveRegionCorrection(
    String token,
    SensitiveRegionTarget sr,
    CorrectionVerb verb,
  ) async {
    return db.transaction(() async {
      if (verb == CorrectionVerb.notARealThing) {
        await (db.update(
          db.sensitiveRegions,
        )..where((r) => r.id.equals(sr.regionId))).write(
          const SensitiveRegionsCompanion(userState: Value('dismissed')),
        );
        return 1;
      } else if (verb == CorrectionVerb.confirm) {
        await (db.update(
          db.sensitiveRegions,
        )..where((r) => r.id.equals(sr.regionId))).write(
          const SensitiveRegionsCompanion(userState: Value('confirmed')),
        );
        return 1;
      }
      return 0;
    });
  }

  Future<int> _applyPoseMembershipCorrection(
    String token,
    PoseMembershipTarget pm,
    CorrectionVerb verb,
  ) async {
    return db.transaction(() async {
      final stateVal = switch (verb) {
        CorrectionVerb.reassign || CorrectionVerb.notARealThing => 'rejected',
        CorrectionVerb.unlink => 'auto',
        CorrectionVerb.confirm => 'manual',
        _ => 'rejected',
      };

      if (pm.isOutfit) {
        await (db.update(db.bodyOutfitMatches)..where(
              (r) =>
                  r.bodyId.equals(pm.bodyId) &
                  r.categoryId.equals(pm.categoryId),
            ))
            .write(BodyOutfitMatchesCompanion(state: Value(stateVal)));
      } else {
        await (db.update(db.bodyPoseMatches)..where(
              (r) =>
                  r.bodyId.equals(pm.bodyId) &
                  r.categoryId.equals(pm.categoryId),
            ))
            .write(BodyPoseMatchesCompanion(state: Value(stateVal)));
      }
      return 1;
    });
  }

  Future<int> _applyPersonPairCorrection(
    String token,
    PersonPairTarget pp,
    CorrectionVerb verb,
    int? targetPersonId,
  ) async {
    if (verb == CorrectionVerb.notSamePerson) {
      await peopleRepo.markDistinct(pp.personAId, pp.personBId);
      return 2;
    } else if (verb == CorrectionVerb.reassign) {
      await peopleRepo.mergePeople(
        sourceId: pp.personAId,
        targetId: pp.personBId,
      );
      return 2;
    }
    return 0;
  }
}
