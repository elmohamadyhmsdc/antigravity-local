import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dtos/system.dart';
import '../../library_providers.dart';
import '../../providers.dart';

Capabilities? studioCapabilities(ServerStatus? status) => switch (status) {
  ServerReady(:final capabilities) => capabilities,
  ServerBusy(:final capabilities) => capabilities,
  _ => null,
};

Future<File> privatePickedPhoto(WidgetRef ref, Uint8List bytes) async {
  final files = ref.read(fileStoreProvider);
  final path = 'work/picker/${DateTime.now().microsecondsSinceEpoch}.jpg';
  await files.write(path, bytes);
  return files.resolve(path);
}

void studioError(BuildContext context, Object error) {
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }
}
