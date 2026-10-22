import 'dart:convert';

/// Only use a measured speed and real step counts; waiting/upload phases have
/// different progress scales and must never produce an invented finish time.
class JobProgress {
  JobProgress(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) details = decoded;
    } on FormatException {
      /* show progress even if older metadata is unreadable */
    }
  }
  Map<String, dynamic> details = const {};

  double? number(String key) {
    final value = details[key];
    return value is num && value.isFinite && value >= 0
        ? value.toDouble()
        : null;
  }

  Duration? remaining(String status) {
    if (status != 'running') return null;
    final step = number('step'), total = number('total_steps');
    final speed = number('seconds_per_step') ?? number('sec_per_step');
    if (step == null ||
        total == null ||
        speed == null ||
        speed <= 0 ||
        step <= 0 ||
        step >= total) {
      return null;
    }
    final seconds = (total - step) * speed;
    if (!seconds.isFinite || seconds > 365 * 86400) return null;
    return Duration(seconds: seconds.ceil());
  }
}
