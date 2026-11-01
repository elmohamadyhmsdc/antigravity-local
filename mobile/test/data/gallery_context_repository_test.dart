import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/repositories/app_settings.dart';
import 'package:antigravity_mobile/data/repositories/artifact_context.dart';
import 'package:antigravity_mobile/data/repositories/library_repository.dart';
import 'package:antigravity_mobile/data/repositories/media_action_source.dart';
import 'package:antigravity_mobile/data/repositories/media_queries.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:antigravity_mobile/data/repositories/studio_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/seed.dart';

void main() {
  late AppDatabase db;
  late Directory temp;
  late FileStore files;
  late StudioRepository studio;
  late LibraryRepository library;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    temp = Directory.systemTemp.createTempSync('gallery_context_');
    files = FileStore(Directory('${temp.path}/private'));
    studio = StudioRepository(db, files);
    library = LibraryRepository(db);
  });
  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  test(
    'action resolver reads the chosen original without guessing a target',
    () async {
      final media = (await library.ensureBrowsableAssets(
        syntheticAssets(1),
      )).single;
      final device = FakeMediaLibrary();
      device.bytes[media.assetId] = tinyPng;
      final resolver = MediaActionSource(
        repository: library,
        queries: MediaQueries(db),
        library: device,
      );
      final source = await resolver.resolve(media.id);
      expect(source.media.id, media.id);
      expect(source.photoBytes, tinyPng);
      expect(source.target, isNull);
      expect(device.maxSides, [2560]);
      await expectLater(
        resolver.resolve(media.id, targetDetectionId: 999),
        throwsFormatException,
      );
      device.unreadable.add(media.assetId);
      await expectLater(resolver.resolve(media.id), throwsFormatException);
      device.unreadable.clear();
      device.failures[media.assetId] = const FileSystemException(
        'Access denied',
      );
      await expectLater(resolver.resolve(media.id), throwsFormatException);
      await expectLater(resolver.resolve(999), throwsFormatException);
      expect(await library.claimNext(), isNull);
    },
  );

  test('job context stays local and travels in a library backup', () async {
    final input = File('${temp.path}/photo.jpg');
    await input.writeAsBytes(tinyPng);
    final id = await studio.enqueue(
      serverId: 'test-server',
      type: 'reface',
      params: const {'quality': 'balanced'},
      target: input,
      video: false,
      context: const ArtifactContext(
        mediaId: 7,
        assetId: 'original-7',
        targetPersonId: 3,
        modelId: 'model-1',
      ),
    );
    final request = jsonDecode((await studio.job(id))!.requestJson) as Map;
    expect(
      request.keys,
      unorderedEquals(['client_job_id', 'type', 'inputs', 'params']),
    );
    expect((await studio.contextFor(id))!.mediaId, 7);
    final settings = AppSettings(db);
    final backup = await settings.rawBackedUp();
    expect(backup, contains('$artifactContextPrefix$id'));
    expect(
      ArtifactContext.decode(backup['$artifactContextPrefix$id'])!.assetId,
      'original-7',
    );
    await (db.delete(db.jobs)..where((job) => job.id.equals(id))).go();
    expect(
      (await studio.contextFor(id))!.modelId,
      'model-1',
      reason: 'result lineage outlives removable job history',
    );
    expect(await studio.contextFor('legacy-result'), isNull);
    expect(ArtifactContext.decode('invalid'), isNull);
  });

  test(
    'related results react to explicit source and reference context only',
    () async {
      for (final entry in [('source', 1), ('reference', 2), ('legacy', 3)]) {
        await db
            .into(db.results)
            .insert(
              ResultsCompanion.insert(
                id: entry.$1,
                type: 'lora_generate',
                path: '${entry.$1}.png',
                originalPath: 'a-shared-name-is-not-proof.png',
                mime: 'image/png',
                sizeBytes: 10,
                sha256: 'hash',
                createdAt: entry.$2,
              ),
            );
      }
      final stream = StreamIterator(studio.watchResultsForMedia(7));
      expect(await stream.moveNext(), isTrue);
      expect(
        stream.current,
        isEmpty,
        reason: 'no invented links for old results',
      );
      await db.transaction(() async {
        await db
            .into(db.settings)
            .insert(
              SettingsCompanion.insert(
                key: '${artifactContextPrefix}source',
                value: jsonEncode(const ArtifactContext(mediaId: 7).toJson()),
              ),
            );
        await db
            .into(db.settings)
            .insert(
              SettingsCompanion.insert(
                key: '${artifactContextPrefix}reference',
                value: jsonEncode(
                  const ArtifactContext(referenceMediaId: 7).toJson(),
                ),
              ),
            );
      });
      expect(
        await stream.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(stream.current.map((result) => result.id), [
        'reference',
        'source',
      ]);
      await stream.cancel();
    },
  );

  test(
    'merging keeps trained models, datasets, results, jobs and marks',
    () async {
      final source = await seedPerson(db, name: 'Source');
      final target = await seedPerson(db, name: 'Survivor');
      await db
          .into(db.loras)
          .insert(
            LorasCompanion.insert(
              id: 'artifact',
              path: 'model.safetensors',
              triggerWord: 'portrait',
              personId: Value(source),
              createdAt: 1,
            ),
          );
      await db
          .into(db.datasets)
          .insert(
            DatasetsCompanion.insert(
              id: 'dataset',
              triggerWord: 'portrait',
              personId: Value(source),
              createdAt: 1,
            ),
          );
      await db
          .into(db.results)
          .insert(
            ResultsCompanion.insert(
              id: 'artifact',
              type: 'lora_train',
              path: 'model.safetensors',
              originalPath: 'private-input.jpg',
              mime: 'application/octet-stream',
              sizeBytes: 4,
              sha256: 'hash',
              personId: Value(source),
              createdAt: 1,
            ),
          );
      await db
          .into(db.jobs)
          .insert(
            JobsCompanion.insert(
              id: 'job',
              serverId: 'server',
              type: 'lora_train',
              requestJson: '{}',
              targetPath: 'input',
              targetSha: 'hash',
              targetSize: 4,
              personId: Value(source),
              status: 'paused',
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      await db
          .into(db.bodyMarks)
          .insert(
            BodyMarksCompanion.insert(
              personId: source,
              segment: 'r_forearm',
              anchor: '{}',
              patchPath: 'marks/keep.png',
              createdAt: 1,
            ),
          );
      await db
          .into(db.settings)
          .insert(
            SettingsCompanion.insert(
              key: '${artifactContextPrefix}artifact',
              value: jsonEncode(
                ArtifactContext(
                  personId: source,
                  targetPersonId: source,
                ).toJson(),
              ),
            ),
          );
      final people = PeopleRepository(
        db,
        files,
        index: InMemoryEmbeddingIndex(),
      );
      await people.mergePeople(sourceId: source, targetId: target);
      expect(await people.person(source), isNull);
      expect((await db.select(db.loras).getSingle()).personId, target);
      expect((await db.select(db.datasets).getSingle()).personId, target);
      expect((await db.select(db.results).getSingle()).personId, target);
      expect((await db.select(db.jobs).getSingle()).personId, target);
      expect((await db.select(db.bodyMarks).getSingle()).personId, target);
      final context = (await studio.contextFor('artifact'))!;
      expect((context.personId, context.targetPersonId), (target, target));
      expect(
        await studio.deletionItems(await db.select(db.results).getSingle()),
        contains('Trained LoRA: portrait'),
      );
    },
  );
}
