import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart' show QueryRow, Variable;
import 'package:path/path.dart' as p;

import '../../data/db/app_database.dart';
import '../../data/platform/crop_source.dart';
import 'crop_math.dart';
import 'export_selection.dart';

/// What to export for one person. Everything that changes the pictures is part of [signature],
/// so a changed option starts a new job instead of mixing two sizes in one folder.
class TrainingExportOptions {
  const TrainingExportOptions({
    required this.personId,
    this.faces = true,
    this.bodies = false,
    this.faceSize = 512,
    this.bodyLongSide = 1024,
    this.faceMargin = 1.6,
    this.bodyMargin = 1.1,
    this.maxUpscale = 2.0,
    this.jpegQuality = 95,
    this.selection = const ExportSelectionOptions(),
  });

  final int personId;
  final bool faces, bodies;

  /// Faces are square, [faceSize] x [faceSize].
  final int faceSize;

  /// Bodies keep their aspect ratio; the long side is at most this (never enlarged).
  final int bodyLongSide;
  final double faceMargin, bodyMargin;

  /// A face crop smaller than faceSize / maxUpscale pixels is skipped, not blown up.
  final double maxUpscale;
  final int jpegQuality;
  final ExportSelectionOptions selection;

  String get signature => [
    'p$personId',
    if (faces) 'f$faceSize',
    if (bodies) 'b$bodyLongSide',
    'm$faceMargin-$bodyMargin',
    'u$maxUpscale',
    'q$jpegQuality',
    'n${selection.maxPerVideo}-${selection.minGapMs}',
    's${selection.minFaceBoxPx}-${selection.minBodyHeightPx}',
  ].join('_').replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');

  Map<String, Object?> toJson() => {
    'personId': personId,
    'faces': faces,
    'bodies': bodies,
    'faceSize': faceSize,
    'bodyLongSide': bodyLongSide,
    'faceMargin': faceMargin,
    'bodyMargin': bodyMargin,
    'maxUpscale': maxUpscale,
    'jpegQuality': jpegQuality,
    'maxPerVideo': selection.maxPerVideo,
    'minGapMs': selection.minGapMs,
    'minFaceBoxPx': selection.minFaceBoxPx,
    'minBodyHeightPx': selection.minBodyHeightPx,
  };
}

class ExportCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class ExportProgress {
  const ExportProgress({
    required this.phase,
    this.done = 0,
    this.total = 0,
    this.exported = 0,
    this.skipped = 0,
  });

  /// planning | exporting | packing
  final String phase;
  final int done, total, exported, skipped;
}

class TrainingExportResult {
  const TrainingExportResult({
    this.zip,
    this.exported = 0,
    this.tooSmall = 0,
    this.missing = 0,
    this.failed = 0,
    this.cancelled = false,
  });

  /// Null while cancelled, or when nothing could be exported.
  final File? zip;
  final int exported, tooSmall, missing, failed;
  final bool cancelled;
}

/// Every detection of the person that could become a training picture, with the stored
/// face/body quality attached. A video's other frames point at their track's kept view, so the
/// view's quality and pose stand in for them.
class TrainingExportQueries {
  TrainingExportQueries(this.db);

  final AppDatabase db;

  Future<List<ExportCandidate>> candidates(TrainingExportOptions o) async {
    final out = <ExportCandidate>[];
    if (o.faces) {
      final rows = await db
          .customSelect(
            'SELECT md.id AS det, md.media_id, md.ref_id, md.x, md.y, md.w, md.h, '
            'md.frame_number, md.timestamp_ms, f.quality_score AS q, f.yaw, f.pitch, '
            'm.asset_id, m.kind, m.width, m.height, m.duration_ms '
            'FROM media_detections md '
            'JOIN faces f ON f.id = md.ref_id '
            'JOIN media m ON m.id = md.media_id '
            "WHERE md.kind = 'f' AND f.person_id = ? AND f.hidden = 0 AND (f.ownership IS NULL OR f.ownership != 'none')",
            variables: [Variable.withInt(o.personId)],
          )
          .get();
      out.addAll(rows.map((r) => _candidate(r, ExportKind.face)).nonNulls);
    }
    if (o.bodies) {
      final rows = await db
          .customSelect(
            'SELECT md.id AS det, md.media_id, md.ref_id, md.x, md.y, md.w, md.h, '
            'md.frame_number, md.timestamp_ms, b.score AS q, b.extent, '
            'm.asset_id, m.kind, m.width, m.height, m.duration_ms '
            'FROM media_detections md '
            'JOIN bodies b ON b.id = md.ref_id '
            'LEFT JOIN faces f ON f.id = b.face_id '
            'JOIN media m ON m.id = md.media_id '
            "WHERE md.kind = 'b' AND b.hidden = 0 AND (b.ownership IS NULL OR b.ownership != 'none') AND (b.person_id = ? "
            "OR (b.person_id IS NULL AND f.person_id = ? AND f.hidden = 0 AND (f.ownership IS NULL OR f.ownership != 'none')))",
            variables: [
              Variable.withInt(o.personId),
              Variable.withInt(o.personId),
            ],
          )
          .get();
      out.addAll(rows.map((r) => _candidate(r, ExportKind.body)).nonNulls);
    }
    return out;
  }

