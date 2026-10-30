// Opt-in QA entry point. Always build with -PcharacterAcceptance=true so it
// cannot open the installed app's Keystore, preferences, database or jobs.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/mobile_api.dart';
import 'package:antigravity_mobile/data/api/pinned_http.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/domain/scan/photo_result_store.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _QaApp());
}

class _QaApp extends StatefulWidget {
  const _QaApp();
  @override
  State<_QaApp> createState() => _QaAppState();
}

class _QaAppState extends State<_QaApp> {
  String _status = 'Preparing isolated character test';
  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final config =
        jsonDecode(
              utf8.decode(
                base64Decode(
                  const String.fromEnvironment('CHARACTER_QA_CONFIG'),
                ),
              ),
            )
            as Map<String, dynamic>;
    final session = ServerSession(
      serverId: 'qa',
      name: 'Isolated QA server',
      host: '127.0.0.1',
      port: config['port'] as int,
      fingerprint: config['fingerprint'] as String,
      token: config['token'] as String,
    );
    final api = HttpMobileApi(session);
    final dio = createPinnedDio(
      host: session.host,
      port: session.port,
      fingerprint: session.fingerprint,
      token: session.token,
    );
    final db = AppDatabase(NativeDatabase.memory());
    final temp = await Directory.systemTemp.createTemp('character_qa_');
    final store = PhotoResultStore(
      db: db,
      files: FileStore(temp),
      index: InMemoryEmbeddingIndex(),
    );
    final report = <String, dynamic>{
      'processed': 0,
      'detections': 0,
      'with_characters': 0,
      'errors': <String>[],
    };
    try {
      if (!(await api.capabilities()).engines.characterDetection) {
        throw StateError('Character capability is missing');
      }
      final entries = (await dio.get<List<dynamic>>('/qa/corpus')).data!;
      for (final raw in entries) {
        final entry = raw as Map<String, dynamic>;
        try {
          final bytes = await dio.get<List<int>>(
            '/qa/image/${entry['id']}',
            options: Options(responseType: ResponseType.bytes),
          );
          final response = await api.analyzeImage(
            Uint8List.fromList(bytes.data!),
            options: const AnalyzeOptions(
              detectCharacters: true,
              detectBodies: false,
              returnCrops: false,
            ),
          );
          if (response.faces.isNotEmpty || response.bodies.isNotEmpty) {
            throw StateError('Human/character identity namespaces mixed');
          }
          final id = await db
              .into(db.media)
              .insert(
                MediaCompanion.insert(
                  assetId: 'qa:${entry['id']}',
                  kind: 'photo',
                ),
              );
          final media = await (db.select(
            db.media,
          )..where((m) => m.id.equals(id))).getSingle();
          final stored = await store.store(media, response);
          final repeated = await store.store(media, response);
          if (repeated.newCharacters != 0 ||
              stored.newCharacters != response.characters.length) {
            throw StateError('Non-idempotent character import');
          }
          report['processed'] = (report['processed'] as int) + 1;
          report['detections'] =
              (report['detections'] as int) + stored.newCharacters;
          report['with_characters'] =
              (report['with_characters'] as int) +
              (stored.newCharacters > 0 ? 1 : 0);
        } catch (error) {
          (report['errors'] as List<String>).add('${entry['id']}: $error');
        }
        if (mounted) {
          setState(
            () => _status =
                '${report['processed']} / ${entries.length} images\n${report['detections']} character detections\n${(report['errors'] as List).length} errors',
          );
        }
        await dio.post('/qa/progress', data: report);
      }
      report['identity_groups'] =
          (await db.select(db.characterIdentities).get()).length;
      report['same_frame_identity_conflicts'] =
          (await db
                  .customSelect(
                    'SELECT identity_id FROM character_samples GROUP BY media_id, frame_number, identity_id HAVING COUNT(*) > 1',
                  )
                  .get())
              .length;
      report['human_faces'] = (await db.select(db.faces).get()).length;
      report['sqlcipher'] =
          (await db.customSelect('PRAGMA cipher_version').get()).isNotEmpty;
      report['completed'] = true;
      await dio.post('/qa/report', data: report);
      if (mounted) {
        setState(
          () => _status =
              'COMPLETE\n$_status\n${report['identity_groups']} separate character groups\nHuman faces: ${report['human_faces']}\nConflicts: ${report['same_frame_identity_conflicts']}\nReal gallery untouched',
        );
      }
    } catch (error) {
      report['fatal'] = '$error';
      try {
        await dio.post('/qa/report', data: report);
      } catch (_) {}
      if (mounted) setState(() => _status = 'FAILED\n$error');
    } finally {
      api.close();
      dio.close();
      await db.close();
      await temp.delete(recursive: true);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Your Gallery · isolated QA')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_status, style: const TextStyle(fontSize: 20)),
        ),
      ),
    ),
  );
}
