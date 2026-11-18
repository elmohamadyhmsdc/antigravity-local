import 'dart:math' as math;

import '../../data/api/dtos/grouping.dart';
import '../../data/api/mobile_api.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/identity_rescan.dart';
import '../../data/repositories/people_repository.dart';
import '../../data/repositories/review_repository.dart';
import 'grouping_config.dart';
import '../identity/doubt_audit.dart';
import '../pose/exposed_matching.dart';
import '../scan/body_face_links.dart';
import 'grouping_inputs.dart';
import 'plan_applier.dart';

class GroupingRun {
  const GroupingRun({
    this.skipped = false,
    this.assigned = 0,
    this.newPeople = 0,
    this.facesInNewPeople = 0,
    this.bodiesLinked = 0,
    this.peopleMerged = 0,
    this.facesRepaired = 0,
    this.review = const ReviewCounts(),
  });

  /// Nothing happened: no PC is paired.
  final bool skipped;
  final int assigned;
  final int newPeople;
  final int facesInNewPeople;
  final int bodiesLinked;

  /// Provisional people folded into the person they clearly are (duplicates the app made itself).
  final int peopleMerged;
  final int facesRepaired;
  final ReviewCounts review;
}

enum _GroupingPass { incremental, full, repair, libraryRepair, rebuild }

/// "Sort my gallery", phone edition. The PC decides (POST /v1/grouping/plan, stateless), the phone
/// applies, in three rounds so that ids stay real:
///   1. apply [match, cluster]  -> confident matches + new people, in one transaction
///   2. apply [bodies]          -> outfit / weak-face links against the people that now exist
///   3. review [all four]       -> everything that still needs a decision, stored for the Review screen
/// A full run audits the faces already assigned. A manual repair pass also
/// checks the audit's suggested moves with the PC before the usual rounds.
/// Every round is idempotent, so running it again (or after a crash) is always safe.
class GroupingRunner {
  GroupingRunner({
    required this._db,
    required this._api,
    required this._review,
    this.kind = 'person',
    this._then,
    PlanApplier? applier,
    GroupingInputs? inputs,
    DoubtAudit? audit,
    this._memberCap = groupingMemberCap,
    this._people,
  }) : _applier = applier ?? PlanApplier(_db, kind: kind),
       _inputs = inputs ?? GroupingInputs(_db, kind: kind),
       _audit = audit ?? DoubtAudit(_db, kind: kind);

  final AppDatabase _db;
  final MobileApi? Function() _api;
  final ReviewRepository _review;
  final PlanApplier _applier;
  final GroupingInputs _inputs;
  final DoubtAudit _audit;
  final int _memberCap;

  final PeopleRepository? _people;

  /// Another kind's runner that follows this one (people, then characters).
  final GroupingRunner? _then;

  /// 'person' or 'character': each kind is grouped on its own, with its own strictness profile.
  final String kind;

  Future<GroupingRun>? _running;
  _GroupingPass? _runningPass;
  int? _runningPersonId;

  /// Join a pass that already covers the work, or follow it with a broader one.
  Future<GroupingRun> run({
    bool incremental = false,
    bool repairExisting = false,
    int? repairPersonId,
  }) => _schedule(
    repairExisting
        ? _GroupingPass.repair
        : incremental
        ? _GroupingPass.incremental
        : _GroupingPass.full,
    repairPersonId: repairPersonId,
  );

  /// Rebuild the automatically created groups and audit saved identities.
  Future<GroupingRun> rebuild() => _schedule(_GroupingPass.rebuild);

  /// Reconcile all identities after their source media has been scanned again.
  Future<GroupingRun> repairLibrary() => _schedule(_GroupingPass.libraryRepair);

