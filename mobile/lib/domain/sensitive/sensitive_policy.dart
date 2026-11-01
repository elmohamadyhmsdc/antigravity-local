/// Roadmap section 8.4 - what counts as sensitive. Pure functions; the numbers are the only thing
/// the S0 evaluation (`the app/eval_sensitive.py`) changes.
library;

/// The PC's `sensitive_detection.MODEL_VERSION`. A file whose `media.sensitive_version` is lower is
/// (re)checked by the backfill.
const sensitiveModelVersion = 1;

/// Bump when [sensitiveThresholds] or [mediaIsSensitive] change: `isSensitive` is a derived cache and
/// must then be recomputed for every file (`SensitiveStore.recomputeAll`).
const sensitivePolicyVersion = 1;

/// Labels that make a file sensitive (exposed genitals, anus, female breast, buttocks).
const sensitiveLabels = <String>{
  'FEMALE_GENITALIA_EXPOSED',
  'MALE_GENITALIA_EXPOSED',
  'ANUS_EXPOSED',
  'FEMALE_BREAST_EXPOSED',
  'BUTTOCKS_EXPOSED',
};

/// Starting value until S0 has per-label precision on the user's own photos (precision >= 0.95 is the
/// gate). Deliberately high: a missed file is cheaper than a wrongly tagged one.
const defaultSensitiveThreshold = 0.60;

/// Per-label score thresholds from S0. Empty = [defaultSensitiveThreshold] for every label.
const sensitiveThresholds = <String, double>{};

double sensitiveThresholdFor(String label) =>
    sensitiveThresholds[label] ?? defaultSensitiveThreshold;

/// One stored region, as the policy sees it.
typedef SensitiveInput = ({String label, double score, String? userState});

/// A region counts when its label is a sensitive one, its score reaches the label's threshold and the
/// user did not dismiss it. A region the user confirmed counts whatever its score.
bool regionCounts(SensitiveInput r) {
  if (r.userState == 'dismissed') return false;
  if (!sensitiveLabels.contains(r.label)) return false;
  if (r.userState == 'confirmed') return true;
  return r.score >= sensitiveThresholdFor(r.label);
}

/// `media.sensitive_override` ('none' | 'sensitive') wins; else any counting region of any
/// (sampled) frame makes the file sensitive.
bool mediaIsSensitive(Iterable<SensitiveInput> regions, {String? override}) {
  if (override == 'none') return false;
  if (override == 'sensitive') return true;
  return regions.any(regionCounts);
}
