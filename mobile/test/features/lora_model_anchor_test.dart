import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/api/dtos/system.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/repositories/artifact_context.dart';
import 'package:antigravity_mobile/features/lora/lora_screens.dart';
import 'package:antigravity_mobile/studio_providers.dart';
import 'package:antigravity_mobile/domain/jobs/job_tracker.dart';
import 'package:antigravity_mobile/domain/scan/scan_state.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';
import '../support/seed.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';

void main() {
  appTest(
    'character generation starts with an illustrated fully clothed prompt',
    (tester, env) async {
      await env.db
          .into(env.db.loras)
          .insert(
            LorasCompanion.insert(
              id: 'hero-model',
              path: 'loras/hero.safetensors',
              triggerWord: 'skshero',
              createdAt: 1,
            ),
          );
      await env.db.putSetting(
        '${artifactContextPrefix}hero-model',
        jsonEncode(
          const ArtifactContext(
            identityModelId: characterEmbeddingModelId,
          ).toJson(),
        ),
      );
      await tester.runAsync(
        () => env.files.write('loras/hero.safetensors', tinyPng),
      );
      await env.pump(
        tester,
        extra: [
          initialLocationProvider.overrideWithValue(
            '/lora/generate?id=hero-model',
          ),
        ],
        settle: false,
      );
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      final prompt = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller?.text ?? '')
          .firstWhere((text) => text.contains('{trigger}'));
      expect(prompt, contains('Illustrated portrait'));
      expect(prompt, contains('fully clothed'));
      expect(prompt, isNot(contains('photorealistic')));
    },
    session: testSession,
  );
  for (final supported in [false, true]) {
    appTest(
      'character dataset ${supported ? 'queues CCIP on a capable PC' : 'blocks an older PC'}',
      (tester, env) async {
        final person = await seedPerson(env.db, name: 'Hero');
        await (env.db.update(env.db.persons)..where((p) => p.id.equals(person)))
            .write(const PersonsCompanion(kind: Value('character')));
        final face = await seedFace(
          env.db,
          personId: person,
          embedding: Float32List(768)..[5] = 1,
        );
        await (env.db.update(
          env.db.faces,
        )..where((f) => f.id.equals(face))).write(
          const FacesCompanion(
            kind: Value('character'),
            modelId: Value(characterEmbeddingModelId),
          ),
        );
        if (supported) {
          final json = fixture('Capabilities.idle');
          json['operations'] = [
            {
              'operation': 'dataset_build',
              'kind': 'character',
              'media_types': ['photo', 'video'],
              'available': true,
              'engine': 'ccip',
              'identity_models': [characterEmbeddingModelId],
            },
          ];
          env.api.capabilities_ = Capabilities.fromJson(json);
        }
        final files = <File>[];
        await tester.runAsync(() async {
          for (var i = 0; i < 5; i++) {
            final file = File('${env.tmp.path}/photo$i.jpg');
            await file.writeAsBytes(tinyPng);
            files.add(file);
          }
        });
        await env.pump(
          tester,
          extra: [
            initialLocationProvider.overrideWithValue(
              '/lora/build?person=$person&manual=true',
            ),
            loraPhotosPickerProvider.overrideWithValue(() async => files),
            jobTrackerProvider.overrideWith((ref) {
              final tracker = JobTracker(
                repository: ref.read(studioRepositoryProvider),
                api: () => null,
                keepAlive: const NoKeepAlive(),
              );
              ref.onDispose(tracker.dispose);
              return tracker;
            }),
          ],
        );
        await tester.tap(find.byKey(const Key('dataset-photos')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('dataset-submit')));
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        final jobs = await env.db.select(env.db.jobs).get();
        if (!supported) {
          expect(jobs, isEmpty);
          expect(find.textContaining('Update the PC server'), findsOneWidget);
        } else {
          final request =
              jsonDecode(jobs.single.requestJson) as Map<String, dynamic>;
          final params = request['params'] as Map<String, dynamic>;
          expect(params['identity_model_id'], characterEmbeddingModelId);
          expect(
            decodeVector(params['anchor_embedding'] as String, 768)[5],
            closeTo(1, .00001),
          );
        }
      },
      session: testSession,
    );
  }
  appTest(
    'dataset anchor keeps CCIP and ArcFace separate and preserves dimensions',
    (tester, env) async {
      final human = await seedFace(
        env.db,
        embedding: Float32List(512)..[0] = 1,
      );
      final character = await seedFace(
        env.db,
        embedding: Float32List(768)..[1] = 1,
      );
      await (env.db.update(
        env.db.faces,
      )..where((f) => f.id.equals(character))).write(
        const FacesCompanion(modelId: Value(characterEmbeddingModelId)),
      );
      final faces = await env.db.select(env.db.faces).get();
      final characterVector = decodeVector(
        datasetIdentityAnchor(faces, characterEmbeddingModelId),
        768,
      );
      final humanVector = decodeVector(
        datasetIdentityAnchor(faces, 'buffalo_l@1'),
        512,
      );
      expect(characterVector[1], closeTo(1, .00001));
      expect(humanVector[0], closeTo(1, .00001));
      expect(
        () => datasetIdentityAnchor(faces, 'unknown'),
        throwsFormatException,
      );
      await (env.db.update(
        env.db.faces,
      )..where((f) => f.id.equals(character))).write(
        FacesCompanion(embedding: Value(embeddingToBlob(Float32List(512)))),
      );
      final invalid = await env.db.select(env.db.faces).get();
      expect(
        () => datasetIdentityAnchor(invalid, characterEmbeddingModelId),
        throwsFormatException,
      );
      expect(human, isPositive);
    },
  );
}