  ExportCandidate? _candidate(QueryRow row, ExportKind kind) {
    final isVideo = row.read<String>('kind') == 'video';
    final ts = row.readNullable<int>('timestamp_ms');
    // A video frame is addressed by its time; without one it cannot be decoded again.
    if (isVideo && ts == null) return null;
    final face = kind == ExportKind.face;
    return ExportCandidate(
      detectionId: row.read<int>('det'),
      kind: kind,
      mediaId: row.read<int>('media_id'),
      refId: row.read<int>('ref_id'),
      assetId: row.read<String>('asset_id'),
      isVideo: isVideo,
      x: row.read<double>('x'),
      y: row.read<double>('y'),
      w: row.read<double>('w'),
      h: row.read<double>('h'),
      quality: row.readNullable<double>('q') ?? 0.5,
      timestampMs: ts,
      frameNumber: row.readNullable<int>('frame_number'),
      yaw: face ? row.readNullable<double>('yaw') : null,
      pitch: face ? row.readNullable<double>('pitch') : null,
      extent: face ? null : row.readNullable<String>('extent'),
      imgW: row.readNullable<int>('width'),
      imgH: row.readNullable<int>('height'),
      durationMs: row.readNullable<int>('duration_ms'),
    );
  }
}

String entryKey(ExportCandidate c) =>
    '${c.kind == ExportKind.face ? 'f' : 'b'}${c.detectionId}';

String entryFileName(ExportCandidate c) {
  final t = (c.timestampMs ?? 0).toString().padLeft(8, '0');
  final kind = c.kind == ExportKind.face ? 'face' : 'body';
  return '${kind}s/${kind}_m${c.mediaId}_t${t}_d${c.detectionId}.jpg';
}

/// One line of the work folder's manifest: the outcome for one picked detection.
class _Entry {
  _Entry(this.key, this.status, this.info);

  final String key;

  /// ok | too_small | missing (original gone or unreadable) | failed (tried again on resume)
  final String status;
  final Map<String, Object?> info;

  bool get settled => status != 'failed';

  Map<String, Object?> toJson() => {'key': key, 'status': status, ...info};
}

