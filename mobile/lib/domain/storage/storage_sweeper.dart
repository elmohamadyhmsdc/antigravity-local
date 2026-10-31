import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/db/app_database.dart';
import '../../data/files/file_store.dart';

/// Where the phone's bytes go, beyond the per-folder sizes of the private file store.
class StorageUsage {
  const StorageUsage({
    required this.folders,
    required this.databaseBytes,
    required this.tempBytes,
  });

  /// Private file store, by top-level folder (`faces`, `bodies`, `results`, `work`, ...).
  final Map<String, int> folders;

  /// The encrypted database with its `-wal` / `-shm` / `-journal` companions.
  final int databaseBytes;

  /// Everything in the temporary/cache folders (photo-picker and origin-file copies,
  /// export and backup scratch files, video-scan result downloads).
  final int tempBytes;

  int get fileStoreBytes => folders.values.fold(0, (a, b) => a + b);
  int get totalBytes => fileStoreBytes + databaseBytes + tempBytes;
}

/// Files nothing refers to any more. Nothing in here is deleted until [StorageSweeper.sweep].
class Leftovers {
  const Leftovers({
    required this.orphans,
    required this.orphanBytes,
    required this.staleTemp,
    required this.staleTempBytes,
  });

  /// Private files (relative paths) that no database row refers to.
  final List<String> orphans;
  final int orphanBytes;

  /// Top-level entries of the temporary folders that have not been touched for a while.
  final List<FileSystemEntity> staleTemp;
  final int staleTempBytes;

  int get totalBytes => orphanBytes + staleTempBytes;
  bool get isEmpty => orphans.isEmpty && staleTemp.isEmpty;

  static const none = Leftovers(
    orphans: [],
    orphanBytes: 0,
    staleTemp: [],
    staleTempBytes: 0,
  );
}

class SweepResult {
  const SweepResult({required this.removedFiles, required this.removedBytes});
  final int removedFiles;
  final int removedBytes;
}

