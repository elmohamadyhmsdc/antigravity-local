import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/platform/crop_source.dart';
import '../../data/platform/foreground_keep_alive.dart';
import '../../domain/export/training_export.dart';
import '../../domain/scan/scan_state.dart';
import '../../providers.dart';

enum TrainingExportPhase { idle, running, done, cancelled, failed }

class TrainingExportState {
  const TrainingExportState({
    this.phase = TrainingExportPhase.idle,
    this.personId,
    this.progress,
    this.result,
    this.error,
  });

  final TrainingExportPhase phase;
  final int? personId;
  final ExportProgress? progress;
  final TrainingExportResult? result;
  final String? error;

  bool get running => phase == TrainingExportPhase.running;
}

final cropSourceProvider = Provider<CropSource>(
  (ref) => const AndroidCropSource(),
);

/// Shown in the foreground-service notification while an export runs with the screen off.
final trainingExportKeepAliveProvider = Provider<ScanKeepAlive>(
  (ref) => const ForegroundServiceKeepAlive(
    channelName: 'Training export',
    channelDescription: 'Full-resolution face and body export',
  ),
);

/// Runs one export at a time as app-level work: closing the dialog or leaving the person page
/// does not stop it, and the foreground service keeps it going with the screen off.
class TrainingExportController extends Notifier<TrainingExportState> {
  ExportCancelToken? _cancel;

  @override
  TrainingExportState build() => const TrainingExportState();

  Future<TrainingExporter> _exporter() async {
    final support = await getApplicationSupportDirectory();
    final cache = await getApplicationCacheDirectory();
    return TrainingExporter(
      queries: TrainingExportQueries(ref.read(databaseProvider)),
      source: ref.read(cropSourceProvider),
      workRoot: Directory(p.join(support.path, 'training_export_work')),
      outputDir: Directory(p.join(cache.path, 'training_exports')),
    );
  }

  Future<void> start(
    TrainingExportOptions options, {
    String personName = '',
    String notificationTitle = 'Exporting training pictures',
  }) async {
    if (state.running) return;
    final cancel = _cancel = ExportCancelToken();
    state = TrainingExportState(
      phase: TrainingExportPhase.running,
      personId: options.personId,
      progress: const ExportProgress(phase: 'planning'),
    );
    final keepAlive = ref.read(trainingExportKeepAliveProvider);
    var lastNote = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await keepAlive.start(title: notificationTitle, text: personName);
      final exporter = await _exporter();
      final result = await exporter.run(
        options,
        personName: personName,
        cancel: cancel,
        onProgress: (progress) {
          state = TrainingExportState(
            phase: TrainingExportPhase.running,
            personId: options.personId,
            progress: progress,
          );
          final now = DateTime.now();
          if (now.difference(lastNote).inSeconds >= 5) {
            lastNote = now;
            unawaited(keepAlive.update('${progress.done} / ${progress.total}'));
          }
        },
      );
      state = TrainingExportState(
        phase: result.cancelled
            ? TrainingExportPhase.cancelled
            : TrainingExportPhase.done,
        personId: options.personId,
        result: result,
      );
    } on Object catch (e) {
      state = TrainingExportState(
        phase: TrainingExportPhase.failed,
        personId: options.personId,
        error: '$e',
      );
    } finally {
      try {
        await keepAlive.stop();
      } on Object {
        // a notification that cannot be removed is not an export failure
      }
    }
  }

  /// Stops after the current picture. Finished pictures stay, so starting again resumes.
  void cancel() => _cancel?.cancel();

  /// Forgets the last outcome (and deletes its zip when [deleteZip]).
  Future<void> dismiss({bool deleteZip = false}) async {
    final zip = state.result?.zip;
    if (deleteZip && zip != null && await zip.exists()) await zip.delete();
    if (!state.running) state = const TrainingExportState();
  }
}

final trainingExportProvider =
    NotifierProvider<TrainingExportController, TrainingExportState>(
      TrainingExportController.new,
    );
