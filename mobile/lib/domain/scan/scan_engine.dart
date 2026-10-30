import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../../data/api/api_exception.dart';
import '../../data/api/dtos/analyze.dart';
import '../../data/api/mobile_api.dart';
import '../../data/api/video_api.dart';
import '../../data/db/app_database.dart';
import '../../data/media/media_library.dart';
import '../../data/repositories/app_settings.dart';
import '../../data/repositories/library_repository.dart';
import '../grouping/grouping_config.dart';
import '../grouping/grouping_runner.dart';
import 'photo_result_store.dart';
import 'scan_state.dart';
import 'video_scan.dart';

/// How long the engine keeps retrying a busy / unreachable PC before it pauses by itself.
class ScanPolicy {
  const ScanPolicy({
    this.busyRetries =
        20, // x Retry-After (15 s) = about 5 minutes of a busy GPU
    this.offlineRetries = 4, // 3 s, 6 s, 12 s, 24 s
    this.serverErrorRetries = 2,
    this.defaultBusyWait = const Duration(seconds: 15),
    this.cacheClearEvery = 40,
  });

  final int busyRetries;
  final int offlineRetries;
  final int serverErrorRetries;
  final Duration defaultBusyWait;
  final int cacheClearEvery;
}

/// Scans the phone's photos into the library:
///
///   list the chosen albums -> queue new / edited photos (the `media` table is the queue)
///   -> per photo: downscale <= 2560 px JPEG -> POST /v1/analyze/image -> dedupe against the
///      library -> faces, bodies and crops in ONE transaction
///   -> every so often (and at the end): grouping rounds on the PC
///
/// Everything is persistent and idempotent: kill the app at any moment and the next [start] picks
/// up where it stopped (a photo being scanned goes back to the queue; a finished photo is never
/// redone). A busy GPU (503) is waited out, an unreachable PC is retried with backoff and then the
/// scan pauses by itself - nothing is lost either way.
class ScanEngine {
  ScanEngine({
    required LibraryRepository library,
    required this._media,
    required this._api,
    required this._settings,
    required this._store,
    required this._grouping,
    this._videoScan,
    String Function(String, double)? describeVideo,
    this._keepAlive = const NoKeepAlive(),
    this._policy = const ScanPolicy(),
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
    String Function(ScanProgress)? describe,
    String keepAliveTitle = 'Scanning your photos',
  }) : _repo = library,
       _clock = clock ?? DateTime.now,
       _delay = delay ?? ((d) => Future<void>.delayed(d)),
       _describe = describe ?? _defaultDescribe,
       _title = keepAliveTitle,
       _describeVideo =
           describeVideo ??
           ((stage, progress) => '$stage ${(progress * 100).round()}%');

  final LibraryRepository _repo;
  final MediaLibrary _media;
  final MobileApi? Function() _api;
  final AppSettings _settings;
  final PhotoResultStore _store;
  final GroupingRunner _grouping;
  final ScanKeepAlive _keepAlive;
  final ScanPolicy _policy;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;
  final String Function(ScanProgress) _describe;
  final String _title;
  final VideoScan? _videoScan;
  final String Function(String, double) _describeVideo;

  static String _defaultDescribe(ScanProgress p) =>
      '${p.done + p.failed}/${p.total} photos, ${p.facesFound} faces';

  final _controller = StreamController<ScanProgress>.broadcast();
  ScanProgress _progress = const ScanProgress();
  bool _active = false;
  Completer<void>? _settled;
  bool _pauseRequested = false;
  bool _allowReconnectResume = true;
  bool _keepAliveOn = false;
  DateTime _lastNotification = DateTime.fromMillisecondsSinceEpoch(0);
  Future<(String, Uint8List?)?>? _preparedPhoto;

  ScanProgress get progress => _progress;
  Stream<ScanProgress> get stream => _controller.stream;
  bool get isRunning => _active;

