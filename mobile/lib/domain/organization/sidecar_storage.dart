import 'dart:convert';
import 'dart:io';

import 'sidecar_metadata.dart';

class SidecarStorage {
  const SidecarStorage();

  static String sidecarPathFor(String mediaPath) => '$mediaPath.json';

  Future<File> writeSidecar(String mediaPath, SidecarMetadata metadata) async {
    final path = sidecarPathFor(mediaPath);
    final file = File(path);
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final content = const JsonEncoder.withIndent('  ').convert(metadata.toJson());
    return file.writeAsString(content, flush: true);
  }

  Future<SidecarMetadata?> readSidecar(String mediaPath) async {
    final path = sidecarPathFor(mediaPath);
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      final text = await file.readAsString();
      final map = jsonDecode(text) as Map<String, dynamic>;
      return SidecarMetadata.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<File?> moveSidecar(String oldMediaPath, String newMediaPath) async {
    final oldPath = sidecarPathFor(oldMediaPath);
    final newPath = sidecarPathFor(newMediaPath);
    final oldFile = File(oldPath);
    if (!await oldFile.exists()) return null;
    final newFile = File(newPath);
    final parent = newFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    return oldFile.rename(newPath);
  }

  Future<bool> deleteSidecar(String mediaPath) async {
    final path = sidecarPathFor(mediaPath);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      return true;
    }
    return false;
  }
}
