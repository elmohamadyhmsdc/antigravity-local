import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/files/crop_cache.dart';
import '../../data/files/crop_cutter.dart';

/// Let the user isolate the torso, garment, or other useful reference area.
Future<Uint8List?> choosePhotoEditReference(
  BuildContext context,
  Uint8List bytes,
) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final aspect = frame.image.width / frame.image.height;
  frame.image.dispose();
  codec.dispose();
  if (!context.mounted) return null;
  final screen = MediaQuery.sizeOf(context);
  final height = math.min(
    (screen.width - 128).clamp(48.0, 420.0) / aspect,
    screen.height * .42,
  );
  final width = height * aspect;
  Offset normalized(Offset point) => Offset(
    (point.dx / width).clamp(0, 1).toDouble(),
    (point.dy / height).clamp(0, 1).toDouble(),
  );

  var selection = const Rect.fromLTWH(0, 0, 1, 1);
  Offset? start;
  final region = await showDialog<Rect>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Reference area'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Drag over the area to use as a guide.'),
            const SizedBox(height: 12),
            SizedBox(
              width: width,
              height: height,
              child: GestureDetector(
                onPanDown: (event) => start = normalized(event.localPosition),
                onPanUpdate: (event) {
                  if (start case final anchor?) {
                    final area = Rect.fromPoints(
                      anchor,
                      normalized(event.localPosition),
                    );
                    setState(() => selection = area);
                  }
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(bytes, fit: BoxFit.fill),
                    Positioned.fromRect(
                      rect: Rect.fromLTWH(
                        selection.left * width,
                        selection.top * height,
                        selection.width * width,
                        selection.height * height,
                      ),
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: selection.width < .03 || selection.height < .03
                ? null
                : () => Navigator.of(context).pop(selection),
            child: const Text('Use reference'),
          ),
        ],
      ),
    ),
  );
  if (region == null) return null;
  if (region == const Rect.fromLTWH(0, 0, 1, 1)) return bytes;
  final crop = await cutCrop(bytes, CropKind.body, (
    x: region.left,
    y: region.top,
    w: region.width,
    h: region.height,
  ), pad: false);
  if (crop == null) {
    throw const FormatException('Could not crop this reference photo.');
  }
  return crop;
}
