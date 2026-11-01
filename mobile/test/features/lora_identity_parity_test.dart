import 'dart:convert';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/api/dtos/system.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/repositories/artifact_context.dart';
import 'package:antigravity_mobile/data/repositories/lora_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

DetectedCharacter character(int coordinate) => DetectedCharacter(
  bbox: const BBox(x: 10, y: 10, w: 40, h: 60),
  score: .95,
  descriptor: const [],
  face: CharacterFace(
    bbox: const BBox(x: 15, y: 15, w: 20, h: 20),
    score: .95,
    embedding: Float32List(768)..[coordinate] = 1,
  ),
);

Future<(LoraRow, int)> prepare(TestEnv env, {bool capability = true}) async {
  final person = await seedPerson(env.db, name: 'Hero');
  await (env.db.update(env.db.persons)..where((p) => p.id.equals(person)))
      .write(const PersonsCompanion(kind: Value('character')));
  final face = await seedFace(
    env.db,
    personId: person,
    embedding: Float32List(768)..[2] = 1,
  );
  await (env.db.update(env.db.faces)..where((f) => f.id.equals(face))).write(
    const FacesCompanion(
      kind: Value('character'),
      modelId: Value(characterEmbeddingModelId),
    ),
  );
  await env.db
      .into(env.db.loras)
      .insert(
        LorasCompanion.insert(
          id: 'model-a',
          personId: Value(person),
          path: 'lora/model.safetensors',
          triggerWord: 'skshero',
          createdAt: 1,
        ),
      );
  final lora = (await env.db.select(env.db.loras).get()).single;
  if (capability) {
    final data = fixture('Capabilities.idle');
    data['operations'] = [
      {
        'operation': 'analyze',
        'kind': 'character',
        'media_types': ['photo'],
        'available': true,
        'engine': 'ccip',
        'identity_models': [characterEmbeddingModelId],
      },
    ];
    env.api.capabilities_ = Capabilities.fromJson(data);
  }
  return (lora, person);
}

Future<void> portrait(
  TestEnv env,
  String id,
  int person, {
  String? model,
}) async {
  final path = 'results/$id/image.png';
  await env.files.write(path, Uint8List.fromList([1, 2, 3]));
  await env.db
      .into(env.db.results)
      .insert(
        ResultsCompanion.insert(
          id: id,
          type: 'generate_lora_images',
          personId: Value(person),
          path: path,
          originalPath: path,
          mime: 'image/png',
          sizeBytes: 3,
          sha256: 'a' * 64,
          createdAt: 1,
        ),
      );
  if (model != null) {
    await env.db.putSetting(
      '$artifactContextPrefix$id',
      jsonEncode(ArtifactContext(modelId: model).toJson()),
    );
  }
}

AnalyzeImageResponse response(List<DetectedCharacter> characters) =>
    AnalyzeImageResponse(
      modelId: 'buffalo_l@1',
      imageW: 100,
      imageH: 100,
      faces: const [],
      bodies: const [],
      pairs: const [],
      characters: characters,
    );

Future<Object?> failure(WidgetTester tester, TestEnv env, LoraRow model) =>
    tester.runAsync(() async {
      try {
        await LoraRepository(env.db, env.files).buildIdentity(model, env.api);
        return 'unexpected success';
      } catch (error) {
        return error;
      }
    });

