import 'package:antigravity_mobile/domain/export/export_selection.dart';
import 'package:flutter_test/flutter_test.dart';

var _id = 0;

ExportCandidate cand({
  ExportKind kind = ExportKind.face,
  int media = 1,
  bool video = true,
  int? t,
  double quality = 0.7,
  double? yaw,
  double? pitch,
  double w = 0.1,
  double h = 0.1,
  int imgW = 3840,
  int imgH = 2160,
  String? extent,
}) => ExportCandidate(
  detectionId: ++_id,
  kind: kind,
  mediaId: media,
  assetId: '$media',
  isVideo: video,
  x: 0.4,
  y: 0.4,
  w: w,
  h: h,
  quality: quality,
  timestampMs: t,
  yaw: yaw,
  pitch: pitch,
  imgW: imgW,
  imgH: imgH,
  extent: extent,
);

void main() {
  setUp(() => _id = 0);

  test('a photo keeps only its best detection of each kind', () {
    final out = selectDiverse([
      cand(video: false, quality: 0.5),
      cand(video: false, quality: 0.9),
      cand(video: false, kind: ExportKind.body, h: 0.5, quality: 0.6),
    ]);
    expect(out.length, 2);
    expect(out.firstWhere((c) => c.kind == ExportKind.face).quality, 0.9);
  });

  test('a video is capped and spread over its whole length', () {
    final frames = [
      for (var i = 0; i < 600; i++)
        cand(
          t: i * 500,
          quality: i < 100 ? 0.95 : 0.6,
        ), // the best are all early
    ];
    final out = selectDiverse(
      frames,
      const ExportSelectionOptions(maxPerVideo: 12),
    );
    expect(out.length, 12);
    final times = out.map((c) => c.timestampMs!).toList()..sort();
    // not clustered in the sharp first 50 s: the last pick is near the end
    expect(times.last, greaterThan(250000));
    expect(times.first, lessThan(50000));
    // every pick keeps the minimum gap
    for (var i = 1; i < times.length; i++) {
      expect(times[i] - times[i - 1], greaterThanOrEqualTo(1000));
    }
  });

  test('fewer candidates than the cap are all kept', () {
    final out = selectDiverse([for (var i = 0; i < 5; i++) cand(t: i * 5000)]);
    expect(out.length, 5);
  });

  test('the minimum gap stops a burst of frames from filling the cap', () {
    final out = selectDiverse([
      for (var i = 0; i < 50; i++) cand(t: i * 100), // 5 s in 100 ms steps
    ]);
    expect(out.length, lessThanOrEqualTo(5));
  });

  test(
    'a different head pose is preferred over a similar one at the same distance',
    () {
      final out = selectDiverse([
        cand(t: 0, yaw: 0, pitch: 0, quality: 0.9),
        cand(t: 10000, yaw: 0, pitch: 0, quality: 0.8),
        cand(
          t: 10000,
          yaw: 60,
          pitch: 0,
          quality: 0.8,
          media: 1,
        ), // same moment: replaced by better
        cand(t: 20000, yaw: 0, pitch: 0, quality: 0.8),
        cand(t: 20000 + 1500, yaw: 55, pitch: 10, quality: 0.8),
      ], const ExportSelectionOptions(maxPerVideo: 3));
      expect(out.any((c) => (c.yaw ?? 0) >= 50), isTrue);
    },
  );

  test('one person once per moment: the better detection of a frame wins', () {
    final out = selectDiverse([
      cand(t: 3000, quality: 0.5),
      cand(t: 3000, quality: 0.9),
    ]);
    expect(out.length, 1);
    expect(out.single.quality, 0.9);
  });

  test('boxes below the minimum native size are dropped', () {
    final out = selectDiverse([
      cand(t: 0, w: 0.01, h: 0.01), // 38 px
      cand(
        t: 5000,
        w: 0.05,
        h: 0.05,
        imgH: 2160,
      ), // 108 px tall, 192 wide: min side 108
    ]);
    expect(out.length, 1);
    expect(out.single.timestampMs, 5000);
  });

  test(
    'head-only bodies are not body pictures; faces of other media are separate',
    () {
      final out = selectDiverse([
        cand(kind: ExportKind.body, h: 0.5, extent: 'head', t: 0),
        cand(kind: ExportKind.body, h: 0.5, extent: 'full', t: 4000),
        cand(media: 2, t: 0),
      ]);
      expect(out.where((c) => c.kind == ExportKind.body).length, 1);
      expect(out.where((c) => c.mediaId == 2).length, 1);
    },
  );

  test('the result is ordered by media then time and is deterministic', () {
    List<ExportCandidate> build() => [
      cand(media: 2, t: 9000),
      cand(media: 1, t: 8000),
      cand(media: 1, t: 1000),
    ];
    _id = 0;
    final a = selectDiverse(build()).map((c) => (c.mediaId, c.timestampMs));
    _id = 0;
    final b = selectDiverse(
      build().reversed,
    ).map((c) => (c.mediaId, c.timestampMs));
    expect(a.toList(), [(1, 1000), (1, 8000), (2, 9000)]);
    expect(b.toList(), a.toList());
  });
}
