import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../data/db/app_database.dart';
import '../../data/files/file_store.dart';
import '../../data/repositories/app_settings.dart';

/// The phone holds the ONLY copy of the user's library, so a backup must be able to rebuild it
/// exactly: every person, face, body, photo record, rejection, detection and crop.
///
/// An `.agbackup` file is a plain zip:
///   manifest.json                 format, versions, row counts, sha-256 of every db file
///   db/`table`.`n`.jsonl          one JSON object per row (blobs as {"$b64": ...}), 2000 rows per file
///   crops/faces/`id`.jpg, crops/bodies/`id`.jpg
///
/// It is NOT encrypted (the database on the phone is): keep it somewhere you trust - see the Backup
/// screen. It never contains the PC pairing, tokens, results or anything of the PC.
const backupFormat = 'agbackup';
const backupFormatVersion = 1;
const backupExtension = 'agbackup';

class BackupTable {
  const BackupTable(this.name);
  final String name;
}

/// Insertion order = foreign-key order (parents first). Deleting goes the other way round.
const backupTables = [
  BackupTable('persons'),
  BackupTable('media'),
  BackupTable('faces'),
  BackupTable('bodies'),
  BackupTable('face_rejections'),
  BackupTable('body_rejections'),
  BackupTable('person_distinct'),
  BackupTable('media_detections'),
  BackupTable('review_matches'),
  BackupTable('review_groups'),
  BackupTable('review_duplicates'),
  BackupTable('review_body_links'),
  BackupTable('results'),
  BackupTable('datasets'),
  BackupTable('dataset_items'),
  BackupTable('loras'),
];

const _rowsPerFile = 2000;
const _blobKey = r'$b64';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BackupInfo {
  const BackupInfo({
    required this.createdAt,
    required this.schemaVersion,
    required this.rows,
    required this.cropCount,
  });

  final DateTime createdAt;
  final int schemaVersion;
  final Map<String, int> rows;
  final int cropCount;

  int get people => rows['persons'] ?? 0;
  int get faces => rows['faces'] ?? 0;
  int get photos => rows['media'] ?? 0;
}

class BackupProgress {
  const BackupProgress(this.stage, this.done, this.total);

  final String stage; // database | crops | restoring | finishing
  final int done;
  final int total;
}