void main() {
  appTest(
    'human identity keeps the 512-dimensional path and verified model link',
    (tester, env) async {
      final person = await seedPerson(env.db, name: 'Alice');
      await seedFace(
        env.db,
        personId: person,
        embedding: Float32List(512)..[1] = 1,
      );
      await env.db
          .into(env.db.loras)
          .insert(
            LorasCompanion.insert(
              id: 'human-model',
              personId: Value(person),
              path: 'lora/human.safetensors',
              triggerWord: 'sksalice',
              createdAt: 1,
            ),
          );
      final model = (await env.db.select(env.db.loras).get()).single;
      await tester.runAsync(
        () => portrait(env, 'human', person, model: 'human-model'),
      );
      env.api.analyzeResult = AnalyzeImageResponse(
        modelId: 'buffalo_l@1',
        imageW: 100,
        imageH: 100,
        faces: [
          DetectedFace(
            bbox: const BBox(x: 10, y: 10, w: 20, h: 20),
            kps: const [],
            detScore: 1,
            embedding: Float32List(512)..[1] = 1,
            quality: const FaceQuality(
              score: 1,
              version: 1,
              parts: {},
              detScore: 1,
              facePx: 100,
              sharpness: 1,
              embeddingNorm: 1,
              pose: null,
            ),
            passesGate: true,
          ),
        ],
        bodies: const [],
        pairs: const [],
      );
      final count = await tester.runAsync(
        () => LoraRepository(env.db, env.files).buildIdentity(model, env.api),
      );
      expect(count, 1);
      expect(env.api.analyzeOptions.single.detectCharacters, isFalse);
      final saved =
          jsonDecode(
                (await env.db.select(env.db.loras).get()).single.identityJson!,
              )
              as Map<String, dynamic>;
      expect(saved['model_id'], 'buffalo_l@1');
      expect(
        decodeVector(
          (saved['faces'] as List).single['embedding'] as String,
          512,
        ),
        hasLength(512),
      );
    },
  );
  appTest(
    'CCIP identity uses only portraits explicitly linked to the selected model',
    (tester, env) async {
      final (model, person) = await prepare(env);
      await tester.runAsync(() async {
        await portrait(env, 'yes', person, model: 'model-a');
        await portrait(env, 'other', person, model: 'model-b');
        await portrait(env, 'legacy', person);
      });
      env.api.analyzeResult = response([character(2)]);
      final count = await tester.runAsync(
        () => LoraRepository(env.db, env.files).buildIdentity(model, env.api),
      );
      expect(count, 1);
      expect(env.api.analyzeCalls, hasLength(1));
      expect(env.api.analyzeOptions.single.detectCharacters, isTrue);
      expect(env.api.analyzeOptions.single.forceKind, 'character');
      expect(env.api.analyzeOptions.single.facelessCharacters, isFalse);
      final stored = (await env.db.select(env.db.loras).get()).single;
      final identity = jsonDecode(stored.identityJson!) as Map<String, dynamic>;
      expect(identity['model_id'], characterEmbeddingModelId);
      final sample = (identity['faces'] as List).single as Map<String, dynamic>;
      expect(
        decodeVector(sample['embedding'] as String, 768)[2],
        closeTo(1, .00001),
      );
    },
  );

  appTest(
    'ambiguous or unmatched character portraits do not replace an identity',
    (tester, env) async {
      final (model, person) = await prepare(env);
      await tester.runAsync(
        () => portrait(env, 'linked', person, model: 'model-a'),
      );
      for (final characters in [
        [character(2), character(2)],
        [character(3)],
      ]) {
        env.api.analyzeResult = response(characters);
        expect(await failure(tester, env, model), isA<FormatException>());
      }
      expect(
        (await env.db.select(env.db.loras).get()).single.identityJson,
        isNull,
      );
    },
  );

  appTest(
    'unknown older PC and unlinked legacy results are refused explicitly',
    (tester, env) async {
      final (model, person) = await prepare(env, capability: false);
      await tester.runAsync(() => portrait(env, 'legacy', person));
      expect(
        await failure(tester, env, model),
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Update the PC server'),
        ),
      );
      final data = fixture('Capabilities.idle');
      data['operations'] = [
        {
          'operation': 'analyze',
          'kind': 'character',
          'media_types': ['photo'],
          'available': true,
          'engine': 'ccip',
          'identity_models': [characterEmbeddingModelId],
        },
      ];
      env.api.capabilities_ = Capabilities.fromJson(data);
      expect(
        await failure(tester, env, model),
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('verified model link'),
        ),
      );
      expect(env.api.analyzeCalls, isEmpty);
    },
  );
}
