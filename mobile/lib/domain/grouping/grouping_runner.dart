import '../../data/api/dtos/grouping.dart';
import '../../data/api/mobile_api.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/people_repository.dart';
import '../../data/repositories/review_repository.dart';
import 'grouping_config.dart';
import '../identity/doubt_audit.dart';
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
  final ReviewCounts review;
}

/// Moves every face, body and artifact of [sourceId] to [targetId] (PeopleRepository.mergePeople).
typedef MergePeople =
    Future<void> Function({required int sourceId, required int targetId});

/// "Sort my gallery", phone edition. The PC decides (POST /v1/grouping/plan, stateless), the phone
/// applies, in three rounds so that ids stay real:
///   1. apply [match, cluster]  -> confident matches + new people, in one transaction
///   2. apply [bodies]          -> outfit / weak-face links against the people that now exist
///   3. review [all four]       -> everything that still needs a decision, stored for the Review screen
///   4. audit (local)           -> faces already on a person that do not look like her, stored the same way
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
    this._merge,
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

  /// Without it (tests of other rounds) the `people` stage's merges are not applied.
  final MergePeople? _merge;

  /// Another kind's runner that follows this one (people, then characters).
  final GroupingRunner? _then;

  /// 'person' or 'character': each kind is grouped on its own, with its own strictness profile.
  final String kind;

  Future<GroupingRun>? _running;
  bool _runningIncremental = false;

  /// Runs the three rounds (a second call while one is running joins it).
  Future<GroupingRun> run({bool incremental = false}) {
    final running = _running;
    // A final/manual full pass must not silently join a smaller in-scan pass.
    if (running != null) {
      // a failed small pass must not stop the full one that was asked for after it
      return incremental || !_runningIncremental
          ? running
          : running.then((_) => run(), onError: (_) => run());
    }
    _runningIncremental = incremental;
    return _running = _runBoth(incremental: incremental).whenComplete(() {
      _running = null;
      _runningIncremental = false;
    });
  }

  /// This kind, then the kind that follows it: the follower runs even if this one failed (the
  /// first error is still reported).
  Future<GroupingRun> _runBoth({required bool incremental}) async {
    GroupingRun? result;
    Object? error;
    StackTrace? trace;
    try {
      result = await _run(incremental: incremental);
    } catch (e, s) {
      error = e;
      trace = s;
    }
    try {
      await _then?.run(incremental: incremental);
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

  Future<GroupingRun> _run({required bool incremental}) async {
    // Repair evidence must exist before a contaminated identity is used as a
    // model. It also remains available when the PC's grouping request fails.
    if (!incremental) await _audit.run();
    final api = _api();
    if (api == null) {
      // the PC is the only thing missing: the audit of faces already on people is local
      return GroupingRun(skipped: true, review: await _review.counts());
    }
    final strictness = kind == 'character'
        ? characterStrictness
        : personStrictness;

    var result = const FacePlanResult();
    var merged = 0;
    Future<void> round1() async {
      final plan = await api.groupingPlan(
        await _inputs.request(
          mode: 'apply',
          stages: _merge == null
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
    if (unsorted > 0 || (_merge != null && people > 1)) {
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

    var bodiesLinked = 0;
    if (await _count("SELECT COUNT(*) AS n FROM bodies WHERE kind = '$kind'") >
            0 &&
        await _count("SELECT COUNT(*) AS n FROM persons WHERE kind = '$kind'") >
            0) {
      final plan = await api.groupingPlan(
        await _inputs.request(
          mode: 'apply',
          stages: round2Stages,
          strictness: strictness,
          cap: _memberCap,
          dropDerived: true,
        ),
      );
      bodiesLinked = await _applier.applyBodyPlan(plan);
    }

    final review = await api.groupingPlan(
      await _inputs.request(
        mode: 'review',
        stages: round3Stages,
        strictness: strictness,
        cap: _memberCap,
      ),
    );
    await _review.replaceAll(review);
    // Then everything already sorted, the faces the user named included: which of them do not look like
    // the rest of their person? They come back as "Are you sure these are X?" questions.
    if (result.changedAnything || merged > 0) await _audit.run();

    return GroupingRun(
      assigned: result.assigned,
      newPeople: result.newPeople,
      facesInNewPeople: result.facesInNewPeople,
      bodiesLinked: bodiesLinked,
      peopleMerged: merged,
      review: await _review.counts(),
    );
  }

  /// Applies the `people` stage: each provisional person is merged into the person it clearly is,
  /// unless the user took it over (named, locked, confirmed...) since the plan was made, or the two now
  /// appear together somewhere (mergePeople refuses that).
  Future<int> _applyMerges(List<PersonMergePlan> merges) async {
    final merge = _merge;
    if (merge == null || merges.isEmpty) return 0;
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
        await merge(sourceId: source, targetId: target);
      } on MergeBlockedException {
        continue;
      }
      gone[source] = target;
      n++;
    }
    return n;
  }
}