  Future<GroupingRun> _schedule(_GroupingPass pass, {int? repairPersonId}) {
    final running = _running;
    if (running != null) {
      if (pass.index <= _runningPass!.index &&
          (pass != _GroupingPass.libraryRepair || pass == _runningPass) &&
          (repairPersonId == null || repairPersonId == _runningPersonId)) {
        return running;
      }
      Future<GroupingRun> follow() =>
          _schedule(pass, repairPersonId: repairPersonId);
      return running.then((_) => follow(), onError: (_) => follow());
    }
    _runningPass = pass;
    _runningPersonId = repairPersonId;
    return _running = _runBoth(pass, repairPersonId: repairPersonId)
        .whenComplete(() {
          _running = null;
          _runningPass = null;
          _runningPersonId = null;
        });
  }

  /// This kind, then the kind that follows it: the follower runs even if this one failed (the
  /// first error is still reported).
  Future<GroupingRun> _runBoth(
    _GroupingPass pass, {
    int? repairPersonId,
  }) async {
    if (pass == _GroupingPass.rebuild) {
      final api = _api();
      if (api == null) return const GroupingRun(skipped: true);
      // Keep the pre-rebuild library usable if either kind fails or the app
      // closes between rounds. The PC planner has no writes of its own.
      return _db
          .transaction(() async {
            final people = await _run(pass, rebuildApi: api);
            final characters = await _then?._run(pass, rebuildApi: api);
            final p = people.review;
            final c = characters?.review ?? const ReviewCounts();
            return GroupingRun(
              assigned: people.assigned + (characters?.assigned ?? 0),
              newPeople: people.newPeople + (characters?.newPeople ?? 0),
              facesInNewPeople:
                  people.facesInNewPeople + (characters?.facesInNewPeople ?? 0),
              bodiesLinked:
                  people.bodiesLinked + (characters?.bodiesLinked ?? 0),
              facesRepaired:
                  people.facesRepaired + (characters?.facesRepaired ?? 0),
              review: ReviewCounts(
                matches: p.matches + c.matches,
                groups: p.groups + c.groups,
                duplicates: p.duplicates + c.duplicates,
                bodyLinks: p.bodyLinks + c.bodyLinks,
                doubtful: p.doubtful + c.doubtful,
                decisions: p.total + c.total,
              ),
            );
          })
          .whenComplete(() {
            _inputs.clearModelCache();
            _then?._inputs.clearModelCache();
          });
    }
    GroupingRun? result;
    Object? error;
    StackTrace? trace;
    try {
      result = await _run(pass, repairPersonId: repairPersonId);
    } catch (e, s) {
      error = e;
      trace = s;
    }
    try {
      await _then?._schedule(pass, repairPersonId: repairPersonId);
    } catch (e, s) {
      if (error == null) {
        error = e;
        trace = s;
      }
    }
    if (error != null) Error.throwWithStackTrace(error, trace!);
    return result!;
  }

  Future<int> _count(String sql) async =>
      (await _db.customSelect(sql).getSingle()).read<int>('n');

