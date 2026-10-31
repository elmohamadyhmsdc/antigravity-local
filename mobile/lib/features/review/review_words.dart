import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/review_questions.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';

/// "Advanced review details" (Settings, or the quick review's menu): numbers instead of words.
final reviewAdvancedProvider = Provider.autoDispose<bool>(
  (ref) => ref.watch(settingsProvider).value?.reviewAdvanced ?? false,
);

String likelihoodWord(AppLocalizations l, Likelihood value) => switch (value) {
  Likelihood.veryLikely => l.likelihoodVeryLikely,
  Likelihood.likely => l.likelihoodLikely,
  Likelihood.maybe => l.likelihoodMaybe,
};

/// How sure the PC is: a word by default, the percentage (and for bodies how they were linked)
/// with Advanced details.
String scoreLabel(
  AppLocalizations l, {
  required bool advanced,
  required ReviewQuestionKind kind,
  required double score,
  String? method,
}) {
  if (!advanced) {
    return likelihoodWord(l, likelihoodOf(kind, score, method: method));
  }
  final percent = (score * 100).round();
  if (kind == ReviewQuestionKind.outfit) {
    return l.bodyLinkDetail(
      method == 'appearance' ? l.linkOutfit : l.linkWeakFace,
      percent,
    );
  }
  return l.similarityPercent(percent);
}