/// Cuts the chosen person's faces and bodies out of the original photos and video frames.
///
/// The work is resumable: every finished picture is a file plus a manifest line in a work folder
/// named after the options. A cancelled or killed run continues where it stopped (the plan is
/// computed again, finished items are skipped); the zip is only built when everything is done.
class TrainingExporter {
  TrainingExporter({
    required this.queries,
    required this.source,
    required this.workRoot,
    required this.outputDir,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TrainingExportQueries queries;
  final CropSource source;
  final Directory workRoot;
  final Directory outputDir;
  final DateTime Function() _clock;

  Directory workDir(TrainingExportOptions o) =>
      Directory(p.join(workRoot.path, o.signature));

  /// Deletes the unfinished work of [o] (the user chose to start over).
  Future<void> discard(TrainingExportOptions o) async {
    final dir = workDir(o);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<TrainingExportResult> run(
    TrainingExportOptions o, {
    String personName = '',
    ExportCancelToken? cancel,
    void Function(ExportProgress progress)? onProgress,
  }) async {
    void report(ExportProgress progress) => onProgress?.call(progress);
    report(const ExportProgress(phase: 'planning'));
    final picks = selectDiverse(await queries.candidates(o), o.selection);
    final dir = workDir(o);
    await dir.create(recursive: true);
    final manifest = File(p.join(dir.path, 'manifest.jsonl'));
    final entries = await _load(manifest);
    final pending = [
      for (final c in picks)
        if (!(entries[entryKey(c)]?.settled ?? false)) c,
    ];
    var done = picks.length - pending.length;
    final settled = [
      for (final c in picks)
        if (entries[entryKey(c)] case final e? when e.settled) e,
    ];
    var exported = settled.where((e) => e.status == 'ok').length;
    var skipped = settled.length - exported;
    void tick() => report(
      ExportProgress(
        phase: 'exporting',
        done: done,
        total: picks.length,
        exported: exported,
        skipped: skipped,
      ),
    );
    tick();

    final sink = manifest.openWrite(mode: FileMode.append);
    String? openKey;
    SourceFrame? frame;
    var cancelled = false;
    try {
      for (final c in pending) {
        if (cancel?.isCancelled ?? false) {
          cancelled = true;
          break;
        }
        if (c.frameKey != openKey) {
          frame = await source.open(
            assetId: c.assetId,
            video: c.isVideo,
            timeMs: c.timestampMs,
          );
          openKey = c.frameKey;
        }
        final entry = await _export(o, c, frame, dir);
        entries[entry.key] = entry;
        sink.writeln(jsonEncode(entry.toJson()));
        await sink.flush();
        done++;
        if (entry.status == 'ok') {
          exported++;
        } else {
          skipped++;
        }
        tick();
      }
    } finally {
      await sink.close();
      await source.close();
    }
    if (cancelled) {
      return _result(picks, entries, cancelled: true);
    }

    report(
      ExportProgress(
        phase: 'packing',
        done: picks.length,
        total: picks.length,
        exported: exported,
        skipped: skipped,
      ),
    );
    final zip = exported == 0
        ? null
        : await _pack(o, picks, entries, dir, personName);
    if (zip != null) await dir.delete(recursive: true);
    return _result(picks, entries, zip: zip);
  }

  TrainingExportResult _result(
    List<ExportCandidate> picks,
    Map<String, _Entry> entries, {
    File? zip,
    bool cancelled = false,
  }) {
    var ok = 0, small = 0, missing = 0, failed = 0;
    for (final c in picks) {
      switch (entries[entryKey(c)]?.status) {
        case 'ok':
          ok++;
        case 'too_small':
          small++;
        case 'missing':
          missing++;
        case 'failed':
          failed++;
      }
    }
    return TrainingExportResult(
      zip: zip,
      exported: ok,
      tooSmall: small,
      missing: missing,
      failed: failed,
      cancelled: cancelled,
    );
  }

  Future<_Entry> _export(
    TrainingExportOptions o,
    ExportCandidate c,
    SourceFrame? frame,
    Directory dir,
  ) async {
    final key = entryKey(c);
    final base = <String, Object?>{
      'kind': c.kind.name,
      'detectionId': c.detectionId,
      'refId': c.refId,
      'mediaId': c.mediaId,
      'assetId': c.assetId,
      'mediaKind': c.isVideo ? 'video' : 'photo',
      'frameNumber': c.frameNumber,
      'timestampMs': c.timestampMs,
      'box': [c.x, c.y, c.w, c.h],
      'quality': c.quality,
    };
    if (frame == null) return _Entry(key, 'missing', base);
    final w = frame.width, h = frame.height;
    base['sourceSize'] = [w, h];
    final isFace = c.kind == ExportKind.face;
    final tooSmall = isFace
        ? (c.w * w < o.selection.minFaceBoxPx ||
              c.h * h < o.selection.minFaceBoxPx)
        : c.h * h < o.selection.minBodyHeightPx;
    final plan = tooSmall
        ? null
        : isFace
        ? faceCrop(
            x: c.x,
            y: c.y,
            w: c.w,
            h: c.h,
            imgW: w,
            imgH: h,
            outSize: o.faceSize,
            margin: o.faceMargin,
            maxUpscale: o.maxUpscale,
          )
        : bodyCrop(
            x: c.x,
            y: c.y,
            w: c.w,
            h: c.h,
            imgW: w,
            imgH: h,
            longSide: o.bodyLongSide,
            margin: o.bodyMargin,
          );
    if (plan == null) return _Entry(key, 'too_small', base);
    base['crop'] = [
      plan.source.left,
      plan.source.top,
      plan.source.width,
      plan.source.height,
    ];
    base['outputSize'] = [plan.outWidth, plan.outHeight];
    final bytes = await source.crop(
      frame,
      plan.source,
      outWidth: plan.outWidth,
      outHeight: plan.outHeight,
      quality: o.jpegQuality,
    );
    if (bytes == null || bytes.isEmpty) return _Entry(key, 'failed', base);
    final name = entryFileName(c);
    final file = File(p.join(dir.path, name));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    base['file'] = name;
    return _Entry(key, 'ok', base);
  }

  /// A last line cut off by a killed app is ignored; that item is simply done again.
  Future<Map<String, _Entry>> _load(File manifest) async {
    final out = <String, _Entry>{};
    if (!await manifest.exists()) return out;
    for (final line in await manifest.readAsLines()) {
      try {
        final json = jsonDecode(line);
        if (json is! Map<String, dynamic>) continue;
        final key = json['key'];
        final status = json['status'];
        if (key is! String || status is! String) continue;
        if (status == 'ok') {
          final file = json['file'];
          // The picture must still be there, or it is made again.
          if (file is! String ||
              !File(p.join(manifest.parent.path, file)).existsSync()) {
            continue;
          }
        }
        out[key] = _Entry(
          key,
          status,
          {...json}
            ..remove('key')
            ..remove('status'),
        );
      } on FormatException {
        continue;
      }
    }
    return out;
  }

  Future<File> _pack(
    TrainingExportOptions o,
    List<ExportCandidate> picks,
    Map<String, _Entry> entries,
    Directory dir,
    String personName,
  ) async {
    await outputDir.create(recursive: true);
    final safe = personName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final now = _clock();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final output = File(
      p.join(
        outputDir.path,
        '${safe.isEmpty ? 'person${o.personId}' : safe}_training_$stamp.zip',
      ),
    );
    final items = [for (final c in picks) ?entries[entryKey(c)]];
    final encoder = ZipFileEncoder()..create(output.path);
    try {
      for (final e in items) {
        final file = e.info['file'];
        if (e.status == 'ok' && file is String) {
          await encoder.addFile(File(p.join(dir.path, file)), file, 0);
        }
      }
      encoder.addArchiveFile(
        ArchiveFile.string(
          'manifest.json',
          const JsonEncoder.withIndent('  ').convert({
            'format': 1,
            'createdAt': now.toIso8601String(),
            'person': personName,
            'options': o.toJson(),
            'items': [for (final e in items) e.toJson()],
          }),
        ),
      );
      encoder.addArchiveFile(ArchiveFile.string('manifest.csv', _csv(items)));
      await encoder.close();
      return output;
    } catch (_) {
      try {
        await encoder.close();
      } catch (_) {}
      if (await output.exists()) await output.delete();
      rethrow;
    }
  }

  static String _csv(List<_Entry> items) {
    String cell(Object? v) {
      final s = v == null ? '' : '$v';
      return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    String at(Object? list, int i) =>
        list is List && i < list.length ? '${list[i]}' : '';
    final rows = <List<Object?>>[
      [
        'file',
        'status',
        'kind',
        'media_kind',
        'asset_id',
        'frame_number',
        'timestamp_ms',
        'box_x',
        'box_y',
        'box_w',
        'box_h',
        'crop_left',
        'crop_top',
        'crop_w',
        'crop_h',
        'out_w',
        'out_h',
        'source_w',
        'source_h',
        'quality',
      ],
      for (final e in items)
        [
          e.info['file'],
          e.status,
          e.info['kind'],
          e.info['mediaKind'],
          e.info['assetId'],
          e.info['frameNumber'],
          e.info['timestampMs'],
          at(e.info['box'], 0),
          at(e.info['box'], 1),
          at(e.info['box'], 2),
          at(e.info['box'], 3),
          at(e.info['crop'], 0),
          at(e.info['crop'], 1),
          at(e.info['crop'], 2),
          at(e.info['crop'], 3),
          at(e.info['outputSize'], 0),
          at(e.info['outputSize'], 1),
          at(e.info['sourceSize'], 0),
          at(e.info['sourceSize'], 1),
          e.info['quality'],
        ],
    ];
    return '${rows.map((r) => r.map(cell).join(',')).join('\n')}\n';
  }
}