/// Finds and removes the private files and scratch files that a deleted/failed/crashed
/// operation left behind. It only ever removes:
///  * private files that no row of any table refers to (a crop whose face is gone, a result
///    whose job was removed, a `.part` download, an export archive...), and
///  * entries of the temporary folders,
/// and only when they are older than [minAge] - a scan or job that is writing right now has
/// just touched its files, so a live operation is never raced. User results, datasets and
/// LoRAs are referenced by their rows and are therefore never swept.
class StorageSweeper {
  StorageSweeper({
    required this.db,
    required this.files,
    this.databaseFile,
    this.tempDirs = const [],
    this.minAge = const Duration(hours: 6),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final FileStore files;
  final File? databaseFile;
  final List<Directory> tempDirs;
  final Duration minAge;
  final DateTime Function() _clock;

  Future<StorageUsage> usage() async {
    final folders = <String, int>{};
    for (final (relative, file) in await files.allFiles()) {
      final folder = relative.contains('/') ? relative.split('/').first : '';
      folders[folder] = (folders[folder] ?? 0) + await _length(file);
    }
    var database = 0;
    final db = databaseFile;
    if (db != null) {
      for (final suffix in const ['', '-wal', '-shm', '-journal']) {
        database += await _length(File('${db.path}$suffix'));
      }
    }
    var temp = 0;
    for (final dir in _uniqueTempDirs()) {
      temp += await _treeBytes(dir);
    }
    return StorageUsage(
      folders: folders,
      databaseBytes: database,
      tempBytes: temp,
    );
  }

  /// Every relative private path some row still needs.
  Future<Set<String>> referencedPaths() async {
    final out = <String>{};
    Future<void> column(String sql) async {
      for (final row in await db.customSelect(sql).get()) {
        for (final value in row.data.values) {
          if (value is String && value.isNotEmpty) out.add(value);
        }
      }
    }

    await column('SELECT crop_path FROM faces WHERE crop_path IS NOT NULL');
    await column('SELECT crop_path FROM bodies WHERE crop_path IS NOT NULL');
    await column(
      'SELECT crop_path FROM character_samples WHERE crop_path IS NOT NULL',
    );
    await column('SELECT path FROM dataset_items');
    await column('SELECT path, original_path FROM results');
    await column('SELECT path FROM loras');
    // A paused/failed/running job still needs its staged inputs (it resumes from them).
    for (final row
        in await db
            .customSelect('SELECT target_path, input_files FROM jobs')
            .get()) {
      out.add(row.read<String>('target_path'));
      try {
        final inputs = jsonDecode(row.read<String>('input_files'));
        if (inputs is Map) out.addAll(inputs.values.whereType<String>());
      } on FormatException {
        // unreadable bookkeeping: keep only target_path
      }
    }
    return out;
  }

  Future<Leftovers> findLeftovers() async {
    final cutoff = _clock().subtract(minAge);
    final referenced = await referencedPaths();
    final orphans = <String>[];
    var orphanBytes = 0;
    for (final (relative, file) in await files.allFiles()) {
      if (referenced.contains(relative)) continue;
      final stat = await _stat(file);
      if (stat == null || !stat.modified.isBefore(cutoff)) continue;
      orphans.add(relative);
      orphanBytes += stat.size;
    }
    final stale = <FileSystemEntity>[];
    var staleBytes = 0;
    for (final dir in _uniqueTempDirs()) {
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(followLinks: false)) {
        final newest = await _newestModification(entity);
        if (newest == null || !newest.isBefore(cutoff)) continue;
        stale.add(entity);
        staleBytes += await _treeBytes(entity);
      }
    }
    return Leftovers(
      orphans: orphans,
      orphanBytes: orphanBytes,
      staleTemp: stale,
      staleTempBytes: staleBytes,
    );
  }

  /// Re-evaluates the leftovers (the library may have changed since the user looked) and removes them.
  Future<SweepResult> sweep() async {
    final found = await findLeftovers();
    var removed = 0;
    var bytes = 0;
    for (final relative in found.orphans) {
      final file = files.resolve(relative);
      final size = await _length(file);
      await files.delete(relative);
      if (!await file.exists()) {
        removed++;
        bytes += size;
      }
    }
    await _removeEmptyFolders(files.root);
    for (final entity in found.staleTemp) {
      final size = await _treeBytes(entity);
      final count = await _fileCount(entity);
      try {
        await entity.delete(recursive: true);
        removed += count;
        bytes += size;
      } on FileSystemException {
        // in use or already gone: it only stays as wasted space until the next sweep
      }
    }
    return SweepResult(removedFiles: removed, removedBytes: bytes);
  }

  List<Directory> _uniqueTempDirs() {
    final seen = <String>{};
    return [
      for (final dir in tempDirs)
        if (seen.add(p.normalize(p.absolute(dir.path)))) dir,
    ];
  }

  static Future<int> _length(File file) async {
    try {
      return await file.length();
    } on FileSystemException {
      return 0;
    }
  }

  static Future<({int size, DateTime modified})?> _stat(File file) async {
    try {
      final stat = await file.stat();
      if (stat.type == FileSystemEntityType.notFound) return null;
      return (size: stat.size, modified: stat.modified);
    } on FileSystemException {
      return null;
    }
  }

  static Future<int> _treeBytes(FileSystemEntity entity) async {
    try {
      if (entity is File) return await entity.length();
      if (entity is! Directory || !await entity.exists()) return 0;
      var total = 0;
      await for (final child in entity.list(
        recursive: true,
        followLinks: false,
      )) {
        if (child is File) total += await _length(child);
      }
      return total;
    } on FileSystemException {
      return 0;
    }
  }

  static Future<int> _fileCount(FileSystemEntity entity) async {
    if (entity is File) return 1;
    if (entity is! Directory) return 0;
    var count = 0;
    try {
      await for (final child in entity.list(
        recursive: true,
        followLinks: false,
      )) {
        if (child is File) count++;
      }
    } on FileSystemException {
      // vanished while counting
    }
    return count;
  }

  /// A folder is as fresh as the most recently written file inside it (an empty one, as itself).
  static Future<DateTime?> _newestModification(FileSystemEntity entity) async {
    try {
      DateTime? newest;
      if (entity is Directory) {
        await for (final child in entity.list(
          recursive: true,
          followLinks: false,
        )) {
          if (child is! File) continue;
          final modified = (await child.stat()).modified;
          if (newest == null || modified.isAfter(newest)) newest = modified;
        }
      }
      return newest ?? (await entity.stat()).modified;
    } on FileSystemException {
      return null;
    }
  }

  static Future<void> _removeEmptyFolders(Directory root) async {
    if (!await root.exists()) return;
    final folders = <Directory>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Directory) folders.add(entity);
    }
    // deepest first, so a folder emptied by its children's removal goes too
    folders.sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final folder in folders) {
      try {
        if (await folder.list().isEmpty) await folder.delete();
      } on FileSystemException {
        // not empty any more
      }
    }
  }
}