  Future<GroupingRun> _run(
    _GroupingPass pass, {
    int? repairPersonId,
    MobileApi? rebuildApi,
  }) async {
    final incremental = pass == _GroupingPass.incremental;
    final rebuilding = pass == _GroupingPass.rebuild;
    final libraryRepair = pass == _GroupingPass.libraryRepair;
    final mergePeople = !rebuilding && !libraryRepair && _people != null;
    if (rebuilding && kind == 'person' && _people != null) {
      final reserved = await IdentityRescan(_db).reservedPersonIds();
      await _people.dissolvePeople(
        (await _inputs.provisionalPersonIds(
          forRebuild: true,
        )).where((id) => !reserved.contains(id)),
        keepReviewDismissals: true,
      );
    }
    // Repair evidence must exist before a contaminated identity is used as a
    // model. It also remains available when the PC's grouping request fails.
    if (!incremental) {
      await _audit.run(
        anchorPersonId: repairPersonId,
        anchorAll: libraryRepair,
        rebuilding: rebuilding,
      );
    }
    final api = rebuildApi ?? _api();
    if (api == null) {
      // the PC is the only thing missing: the audit of faces already on people is local
      return GroupingRun(skipped: true, review: await _review.counts());
    }
    if (repairPersonId != null) {
      await _people?.regroupDoubtfulFaces(repairPersonId);
    }
    final strictness = kind == 'character'
        ? characterStrictness
        : personStrictness;
    var repaired = pass == _GroupingPass.repair || rebuilding || libraryRepair
        ? await _repairFaces(api, strictness, sourceId: repairPersonId)
        : 0;
    if ((rebuilding || libraryRepair) && _people != null) {
      repaired += await _people.regroupDoubtfulFaces(
        null,
        includeSuggested: libraryRepair,
      );
    }

    var result = const FacePlanResult();
    var merged = 0;
    Future<void> round1() async {
      final plan = await api.groupingPlan(
        await _inputs.request(
          mode: 'apply',
          stages: !mergePeople
              ? [
                  for (final s in round1Stages)
                    if (s != 'people') s,
                ]
              : round1Stages,
          strictness: strictness,
          cap: _memberCap,
        ),
      );
      final applied = await _applier.applyFacePlan(plan);
      result = FacePlanResult(
        assigned: result.assigned + applied.assigned,
        newPeople: result.newPeople + applied.newPeople,
        facesInNewPeople: result.facesInNewPeople + applied.facesInNewPeople,
      );
      merged += await _applyMerges(plan.merges ?? const []);
    }

    final unsorted = await _count(
      "SELECT COUNT(*) AS n FROM faces WHERE person_id IS NULL AND kind = '$kind'",
    );
    final people = await _count(
      "SELECT COUNT(*) AS n FROM persons WHERE kind = '$kind'",
    );
    if (unsorted > 0 || (mergePeople && people > 1)) {
      await round1();
      // A merge leaves one bigger, better model: faces that fitted neither half may fit it now.
      if (merged > 0 && !incremental) await round1();
    }

    if (incremental) {
      return GroupingRun(
        assigned: result.assigned,
        newPeople: result.newPeople,
        facesInNewPeople: result.facesInNewPeople,
        peopleMerged: merged,
      );
    }

    Future<int> relinkBodies() async {
      if (await _count(
            "SELECT COUNT(*) AS n FROM bodies WHERE kind = '$kind'",
          ) ==
          0) {
        return 0;
      }
      if (await _count(
            "SELECT COUNT(*) AS n FROM persons WHERE kind = '$kind'",
          ) ==
          0) {
        return rebuilding || libraryRepair
            ? _applier.applyBodyPlan(const GroupingPlanResponse(mode: 'apply'))
            : 0;
      }
      return _applier.applyBodyPlan(
        await api.groupingPlan(
          await _inputs.request(
            mode: 'apply',
            stages: round2Stages,
            strictness: strictness,
            cap: _memberCap,
            dropDerived: true,
          ),
        ),
      );
    }

    final repairedBodies =
        (pass == _GroupingPass.repair && repairPersonId == null) ||
            rebuilding ||
            libraryRepair
        ? await BodyFaceLinks(_db).repairIsolated(kind)
        : 0;
    var bodiesLinked = await relinkBodies();

    Future<GroupingPlanResponse> buildReview() async => api.groupingPlan(
      await _inputs.request(
        mode: 'review',
        stages: round3Stages,
        strictness: strictness,
        cap: _memberCap,
      ),
    );

    var review = await buildReview();
    // New or repaired identities can make a match automatic after round 1.
    // Use the same thresholds and apply-time guards before asking the user.
    final automatic = review.assignments.where((a) => a.isAuto).toList();
    if (automatic.isNotEmpty) {
      final applied = await _applier.applyFacePlan(
        GroupingPlanResponse(mode: 'apply', assignments: automatic),
      );
      if (applied.assigned > 0) {
        result = FacePlanResult(
          assigned: result.assigned + applied.assigned,
          newPeople: result.newPeople,
          facesInNewPeople: result.facesInNewPeople,
        );
        if (rebuilding || libraryRepair) bodiesLinked = await relinkBodies();
        review = await buildReview();
      }
    }
    await _review.replaceAll(review);
    // Then everything already sorted, the faces the user named included: which of them do not look like
    // the rest of their person? They come back as "Are you sure these are X?" questions.
    if (result.changedAnything || merged > 0 || repaired > 0) {
      await _audit.run(rebuilding: rebuilding, anchorAll: libraryRepair);
    }
    if (kind == 'person') await ExposedClusters(_db).publishSuggestions();

    return GroupingRun(
      assigned: result.assigned,
      newPeople: result.newPeople,
      facesInNewPeople: result.facesInNewPeople,
      bodiesLinked: repairedBodies + bodiesLinked,
      peopleMerged: merged,
      facesRepaired: repaired,
      review: await _review.counts(),
    );
  }

