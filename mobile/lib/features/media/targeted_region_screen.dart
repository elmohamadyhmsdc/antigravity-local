import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/api/dtos/analyze.dart';
import 'roi_selection_overlay.dart';

/// Draws in the same upright image bytes sent to the PC, independent of viewer zoom.
class TargetedRegionScreen extends StatefulWidget {
  const TargetedRegionScreen({super.key, required this.bytes, required this.kind});

  final Uint8List bytes;
  final String kind;

  @override
  State<TargetedRegionScreen> createState() => _TargetedRegionScreenState();
}

class _TargetedRegionScreenState extends State<TargetedRegionScreen> {
  late final Future<Size> _imageSize = _loadSize();
  BBox _box = const BBox(x: .25, y: .25, w: .5, h: .5);

  Future<Size> _loadSize() async {
    final codec = await ui.instantiateImageCodec(widget.bytes);
    try {
      final frame = await codec.getNextFrame();
      final size = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      frame.image.dispose();
      return size;
    } finally {
      codec.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.kind == 'anime_face' ? 'Select anime face' : 'Select area'),
    ),
    body: FutureBuilder<Size>(
      future: _imageSize,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not open this photo. Go back and retry.'));
        }
        final size = snapshot.data;
        if (size == null) return const Center(child: CircularProgressIndicator());
        return SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Move the box and drag its handles to fit the face or area.'),
              ),
              Expanded(
                child: LayoutBuilder(builder: (context, constraints) {
                  final fitted = applyBoxFit(BoxFit.contain, size, constraints.biggest).destination;
                  return Center(
                    child: SizedBox(
                      width: fitted.width,
                      height: fitted.height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(widget.bytes, fit: BoxFit.fill),
                          RoiSelectionOverlay(
                            key: ValueKey(fitted),
                            fittedSize: fitted,
                            initialBBox: _box,
                            showActions: false,
                            onChanged: (box) => _box = box,
                            onConfirm: (_) {},
                            onCancel: () {},
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    TextButton(
                      key: const Key('target-region-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      key: const Key('target-region-scan'),
                      onPressed: () => Navigator.of(context).pop(_box),
                      icon: const Icon(Icons.search),
                      label: const Text('Scan this area'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
