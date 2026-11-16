import 'dart:math';

import 'package:antigravity_mobile/domain/scan/track_assignment.dart';
import 'package:antigravity_mobile/domain/scan/video_tracks.dart';
import 'package:flutter_test/flutter_test.dart';

const box = (x: 0.1, y: 0.1, w: 0.2, h: 0.2);

Track<int> track(int id, {int? time = 0}) => Track<int>(id)
  ..lastBox = box
  ..lastTimestampMs = time
  ..views.add(TrackView(id: id, value: id));

void main() {
  test('joint assignment preserves a second person that greedy would lose', () {
    final tracks = [track(0), track(1)];
    final scores = [
      [0.95, 0.9],
      [0.89, 0.1],
    ];
    final result = assignTracks<int>(
      values: [0, 1],
      boxes: [box, box],
      timestampMs: 500,
      tracks: tracks,
      similarity: (a, b) => scores[b][a],
      identity: 0.65,
      motion: 0.4,
    );
    expect(result.map((t) => t?.id), [1, 0]);
  });

  test('ambiguous crossing remains unmatched regardless of detector order', () {
    for (final order in [
      [0, 1],
      [1, 0],
    ]) {
      final result = assignTracks<int>(
        values: order,
        boxes: [box, box],
        timestampMs: 500,
        tracks: [track(0), track(1)],
        similarity: (_, _) => 0.9,
        identity: 0.65,
        motion: 0.4,
      );
      expect(result, [null, null]);
    }
  });

  test('a strong face cannot continue an expired or future track', () {
    for (final time in [-5000, 1000, 500]) {
      expect(
        assignTracks<int>(
          values: [0],
          boxes: [box],
          timestampMs: 500,
          tracks: [track(0, time: time)],
          similarity: (_, _) => 1,
          identity: 0.65,
          motion: 0.4,
        ),
        [null],
      );
    }
  });

  test('identical clothing elsewhere does not continue a body track', () {
    expect(
      assignTracks<int>(
        values: [0],
        boxes: [(x: 0.7, y: 0.7, w: 0.2, h: 0.2)],
        timestampMs: 500,
        tracks: [track(0)],
        similarity: (_, _) => 1,
        identity: 0.9,
        motion: 0.7,
        requireMotion: true,
      ),
      [null],
    );
  });

  test('invalid similarities never create a link', () {
    for (final invalid in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        assignTracks<int>(
          values: [0],
          boxes: [box],
          timestampMs: 500,
          tracks: [track(0)],
          similarity: (_, _) => invalid,
          identity: 0.65,
          motion: 0.4,
        ),
        [null],
      );
    }
  });

  test(
    'assignment agrees with exhaustive optima, including unmatched rows',
    () {
      final random = Random(64);
      for (var n = 1; n <= 4; n++) {
        for (var m = 0; m <= 4; m++) {
          for (var sample = 0; sample < 20; sample++) {
            final weights = List.generate(
              n,
              (_) => List.generate(
                m,
                (_) => random.nextInt(4) == 0 ? 0.0 : random.nextDouble(),
              ),
            );
            double exhaustive(int row, Set<int> used) {
              if (row == n) return 0;
              var best = exhaustive(row + 1, used);
              for (var col = 0; col < m; col++) {
                if (!used.contains(col)) {
                  best = max(
                    best,
                    weights[row][col] + exhaustive(row + 1, {...used, col}),
                  );
                }
              }
              return best;
            }

            final result = maximumTrackAssignment(weights);
            expect(result.score, closeTo(exhaustive(0, {}), 1e-10));
            final matched = result.columns.whereType<int>().toList();
            expect(matched.toSet().length, matched.length);
          }
        }
      }
    },
  );
}