  Future<int> _repairFaces(
    MobileApi api,
    String strictness, {
    int? sourceId,
  }) async {
    final people = _people;
    if (people == null) return 0;
    List<(int, int)>? distinctPairs;
    var repaired = 0;
    await for (final candidatesPage in _inputs.repairCandidates()) {
      final page = candidatesPage
          .where((c) => sourceId == null || c.sourceId == sourceId)
          .toList();
      if (page.isEmpty) continue;
      final models = await _inputs.models(
        cap: math.min(_memberCap, 24),
        onlyPeople: {
          for (final c in page) c.sourceId,
          for (final c in page) c.targetId,
        },
      );
      final modelIds = {for (final m in models) m.pid};
      final candidates = {
        for (final c in page)
          if (modelIds.contains(c.sourceId) && modelIds.contains(c.targetId))
            c.face.id: c,
      };
      if (candidates.isEmpty) continue;
      final pairs = distinctPairs ??= await _inputs.distinctPairs();
      final plan = await api.groupingPlan(
        GroupingPlanRequest(
          mode: 'apply',
          stages: const ['match'],
          strictness: strictness,
          models: models,
          pending: [for (final c in candidates.values) c.face],
          distinctPairs: [
            for (final pair in pairs)
              if (modelIds.contains(pair.$1) && modelIds.contains(pair.$2))
                pair,
          ],
        ),
      );
      for (final assignment in plan.assignments) {
        final c = candidates[assignment.faceId];
        // The audit compared the rest of the library. On the PC, the source
        // still competes with the proposed target using its cleaned model.
        if (c == null ||
            assignment.personId != c.targetId ||
            !assignment.isAuto ||
            assignment.margin < 0.12) {
          continue;
        }
        if (await people.applyFaceRepair(
          faceId: c.face.id,
          sourceId: c.sourceId,
          targetId: c.targetId,
          modelId: c.modelId,
          embedding: c.embedding,
        )) {
          repaired++;
        }
      }
    }
    return repaired;
  }

  /// Applies the `people` stage: each provisional person is merged into the person it clearly is,
  /// unless the user took it over (named, locked, confirmed...) since the plan was made, or the two now
  /// appear together somewhere (mergePeople refuses that).
  Future<int> _applyMerges(List<PersonMergePlan> merges) async {
    final people = _people;
    if (people == null || merges.isEmpty) return 0;
    final provisional = (await _inputs.provisionalPersonIds()).toSet();
    final gone = <int, int>{}; // absorbed -> where its faces went
    int resolve(int id) {
      var x = id;
      for (var i = 0; i < 64 && gone.containsKey(x); i++) {
        x = gone[x]!;
      }
      return x;
    }

    var n = 0;
    for (final m in merges) {
      final source = resolve(m.absorb);
      final target = resolve(m.into);
      if (source == target || !provisional.contains(source)) continue;
      final alive = await _count(
        "SELECT COUNT(*) AS n FROM persons WHERE id IN ($source, $target) AND kind = '$kind'",
      );
      if (alive != 2) continue;
      try {
        await people.mergePeople(sourceId: source, targetId: target);
      } on MergeBlockedException {
        continue;
      }
      gone[source] = target;
      n++;
    }
    return n;
  }
}
