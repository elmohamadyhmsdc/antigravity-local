import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The phone's private file area for face and body crops. Only *relative* paths (`faces/12.jpg`)
/// are stored in the database, so a backup restores into any install. Originals (the user's
/// photos) are never copied here - they are referenced by MediaStore asset id.
class FileStore {
  FileStore(this.root);

  final Directory root;

  static const facesFolder = 'faces';
  static const bodiesFolder = 'bodies';

  /// App start-up: `<app support dir>/crops` (private to the app, excluded from Android backups).
  static Future<FileStore> open() async {
    final base = await getApplicationSupportDirectory();
    return FileStore(Directory(p.join(base.path, 'crops')));
  }

  String faceCropPath(int faceId) => '$facesFolder/$faceId.jpg';
  String bodyCropPath(int bodyId) => '$bodiesFolder/$bodyId.jpg';

  File resolve(String relative) {
    if (relative.isEmpty ||
        relative.contains('\\') ||
        p.posix.isAbsolute(relative) ||
        relative.contains(':') ||
        p.posix.split(relative).any((s) => s == '..' || s.isEmpty)) {
      throw const FormatException('Unsafe private file path');
    }
    return File(p.joinAll([root.path, ...p.posix.split(relative)]));
  }

  /// Writes `bytes` to the relative path (creating folders) and returns the path.
  Future<String> write(String relative, Uint8List bytes) async {
    final file = resolve(relative);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return relative;
  }

  Future<String> writeFaceCrop(int faceId, Uint8List bytes) =>
      write(faceCropPath(faceId), bytes);

  Future<String> writeBodyCrop(int bodyId, Uint8List bytes) =>
      write(bodyCropPath(bodyId), bytes);

  Future<void> delete(String? relative) async {
    if (relative == null || relative.isEmpty) return;
    final file = resolve(relative);
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // a crop that cannot be removed is only wasted space
    }
  }

  Future<void> deleteAll(Iterable<String?> relatives) async {
    for (final r in relatives) {
      await delete(r);
    }
  }

  /// Every crop file as `(relative path, file)`, for backups and the storage manager.
  Future<List<(String, File)>> allFiles() async {
    if (!await root.exists()) return const [];
    final out = <(String, File)>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        out.add((
          p.posix.joinAll(p.split(p.relative(entity.path, from: root.path))),
          entity,
        ));
      }
    }
    return out;
  }

  Future<int> usedBytes() async {
    var total = 0;
    for (final (_, file) in await allFiles()) {
      total += await file.length();
    }
    return total;
  }

  /// Removes every crop (used when a backup replaces the whole library).
  Future<void> clear() async {
    if (await root.exists()) await root.delete(recursive: true);
  }
}