  void _emit(ScanProgress next) {
    _progress = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  /// Asks the running scan to stop after the photo it is on.
  void pause() {
    _allowReconnectResume = false;
    _pauseRequested = true;
  }

  /// Waits until all current database/file writes and grouping have settled.
  /// Backup and restore must not race the photo currently being analysed.
  Future<void> pauseAndWait() async {
    pause();
    await _settled?.future;
  }

  /// Hides the summary of a finished scan (the progress card goes away).
  void dismiss() {
    if (!_active && _progress.phase == ScanPhase.completed) {
      _emit(const ScanProgress());
    }
  }

  Future<void> dispose() async {
    pause();
    await _controller.close();
  }

  /// After a restart: if a scan was running when the app died, carry on (without re-listing the albums).
  Future<void> resumeIfInterrupted() async {
    if (_active) return;
    final prefs = await _settings.load();
    if (prefs.scanActive && _api() != null) {
      await start(enumerate: false);
    }
  }

  Future<void> resumeAfterConnectionRestored() async {
    if (_allowReconnectResume &&
        !_active &&
        _progress.phase == ScanPhase.paused &&
        _progress.pauseReason == PauseReason.offline) {
      await start(enumerate: false);
    }
  }

  /// Runs until the queue is empty or the scan is paused. `enumerate` = list the chosen albums first
  /// (a new scan); false = just work through what is already queued (resume).
  Future<void> start({bool enumerate = true}) async {
    if (_active) return;
    _allowReconnectResume = true;
    _active = true;
    final settled = _settled = Completer<void>();
    _pauseRequested = false;
    try {
      await _run(enumerate);
    } catch (e) {
      await _pause(PauseReason.error, '$e');
    } finally {
      try {
        await _preparedPhoto;
        _preparedPhoto = null;
        if (_keepAliveOn) {
          _keepAliveOn = false;
          await _keepAlive.stop();
        }
      } finally {
        _active = false;
        _settled = null;
        settled.complete();
      }
    }
  }

  Future<void> _pause(PauseReason reason, [String? message]) async {
    await _settings.setScanActive(false);
    _emit(
      _progress.copyWith(
        phase: ScanPhase.paused,
        pauseReason: reason,
        message: message,
        clearMessage: message == null,
        grouping: false,
        clearEta: true,
      ),
    );
  }

  Future<void> _run(bool enumerate) async {
    final api = _api();
    if (api == null) {
      await _pause(PauseReason.notPaired);
      return;
    }
    final prefs = await _settings.load();
    _emit(const ScanProgress(phase: ScanPhase.preparing));
    if (prefs.scanCharacters &&
        !(await api.capabilities()).engines.characterDetection) {
      await _pause(
        PauseReason.error,
        'Character detection is unavailable. Update the PC server and check its body models.',
      );
      return;
    }

    if (!await _media.requestAccess()) {
      await _pause(PauseReason.noAccess);
      return;
    }
    await _keepAlive.start(title: _title, text: _describe(_progress));
    _keepAliveOn = true;
    if (enumerate) {
      if (prefs.albumIds.isEmpty) {
        await _pause(PauseReason.noAlbums);
        return;
      }
      await _repo.resetScanning();
      await _repo.skipPending();
      var found = const SyncResult();
      await for (final page in _media.photos(prefs.albumIds.toSet())) {
        found += await _repo.syncAssets([
          for (final asset in page)
            if (asset.kind != 'video' || prefs.scanVideos) asset,
        ]);
        _emit(
          ScanProgress(
            phase: ScanPhase.preparing,
            found: found.queued + found.unchanged,
            total: found.queued,
          ),
        );
        if (_pauseRequested) break;
      }
      if (_pauseRequested) {
        await _pause(PauseReason.user);
        return;
      }
    }
    await _repo.resetScanning();
    final counts = await _repo.scanCounts();

    var modelId = prefs.modelId;
    final started = _clock();
    var done = 0,
        failed = 0,
        facesFound = 0,
        linked = 0,
        bodies = 0,
        characters = 0;
    var sinceGroupingPhotos = 0, sinceGroupingFaces = 0;
    final durations = Queue<double>();
    MediaRow? current;
    Uint8List? previewBytes;
    int? previewTimestampMs;

    void prepareNextPhoto() {
      _preparedPhoto = () async {
        try {
          final next = await _repo.nextPending();
          if (next == null || next.kind != 'photo' || _pauseRequested) {
            return null;
          }
          final bytes = await _media.downscaledJpeg(
            next.assetId,
            width: next.width ?? 0,
            height: next.height ?? 0,
            maxSide: prefs.maxSide,
          );
          return (next.assetId, bytes);
        } on Exception {
          return null;
        }
      }();
    }

    ScanProgress snapshot({
      ScanPhase phase = ScanPhase.running,
      String? message,
    }) {
      Duration? eta;
      if (durations.isNotEmpty) {
        final avg = durations.reduce((a, b) => a + b) / durations.length;
        eta = Duration(
          seconds: (avg * (counts.remaining - done - failed).clamp(0, 1 << 30))
              .round(),
        );
      }
      return ScanProgress(
        phase: phase,
        message: message,
        total: counts.remaining,
        done: done,
        failed: failed,
        facesFound: facesFound,
        facesLinked: linked,
        bodiesFound: bodies,
        charactersFound: characters,
        eta: eta,
        startedAt: started,
        currentAssetId: current?.assetId,
        currentKind: current?.kind,
        previewBytes: previewBytes,
        previewTimestampMs: previewTimestampMs,
      );
    }

    await _settings.setScanActive(true);
    _emit(snapshot());

    Future<void> notify() async {
      final now = _clock();
      if (now.difference(_lastNotification) < const Duration(seconds: 2)) {
        return;
      }
      _lastNotification = now;
      await _keepAlive.update(_describe(_progress));
    }

    Future<void> groupNow({bool incremental = false}) async {
      if (prefs.scanCharacters) return;
      if (_api() == null) return;
      _emit(_progress.copyWith(grouping: true));
      try {
        await _grouping.run(incremental: incremental);
      } on ApiException catch (e) {
        // grouping is repeatable at any time (Review has a "Sort now" button): never fail the scan for it
        _emit(_progress.copyWith(message: e.message));
      } finally {
        _emit(_progress.copyWith(grouping: false));
      }
      sinceGroupingPhotos = 0;
      sinceGroupingFaces = 0;
    }

    while (true) {
      if (_pauseRequested) {
        if (sinceGroupingFaces > 0) await groupNow();
        await _pause(PauseReason.user);
        return;
      }
      final prepared = await _preparedPhoto;
      _preparedPhoto = null;
      final row = await _repo.claimNext();
      if (row == null) break;
      current = row;
      previewBytes = null;
      previewTimestampMs = null;
      _emit(snapshot());
      final watch = Stopwatch()..start();

      final result = await _scanOne(
        row,
        api: api,
        prefs: prefs,
        modelId: modelId,
        snapshot: snapshot,
        preparedPhoto: prepared?.$1 == row.assetId ? prepared?.$2 : null,
        prepareNextPhoto: prepareNextPhoto,
        preview: (bytes, timestamp) {
          previewBytes = bytes;
          previewTimestampMs = timestamp;
          _emit(snapshot());
        },
      );
      switch (result) {
        case _Paused():
          if (sinceGroupingFaces > 0) await groupNow();
          return;
        case _Failed():
          failed++;
        case _Scanned(:final outcome, :final model):
          modelId = model;
          done++;
          facesFound += outcome.newFaces;
          linked += outcome.linkedFaces;
          bodies += outcome.newBodies;
          characters += outcome.newCharacters;
          sinceGroupingFaces += outcome.newFaces;
      }
      sinceGroupingPhotos++;
      current = null;
      previewBytes = null;
      previewTimestampMs = null;
      durations.addLast(watch.elapsedMilliseconds / 1000.0);
      if (durations.length > 15) durations.removeFirst();
      _emit(snapshot());
      await notify();
      if ((done + failed) % _policy.cacheClearEvery == 0) {
        await _preparedPhoto;
        await _media.clearCache();
      }

      if (sinceGroupingFaces >= groupEveryNewFaces ||
          sinceGroupingPhotos >= groupEveryPhotos) {
        await groupNow(incremental: true);
        _emit(snapshot());
      }
    }

    await groupNow();
    await _media.clearCache();
    await _settings.setScanActive(false);
    _emit(
      snapshot(
        phase: ScanPhase.completed,
      ).copyWith(grouping: false, clearEta: true),
    );
  }

  Future<_Result> _scanOne(
    MediaRow row, {
    required MobileApi api,
    required SettingsSnapshot prefs,
    required String? modelId,
    required ScanProgress Function({ScanPhase phase, String? message}) snapshot,
    required void Function(Uint8List bytes, int? timestampMs) preview,
    Uint8List? preparedPhoto,
    required void Function() prepareNextPhoto,
  }) async {
    Uint8List? bytes;
    try {
      if (row.kind == 'video') {
        final thumb = await _media.thumbnail(
          row.assetId,
          width: row.width ?? 0,
          height: row.height ?? 0,
          size: 480,
        );
        if (thumb != null) preview(thumb, null);
      } else {
        bytes =
            preparedPhoto ??
            await _media.downscaledJpeg(
              row.assetId,
              width: row.width ?? 0,
              height: row.height ?? 0,
              maxSide: prefs.maxSide,
            );
        if (bytes != null) preview(bytes, null);
      }
    } on Exception {
      // A missing/corrupt file must not pause every remaining item in the queue.
    }
    if (bytes == null && row.kind != 'video') {
      await _repo.markFailed(
        row.id,
        'The photo could not be read (it was deleted or is not a supported format).',
      );
      return const _Failed();
    }

    prepareNextPhoto();
    var busy = 0, offline = 0, serverErrors = 0;
    while (true) {
      try {
        if (row.kind == 'video') {
          final scanner = _videoScan;
          final media = _media;
          if (scanner == null ||
              api is! VideoApi ||
              media is! VideoMediaLibrary) {
            await _repo.markFailed(
              row.id,
              'Video scanning is unavailable. Update the phone app and PC server.',
            );
            return const _Failed();
          }
          final outcome = await scanner.run(
            row,
            api: api as VideoApi,
            library: media as VideoMediaLibrary,
            prefs: prefs,
            paused: () => _pauseRequested,
            report: (stage, progress) {
              _emit(snapshot(message: _describeVideo(stage, progress)));
              unawaited(_keepAlive.update(_describe(_progress)));
            },
            onPreview: preview,
          );
          return _Scanned(
            outcome,
            (await _settings.load()).modelId ?? modelId ?? 'buffalo_l@1',
          );
        }
        final response = await api.analyzeImage(
          bytes!,
          options: AnalyzeOptions(
            detectBodies: prefs.scanBodies,
            detectCharacters: prefs.scanCharacters,
            minQuality: prefs.qualityGate,
            modelId: modelId,
          ),
        );
        if (!prefs.scanCharacters &&
            modelId != null &&
            response.modelId != modelId) {
          return _stop(row.id, PauseReason.modelMismatch, response.modelId);
        }
        if (!prefs.scanCharacters && modelId == null) {
          await _settings.setModelId(response.modelId);
        }
        final media = await _repo.mediaById(row.id);
        if (media == null) {
          return const _Failed(); // deleted from the library while it was being analysed
        }
        final outcome = await _store.store(media, response);
        return _Scanned(outcome, response.modelId);
      } on VideoScanPaused {
        return _stop(row.id, PauseReason.user);
      } on ApiException catch (e) {
        if (e.code == 'engine_unavailable' && !e.retryable) {
          return _stop(row.id, PauseReason.error, e.message);
        }
        if (e.isGpuBusy || e.isResourcePressure) {
          busy++;
          if (busy > _policy.busyRetries) {
            return _stop(
              row.id,
              PauseReason.pcBusy,
              e.isResourcePressure ? e.message : null,
            );
          }
          _emit(snapshot(phase: ScanPhase.waiting, message: e.message));
          if (!await _sleep(e.retryAfter ?? _policy.defaultBusyWait)) {
            return _stop(row.id, PauseReason.user);
          }
          _emit(snapshot());
          continue;
        }
        if (e.isOffline) {
          offline++;
          if (offline > _policy.offlineRetries) {
            return _stop(row.id, PauseReason.offline, e.message);
          }
          _emit(snapshot(phase: ScanPhase.waiting, message: e.message));
          if (!await _sleep(Duration(seconds: 3 * (1 << (offline - 1))))) {
            return _stop(row.id, PauseReason.user);
          }
          _emit(snapshot());
          continue;
        }
        if (e.isUnauthorized || e.code == ApiException.certificateCode) {
          return _stop(row.id, PauseReason.revoked, e.message);
        }
        if (e.code == 'model_mismatch') {
          return _stop(row.id, PauseReason.modelMismatch, e.message);
        }
        if (e.retryable && serverErrors < _policy.serverErrorRetries) {
          serverErrors++;
          if (!await _sleep(const Duration(seconds: 2))) {
            return _stop(row.id, PauseReason.user);
          }
          continue;
        }
        await _repo.markFailed(row.id, e.message);
        return const _Failed();
      }
    }
  }

  /// Gives the photo back to the queue and pauses (the photo is not at fault).
  Future<_Result> _stop(
    int mediaId,
    PauseReason reason, [
    String? message,
  ]) async {
    await _repo.requeue(mediaId);
    await _pause(reason, message);
    return const _Paused();
  }

  /// Waits `total`, in short slices so a pause request is noticed. False = the user paused meanwhile.
  Future<bool> _sleep(Duration total) async {
    var left = total;
    const slice = Duration(seconds: 1);
    while (left > Duration.zero) {
      if (_pauseRequested) return false;
      final step = left < slice ? left : slice;
      await _delay(step);
      left -= step;
    }
    return !_pauseRequested;
  }
}

sealed class _Result {
  const _Result();
}

class _Paused extends _Result {
  const _Paused();
}

class _Failed extends _Result {
  const _Failed();
}

class _Scanned extends _Result {
  const _Scanned(this.outcome, this.model);
  final StoreOutcome outcome;
  final String model;
}
