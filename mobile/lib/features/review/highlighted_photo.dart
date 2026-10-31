import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/review_visual_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../shared/crop_image.dart';
import 'review_media_viewer.dart';

/// Where a face or body was found (its first occurrence).
final reviewVisualProvider = FutureProvider.autoDispose
    .family<ReviewVisual?, (String, int)>((ref, target) async {
      final visuals = await ReviewVisualRepository(
        ref.watch(databaseProvider),
      ).load([ReviewTarget(target.$1, target.$2)]);
      return visuals.isEmpty ? null : visuals.first;
    });

/// A photo, decoded once to learn its size. Null when the original is gone.
final _photoProvider = FutureProvider.autoDispose
    .family<(Uint8List, int, int)?, (String, int)>((ref, key) async {
      try {
        final bytes = await ref
            .watch(mediaLibraryProvider)
            .viewerImage(key.$1, maxSide: key.$2);
        if (bytes == null) return null;
        final codec = await ui.instantiateImageCodec(bytes);
        try {
          final frame = await codec.getNextFrame();
          final result = (bytes, frame.image.width, frame.image.height);
          frame.image.dispose();
          return result;
        } finally {
          codec.dispose();
        }
      } catch (_) {
        return null;
      }
    });

/// The whole photo with one face (`kind` 'f') or body ('b') highlighted and its crop as an inset,
/// the way the quick review and the album review show a question. Videos and missing originals
/// fall back to the crop.
class HighlightedPhoto extends ConsumerWidget {
  const HighlightedPhoto({
    super.key,
    required this.kind,
    required this.id,
    this.maxSide = 1600,
    this.inset = true,
    this.label = true,
  });

  final String kind;
  final int id;
  final int maxSide;
  final bool inset;
  final bool label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final visual = ref.watch(reviewVisualProvider((kind, id)));
    final placeholder = kind == 'f'
        ? Icons.face_outlined
        : Icons.accessibility_new;
    Widget crop(String? path) => Center(
      child: CropImage(
        key: Key('highlight-crop-$kind-$id'),
        path: path,
        fit: BoxFit.contain,
        cacheWidth: 800,
        placeholderIcon: placeholder,
      ),
    );
    return visual.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => crop(null),
      data: (v) {
        if (v == null) return crop(null);
        if (v.assetId == null || v.mediaKind == 'video') {
          return crop(v.cropPath);
        }
        final photo = ref.watch(_photoProvider((v.assetId!, maxSide)));
        return photo.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => crop(v.cropPath),
          data: (image) {
            if (image == null) return crop(v.cropPath);
            return Center(
              child: AspectRatio(
                aspectRatio: image.$2 / image.$3,
                child: Semantics(
                  label: kind == 'f'
                      ? l.reviewFaceHighlighted
                      : l.reviewBodyHighlighted,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(
                        image.$1,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                      ),
                      IgnorePointer(
                        child: CustomPaint(
                          key: Key('highlight-$kind-$id'),
                          painter: ReviewHighlightPainter(
                            Rect.fromLTWH(v.x, v.y, v.w, v.h),
                            label: label
                                ? (kind == 'f' ? l.reviewFace : l.reviewBody)
                                : '',
                          ),
                        ),
                      ),
                      if (inset && v.cropPath != null)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          width: 76,
                          height: kind == 'f' ? 76 : 104,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 2),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: const [
                                BoxShadow(blurRadius: 6, color: Colors.black45),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: CropImage(
                                path: v.cropPath,
                                cacheWidth: 240,
                                placeholderIcon: placeholder,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
