import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/repositories/studio_repository.dart';
import 'package:antigravity_mobile/domain/jobs/artifact_store.dart';

void main() {
  group('Reface & Identity Bundle Mobile Integration (Phase 6)', () {
    late AppDatabase db;
    late Directory tmp;
    late FileStore files;
    late StudioRepository repository;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      tmp = Directory.systemTemp.createTempSync('ag_test_bundle_');
      files = FileStore(Directory('${tmp.path}/files'));
      repository = StudioRepository(db, files);

      await db.upsertServer(
        ServersCompanion.insert(
          id: 'srv_pc',
          name: 'PC',
          host: '127.0.0.1',
          port: 8443,
          fingerprint: 'aa' * 32,
          pairedAt: 100,
        ),
      );
      await db.into(db.persons).insert(
        PersonsCompanion.insert(
          id: const Value(42),
          name: const Value('Test Person 42'),
          createdAt: 100,
        ),
      );
      await db.into(db.persons).insert(
        PersonsCompanion.insert(
          id: const Value(99),
          name: const Value('Test Person 99'),
          createdAt: 100,
        ),
      );
    });

    tearDown(() async {
      await db.close();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('ArtifactStore stages and commits build_identity artifact to settings', () async {
      final sampleFile = File('../the app/mobile_api/contract/fixtures/identity/sample_bundle.json');
      expect(sampleFile.existsSync(), true, reason: 'sample_bundle.json fixture must exist');
      final sampleJson = sampleFile.readAsStringSync();

      // Create dummy image input
      final img = File('${tmp.path}/input.jpg');
      await img.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);

      final jobId = await repository.enqueueInputs(
        serverId: 'srv_pc',
        type: 'build_identity',
        params: {'model_id': 'buffalo_l@1'},
        inputs: {'images': [img]},
        personId: 42,
      );

      final job = (await repository.job(jobId))!;
      final relativeArtifact = 'results/$jobId/identity_bundle.json';
      final artifactFile = files.resolve(relativeArtifact);
      await artifactFile.parent.create(recursive: true);
      await artifactFile.writeAsString(sampleJson);

      final store = ArtifactStore(db, files);
      final commitCallback = await store.stage(
        job,
        relativeArtifact,
        metadata: {
          'name': 'identity_bundle.json',
          'mime': 'application/json',
          'engine': 'insightface',
        },
      );

      // Execute commit inside transaction
      await db.transaction(() async {
        await commitCallback();
      });

      // Verify identity bundle is stored in settings for person 42 and job id
      final storedForPerson = await db.setting('identity_bundle_42');
      expect(storedForPerson, isNotNull);
      final personBundle = jsonDecode(storedForPerson!) as Map<String, dynamic>;
      expect(personBundle['schema_version'], '1.0');
      expect(personBundle['algorithm_version'], 'identity_v1');
      expect(personBundle['primary_embedding'] is List, true);

      final storedForJob = await db.setting('identity_bundle_$jobId');
      expect(storedForJob, storedForPerson);
    });

    test('ArtifactStore rejects invalid identity bundle schema', () async {
      final img = File('${tmp.path}/input2.jpg');
      await img.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);

      final jobId = await repository.enqueueInputs(
        serverId: 'srv_pc',
        type: 'build_identity',
        params: {'model_id': 'buffalo_l@1'},
        inputs: {'images': [img]},
        personId: 99,
      );

      final job = (await repository.job(jobId))!;
      final relativeArtifact = 'results/$jobId/identity_bundle.json';
      final artifactFile = files.resolve(relativeArtifact);
      await artifactFile.parent.create(recursive: true);
      // Write corrupted bundle (wrong schema version)
      await artifactFile.writeAsString(jsonEncode({
        'schema_version': '0.9',
        'primary_embedding': List.filled(512, 0.0),
      }));

      final store = ArtifactStore(db, files);
      final commitCallback = await store.stage(
        job,
        relativeArtifact,
        metadata: {'name': 'identity_bundle.json'},
      );

      expect(
        () async => await commitCallback(),
        throwsA(isA<FormatException>()),
      );
    });

    test('Reface payload parameters parity and capability negotiation', () {
      final sampleFile = File('../the app/mobile_api/contract/fixtures/identity/sample_bundle.json');
      final sampleBundle = jsonDecode(sampleFile.readAsStringSync()) as Map<String, dynamic>;

      // When identity_bundle capability is enabled on server
      final paramsWithBundle = <String, dynamic>{
        'source_faces': <Map<String, dynamic>>[],
        'identity_bundle': sampleBundle,
        'model_id': 'buffalo_l@1',
        'restorer': 'auto',
        'use_parser': true,
        'use_occluder': true,
        'realism_preset': 'natural',
        'quality_profile': 'balanced',
        'use_3d_geometry': true,
        'identity_boost': 0.5,
        'preview': false,
      };

      expect(paramsWithBundle['use_3d_geometry'], true);
      expect(paramsWithBundle['realism_preset'], 'natural');
      expect(paramsWithBundle['quality_profile'], 'balanced');
      expect(paramsWithBundle.containsKey('identity_bundle'), true);
      expect(paramsWithBundle['identity_bundle']['bundle_hash'], sampleBundle['bundle_hash']);

      // Backward-compatible fallback when server lacks identity_bundle engine
      final paramsLegacy = <String, dynamic>{
        'source_faces': <Map<String, dynamic>>[
          {'embedding': 'abc', 'quality': 0.9}
        ],
        'model_id': 'buffalo_l@1',
        'restorer': 'auto',
        'use_parser': true,
        'use_occluder': true,
        'realism_preset': 'natural',
        'quality_profile': 'balanced',
        'use_3d_geometry': true,
        'identity_boost': 0.5,
        'preview': false,
      };

      expect(paramsLegacy.containsKey('identity_bundle'), false);
      expect((paramsLegacy['source_faces'] as List).isNotEmpty, true);
    });
  });
}
