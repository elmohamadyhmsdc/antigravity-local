import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_exception.dart';
import '../../data/api/dtos/analyze.dart';
import '../../providers.dart';

sealed class AnalyzeState {
  const AnalyzeState();
}

class AnalyzeIdle extends AnalyzeState {
  const AnalyzeIdle();
}

class AnalyzeWorking extends AnalyzeState {
  const AnalyzeWorking(this.photo);
  final Uint8List photo;
}

class AnalyzeDone extends AnalyzeState {
  const AnalyzeDone(this.photo, this.result);
  final Uint8List photo;
  final AnalyzeImageResponse result;
}

class AnalyzeFailed extends AnalyzeState {
  const AnalyzeFailed(this.error, this.photo);
  final ApiException error;
  final Uint8List photo;
}

/// face_quality.TIERS on the server: >=0.75 great, >=0.55 good, >=0.35 fair, else poor.
enum QualityTier { great, good, fair, poor }

QualityTier qualityTier(double score) {
  if (score >= 0.75) return QualityTier.great;
  if (score >= 0.55) return QualityTier.good;
  if (score >= 0.35) return QualityTier.fair;
  return QualityTier.poor;
}

/// Pick one photo, send it to the PC, show what came back. (The P1 end-to-end check; the
/// library scan in P2 uses the same endpoint for every photo.)
class AnalyzeController extends Notifier<AnalyzeState> {
  @override
  AnalyzeState build() => const AnalyzeIdle();

  Future<void> pickAndAnalyze() async {
    if (state is AnalyzeWorking) return;
    final photo = await ref.read(photoPickerProvider).pickPhoto();
    if (photo == null) return; // cancelled
    await _analyze(photo);
  }

  Future<void> retry() async {
    final current = state;
    if (current is AnalyzeFailed) await _analyze(current.photo);
  }

  Future<void> _analyze(Uint8List photo) async {
    final api = ref.read(mobileApiProvider);
    if (api == null) return;
    state = AnalyzeWorking(photo);
    try {
      final result = await api.analyzeImage(photo);
      state = AnalyzeDone(photo, result);
    } on ApiException catch (e) {
      state = AnalyzeFailed(e, photo);
    }
  }
}

final analyzeControllerProvider =
    NotifierProvider.autoDispose<AnalyzeController, AnalyzeState>(
      AnalyzeController.new,
    );
