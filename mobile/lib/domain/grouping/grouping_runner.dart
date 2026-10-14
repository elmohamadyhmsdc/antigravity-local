import '../../data/api/mobile_api.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/app_settings.dart';
import '../../data/repositories/review_repository.dart';
import 'grouping_config.dart';
import 'grouping_inputs.dart';
import 'plan_applier.dart';

class GroupingRun {
  const GroupingRun({
    this.skipped = false,
    this.assigned = 0,
    this.newPeople = 0,
    this.facesInNewPeople = 0,
    this.bodiesLinked = 0,
    this.review = const ReviewCounts(),
  });

  /// Nothing happened: no PC is paired.
  final bool skipped;
  final int assigned;
  final int newPeople;
  final int facesInNewPeople;
  final int bodiesLinked;
  final ReviewCounts review;
}

/// "Sort my gallery", phone edition. The PC decides (POST /v1/grouping/plan, stateless), the phone
/// applies, in three rounds so that ids stay real:
///   1. apply [match, cluster]  -> confident matches + new people, in one transaction
///   2. apply [bodies]          -> outfit / weak-face links against the people that now exist
///   3. review [all four]       -> everything that still needs a decision, stored for the Review screen
/// Every round is idempotent, so running it again (or after a crash) is always safe.
class GroupingRunner {
  GroupingRunner({
    required this._db,
    required this._api,
    required this._settings,
    required this._review,
    PlanApplier? applier,
    GroupingInputs? inputs,
    this._memberCap = groupingMemberCap,
  }) : _applier = applier ?? PlanApplier(_db),
       _inputs = inputs ?? GroupingInputs(_db);

  final AppDatabase _db;
  final MobileApi? Function() _api;
  final AppSettings _settings;
  final ReviewRepository _review;
  final PlanApplier _applier;
  final GroupingInputs _inputs;
  final int _memberCap;

  Future<GroupingRun>? _running;

  /// Runs the three rounds (a second call while one is running joins it).
  Future<GroupingRun> run() =>
      _running ??= _run().whenComplete(() => _running = null);

  Future<int> _count(String sql) async =>
      (await _db.customSelect(sql).getSingle()).read<int>('n');

  Future<GroupingRun> _run() async {
    final api = _api();
    if (api == null) return const GroupingRun(skipped: true);
    final strictness = (await _settings.load()).strictness;

    var result = const FacePlanResult();
    if (await _count(
          'SELECT COUNT(*) AS n FROM faces WHERE person_id IS NULL',
        ) >
        0) {
      final plan = await api.groupingPlan(
        await _inputs.request(
          mode: 'apply',
          stages: round1Stages,
          strictness: strictness,
          cap: _memberCap,
        ),
      );
      result = await _applier.applyFacePlan(plan);
    }

    var bodiesLinked = 0;
    if (await _count('SELECT COUNT(*) AS n FROM bodies') > 0 &&
        await _count('SELECT COUNT(*) AS n FROM persons') > 0) {
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

    return GroupingRun(
      assigned: result.assigned,
      newPeople: result.newPeople,
      facesInNewPeople: result.facesInNewPeople,
      bodiesLinked: bodiesLinked,
      review: await _review.counts(),
    );
  }
}