class BackupService {
  BackupService({
    required this._db,
    required this._files,
    required this._settings,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final FileStore _files;
  final AppSettings _settings;
  final DateTime Function() _clock;

  // ---- export ---------------------------------------------------------------------

  /// Writes `<dir>/antigravity-<timestamp>.agbackup` and returns it.
  Future<File> export(
    Directory dir, {
    void Function(BackupProgress)? onProgress,
  }) async {
    await dir.create(recursive: true);
    final now = _clock();
    final stamp =
        '${now.year}${_two(now.month)}${_two(now.day)}-${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
    final out = File(p.join(dir.path, 'antigravity-$stamp.$backupExtension'));
    if (await out.exists()) await out.delete();

    final encoder = ZipFileEncoder()..create(out.path);
    try {
      final rows = <String, int>{};
      final hashes = <String, String>{};
      var rowsDone = 0;
      final rowsTotal = await _totalRows();
      for (final table in backupTables) {
        var count = 0;
        var file = 0;
        var lastRowId = 0;
        while (true) {
          final page = await _db
              .customSelect(
                'SELECT rowid AS _rowid_, * FROM ${table.name} WHERE rowid > ? ORDER BY rowid LIMIT ?',
                variables: [
                  Variable.withInt(lastRowId),
                  Variable.withInt(_rowsPerFile),
                ],
              )
              .get();
          if (page.isEmpty) break;
          final lines = StringBuffer();
          for (final row in page) {
            final data = Map<String, Object?>.of(row.data)..remove('_rowid_');
            lines.writeln(
              jsonEncode({
                for (final e in data.entries) e.key: _encodeValue(e.value),
              }),
            );
          }
          lastRowId = page.last.read<int>('_rowid_');
          final name =
              'db/${table.name}.${(file++).toString().padLeft(4, '0')}.jsonl';
          final bytes = utf8.encode(lines.toString());
          hashes[name] = sha256.convert(bytes).toString();
          encoder.addArchiveFile(ArchiveFile.bytes(name, bytes));
          count += page.length;
          rowsDone += page.length;
          onProgress?.call(BackupProgress('database', rowsDone, rowsTotal));
        }
        rows[table.name] = count;
      }

      final crops = (await _files.allFiles())
          .where(
            (entry) =>
                !entry.$1.startsWith('work/') && !entry.$1.endsWith('.part'),
          )
          .toList();
      var cropsDone = 0;
      for (final (relative, file) in crops) {
        await encoder.addFile(
          file,
          'crops/$relative',
          0,
        ); // JPEGs: store, do not deflate
        onProgress?.call(BackupProgress('crops', ++cropsDone, crops.length));
      }

      final manifest = {
        'format': backupFormat,
        'format_version': backupFormatVersion,
        'created_by': 'antigravity-mobile',
        'created_at': now.toUtc().toIso8601String(),
        'schema_version': AppDatabase.currentSchemaVersion,
        'rows': rows,
        'crops': crops.length,
        'db_files': hashes,
        'settings': await _settings.rawBackedUp(),
      };
      encoder.addArchiveFile(
        ArchiveFile.string('manifest.json', jsonEncode(manifest)),
      );
      await encoder.close();
    } catch (_) {
      try {
        await encoder.close();
      } on Object {
        // already failed
      }
      if (await out.exists()) await out.delete();
      rethrow;
    }
    await _settings.setLastBackupAt(now);
    return out;
  }

  Future<int> _totalRows() async {
    var total = 0;
    for (final t in backupTables) {
      total +=
          (await _db
                  .customSelect('SELECT COUNT(*) AS n FROM ${t.name}')
                  .getSingle())
              .read<int>('n');
    }
    return total;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static Object? _encodeValue(Object? v) {
    if (v is Uint8List) return {_blobKey: base64Encode(v)};
    if (v is List<int>) return {_blobKey: base64Encode(v)};
    if (v is BigInt) return v.toInt();
    return v;
  }

  // ---- inspect / restore ----------------------------------------------------------

  Future<BackupInfo> inspect(File file) async {
    final input = InputFileStream(file.path);
    try {
      return _readManifest(ZipDecoder().decodeStream(input));
    } on BackupException {
      rethrow;
    } on Object catch (e) {
      throw BackupException('This file is not a readable backup ($e).');
    } finally {
      await input.close();
    }
  }

  BackupInfo _readManifest(Archive archive) {
    final entry = archive.findFile('manifest.json');
    if (entry == null) {
      throw BackupException(
        'This is not an Antigravity backup (manifest.json is missing).',
      );
    }
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(utf8.decode(entry.content)) as Map<String, dynamic>;
    } on Object {
      throw BackupException(
        'The backup is damaged (its manifest cannot be read).',
      );
    }
    if (m['format'] != backupFormat) {
      throw BackupException('This is not an Antigravity backup.');
    }
    final version = m['format_version'];
    if (version is! int || version > backupFormatVersion) {
      throw BackupException(
        'This backup was made by a newer version of the app. Update the app first.',
      );
    }
    final schema = m['schema_version'];
    if (schema is! int || schema > AppDatabase.currentSchemaVersion) {
      throw BackupException(
        'This backup was made by a newer version of the app. Update the app first.',
      );
    }
    return BackupInfo(
      createdAt:
          DateTime.tryParse('${m['created_at']}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      schemaVersion: schema,
      rows: {
        for (final e in (m['rows'] as Map<String, dynamic>).entries)
          e.key: e.value as int,
      },
      cropCount: (m['crops'] as int?) ?? 0,
    );
  }

  /// Replaces the whole library with the backup's. All-or-nothing for the database (one
  /// transaction: if anything is wrong the current library is untouched); crops are extracted next
  /// to the live ones first and swapped in after the database commit.
  Future<BackupInfo> restore(
    File file, {
    void Function(BackupProgress)? onProgress,
  }) async {
    final input = InputFileStream(file.path);
    final staging = Directory('${_files.root.path}.restoring');
    try {
      final archive = ZipDecoder().decodeStream(input);
      final info = _readManifest(archive);
      final manifest =
          jsonDecode(utf8.decode(archive.findFile('manifest.json')!.content))
              as Map<String, dynamic>;
      final hashes =
          (manifest['db_files'] as Map<String, dynamic>?) ?? const {};

      // crops first, into a staging folder
      if (await staging.exists()) await staging.delete(recursive: true);
      final cropEntries = [
        for (final f in archive.files)
          if (f.isFile && f.name.startsWith('crops/')) f,
      ];
      var cropsDone = 0;
      for (final entry in cropEntries) {
        final relative = entry.name.substring('crops/'.length);
        if (relative.contains('..')) {
          throw BackupException('The backup is damaged (unsafe file name).');
        }
        final target = FileStore(staging).resolve(relative);
        await target.parent.create(recursive: true);
        await target.writeAsBytes(entry.content, flush: true);
        onProgress?.call(
          BackupProgress('crops', ++cropsDone, cropEntries.length),
        );
      }

      // database: one transaction
      final byTable = <String, List<ArchiveFile>>{};
      for (final f in archive.files) {
        if (f.isFile && f.name.startsWith('db/') && f.name.endsWith('.jsonl')) {
          final table = p.posix.basename(f.name).split('.').first;
          byTable.putIfAbsent(table, () => []).add(f);
        }
      }
      for (final list in byTable.values) {
        list.sort((a, b) => a.name.compareTo(b.name));
      }
      final total = info.rows.values.fold<int>(0, (a, b) => a + b);
      var done = 0;
      await _db.transaction(() async {
        // PC job IDs never travel. A restored output remains a private local result.
        await _db.delete(_db.jobs).go();
        for (final table in backupTables.reversed) {
          await _db.customStatement('DELETE FROM ${table.name}');
        }
        for (final table in backupTables) {
          var inserted = 0;
          for (final part in byTable[table.name] ?? const <ArchiveFile>[]) {
            final bytes = part.content;
            final expected = hashes[part.name];
            if (expected != null &&
                sha256.convert(bytes).toString() != expected) {
              throw BackupException(
                'The backup is damaged (${part.name} does not match its checksum).',
              );
            }
            for (final line in const LineSplitter().convert(
              utf8.decode(bytes),
            )) {
              if (line.trim().isEmpty) continue;
              await _insertRow(
                table.name,
                jsonDecode(line) as Map<String, dynamic>,
              );
              inserted++;
              done++;
              if (done % 500 == 0) {
                onProgress?.call(BackupProgress('restoring', done, total));
              }
            }
          }
          final expectedRows = info.rows[table.name] ?? 0;
          if (inserted != expectedRows) {
            throw BackupException(
              'The backup is incomplete: ${table.name} has $inserted of $expectedRows rows.',
            );
          }
        }
        final settings = manifest['settings'];
        if (settings is Map<String, dynamic>) {
          await _settings.putRaw({
            for (final e in settings.entries)
              if (SettingKeys.backedUp.contains(e.key)) e.key: '${e.value}',
          });
        }
        // A restored backup may have an earlier video checkpoint than the current
        // phone. Reusing that phone's newer PC job could skip uncommitted samples.
        await (_db.delete(
          _db.settings,
        )..where((s) => s.key.like('video.job.%'))).go();
        await _settings.setScanActive(false);
      });

      // raw statements do not wake drift's streams: tell every screen that watches the library
      _db.markTablesUpdated(_db.allTables);

      // database committed: swap the crops in
      onProgress?.call(const BackupProgress('finishing', 0, 0));
      if (await _files.root.exists()) await _files.root.delete(recursive: true);
      if (await staging.exists()) {
        await staging.rename(_files.root.path);
      } else {
        await _files.root.create(recursive: true);
      }
      return info;
    } on BackupException {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    } on Object catch (e) {
      if (await staging.exists()) await staging.delete(recursive: true);
      throw BackupException('The backup could not be restored: $e');
    } finally {
      await input.close();
    }
  }

  Future<void> _insertRow(String table, Map<String, dynamic> row) {
    final columns = row.keys.toList();
    return _db.customStatement(
      'INSERT INTO $table (${columns.map((c) => '"$c"').join(', ')}) VALUES (${List.filled(columns.length, '?').join(', ')})',
      [for (final c in columns) _decodeValue(row[c])],
    );
  }

  static Object? _decodeValue(Object? v) {
    if (v is Map && v.containsKey(_blobKey)) {
      return base64Decode(v[_blobKey] as String);
    }
    return v;
  }
}
