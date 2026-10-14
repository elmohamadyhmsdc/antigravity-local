import 'dart:math';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/domain/scan/scan_math.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

void main() {
  group('EmbeddingMatrix', () {
    test('finds the most similar stored face and reports its cosine', () {
      final m = EmbeddingMatrix(capacity: 2);
      final a = unitVec(1), b = unitVec(2), c = unitVec(3);
      m
        ..add(10, a)
        ..add(20, b)
        ..add(30, c);
      final hit = m.nearest(near(b, 99, 0.1))!;
      expect(hit.id, 20);
      expect(hit.cosine, closeTo(dot(b, near(b, 99, 0.1)), 1e-5));
      expect(
        m.nearest(a)!.cosine,
        closeTo(1.0, 1e-5),
        reason: 'a face is identical to itself',
      );
      expect(
        m.length,
        3,
        reason: 'the matrix grew past its first capacity of 2',
      );
    });

    test(
      'vectors are normalised on the way in and on the way out, so cosine is a plain dot product',
      () {
        final m = EmbeddingMatrix();
        final a = unitVec(7);
        m.add(
          1,
          Float32List.fromList([for (final x in a) x * 22.0]),
        ); // a raw (unnormalised) embedding
        final hit = m.nearest(
          Float32List.fromList([for (final x in a) x * 0.5]),
        )!;
        expect(hit.cosine, closeTo(1.0, 1e-5));
      },
    );

    test(
      'adding an id again replaces its vector; removing swaps the last one in and keeps every id findable',
      () {
        final m = EmbeddingMatrix();
        final v = [for (var i = 0; i < 6; i++) unitVec(100 + i)];
        for (var i = 0; i < v.length; i++) {
          m.add(i, v[i]);
        }
        m.add(2, v[5]); // replace
        expect(m.length, 6);
        expect(m.nearest(v[5])!.cosine, closeTo(1.0, 1e-5));
        m.remove(0);
        m.remove(0); // unknown id: no-op
        expect(m.length, 5);
        expect(m.contains(0), isFalse);
        for (final id in [1, 3, 4, 5]) {
          expect(
            m.nearest(v[id])!.id,
            id,
            reason: 'face $id is still found after the swap-remove',
          );
        }
        expect(
          m.nearest(v[0])!.id,
          isNot(0),
          reason: 'a removed face is never returned',
        );
      },
    );

    test(
      'an empty index matches nothing, and an all-zero vector matches nothing well',
      () {
        final m = EmbeddingMatrix();
        expect(m.nearest(unitVec(1)), isNull);
        m.add(1, unitVec(1));
        expect(m.nearest(Float32List(embeddingDim))!.cosine, 0.0);
      },
    );

    test('a wrong-sized vector is refused', () {
      expect(
        () => EmbeddingMatrix().add(1, Float32List(10)),
        throwsArgumentError,
      );
    });

    test(
      "the PC's duplicate rule: cosine >= 0.95 links, below it does not",
      () {
        final m = EmbeddingMatrix();
        final stored = unitVec(5);
        m.add(1, stored);
        // the same face from another copy of the photo: tiny noise
        final copy = near(stored, 50, 0.1);
        expect(m.nearest(copy)!.cosine, greaterThanOrEqualTo(duplicateCosine));
        // the same person on another day: far below the duplicate threshold
        final otherDay = near(stored, 51, 0.9);
        expect(m.nearest(otherDay)!.cosine, lessThan(duplicateCosine));
      },
    );
  });

  group('IsolateEmbeddingIndex', () {
    test('answers exactly like the in-memory one', () async {
      final isolated = await IsolateEmbeddingIndex.spawn();
      addTearDown(isolated.dispose);
      final local = InMemoryEmbeddingIndex();
      final rng = Random(4);
      final faces = [for (var i = 0; i < 60; i++) (i + 1, unitVec(200 + i))];
      await isolated.addAll(faces);
      await local.addAll(faces);
      expect(await isolated.size(), 60);

      final queries = [
        for (var i = 0; i < 12; i++)
          near(faces[rng.nextInt(60)].$2, 300 + i, 0.2),
        unitVec(999),
      ];
      final fromIsolate = await isolated.nearest(queries);
      final fromLocal = await local.nearest(queries);
      for (var i = 0; i < queries.length; i++) {
        expect(fromIsolate[i]!.id, fromLocal[i]!.id, reason: 'query $i');
        expect(fromIsolate[i]!.cosine, closeTo(fromLocal[i]!.cosine, 1e-9));
      }

      await isolated.remove([1, 2, 3]);
      await local.remove([1, 2, 3]);
      expect(await isolated.size(), 57);
      final after = await isolated.nearest([faces[0].$2]);
      expect(after.single!.id, isNot(1));
    });

    test(
      'an empty index answers null for every query and a closed one refuses work',
      () async {
        final index = await IsolateEmbeddingIndex.spawn();
        expect(await index.nearest([unitVec(1), unitVec(2)]), [null, null]);
        expect(await index.nearest(const []), isEmpty);
        await index.dispose();
        await index.dispose(); // twice is fine
        await expectLater(index.size(), throwsStateError);
      },
    );
  });
}
