import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/marks/mark_geometry.dart';
import '../../domain/pose/pose_geometry.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../shared/crop_image.dart';

String segmentLabel(AppLocalizations l, String segment) => switch (segment) {
  'r_upper_arm' => l.markSegRUpperArm,
  'l_upper_arm' => l.markSegLUpperArm,
  'r_forearm' => l.markSegRForearm,
  'l_forearm' => l.markSegLForearm,
  'r_thigh' => l.markSegRThigh,
  'l_thigh' => l.markSegLThigh,
  'r_lower_leg' => l.markSegRLowerLeg,
  'l_lower_leg' => l.markSegLLowerLeg,
  'chest' => l.markSegChest,
  'abdomen' => l.markSegAbdomen,
  'ribs' => l.markSegRibs,
  'upper_back' => l.markSegUpperBack,
  'lower_back' => l.markSegLowerBack,
  'hips' => l.markSegHips,
  _ => segment,
};

/// Roadmap 7.4, marking: on a body of a KNOWN person the user picks the body area, taps the tattoo on the body
/// picture and sets its size. The patch is cut from the original photo and stored with its position relative to
/// the area's anchor keypoints. Returns true when a mark was saved.
Future<bool> showMarkTattoo(
  BuildContext context,
  WidgetRef ref,
  int bodyId,
) async {
  final l = AppLocalizations.of(context);
  final db = ref.read(databaseProvider);
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));

  final body = await (db.select(
    db.bodies,
  )..where((b) => b.id.equals(bodyId))).getSingleOrNull();
  if (body == null || body.mediaId == null) return false;
  final media = await (db.select(
    db.media,
  )..where((m) => m.id.equals(body.mediaId!))).getSingleOrNull();
  final face = body.faceId == null
      ? null
      : await (db.select(
          db.faces,
        )..where((f) => f.id.equals(body.faceId!))).getSingleOrNull();
  final personId = face?.personId ?? body.personId;
  if (!context.mounted) return false;
  if (personId == null) {
    say(l.markNeedsPerson);
    return false;
  }
  final pose = media == null
      ? null
      : Pose.fromJson(
          body.kpts,
          media.width,
          media.height,
          extent: body.extent,
        );
  final segments = pose == null
      ? const <String>[]
      : [
          for (final s in markSegments)
            if (segmentVisible(pose, s)) s,
        ];
  if (segments.isEmpty) {
    say(l.markNoSegment);
    return false;
  }
  final choice = await showDialog<_MarkChoice>(
    context: context,
    builder: (_) => _MarkDialog(segments: segments, cropPath: body.cropPath),
  );
  if (choice == null || !context.mounted) return false;

  final bx = body.bboxX * media!.width!.toDouble();
  final by = body.bboxY * media.height!.toDouble();
  final bw = body.bboxW * media.width!.toDouble();
  final bh = body.bboxH * media.height!.toDouble();
  final size = choice.size * bw;
  final box = (
    x: bx + choice.fx * bw - size / 2,
    y: by + choice.fy * bh - size / 2,
    w: size,
    h: size,
  );
  final anchor = anchorFor(pose!, choice.segment, box);
  final rect = anchor == null ? null : rectFor(pose, choice.segment, anchor);
  final patch = rect == null
      ? null
      : await ref.read(patchCutterProvider)(media, rect);
  if (!context.mounted) return false;
  if (patch == null) {
    say(l.markPatchFailed);
    return false;
  }
  await ref
      .read(bodyMarkStoreProvider)
      .create(
        personId: personId,
        segment: choice.segment,
        anchor: anchor!,
        patch: patch,
        sourceBodyId: bodyId,
      );
  if (context.mounted) say(l.markSaved);
  return true;
}

class _MarkChoice {
  const _MarkChoice(this.segment, this.fx, this.fy, this.size);
  final String segment;
  final double fx, fy; // the tap, as fractions of the body box
  final double size; // fraction of the body box width
}

class _MarkDialog extends StatefulWidget {
  const _MarkDialog({required this.segments, required this.cropPath});

  final List<String> segments;
  final String? cropPath;

  @override
  State<_MarkDialog> createState() => _MarkDialogState();
}

class _MarkDialogState extends State<_MarkDialog> {
  late String _segment = widget.segments.first;
  Offset? _tap; // fractions of the picture
  double _size = 0.2;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.markTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.markPickSegment),
              DropdownButton<String>(
                key: const Key('mark-segment'),
                isExpanded: true,
                value: _segment,
                items: [
                  for (final s in widget.segments)
                    DropdownMenuItem(value: s, child: Text(segmentLabel(l, s))),
                ],
                onChanged: (v) => setState(() => _segment = v ?? _segment),
              ),
              const SizedBox(height: 8),
              Text(l.markTapToPlace),
              const SizedBox(height: 8),
              AspectRatio(
                aspectRatio: 0.62,
                child: LayoutBuilder(
                  builder: (context, c) => GestureDetector(
                    key: const Key('mark-picture'),
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => setState(
                      () => _tap = Offset(
                        (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0),
                        (d.localPosition.dy / c.maxHeight).clamp(0.0, 1.0),
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CropImage(
                            path: widget.cropPath,
                            placeholderIcon: Icons.accessibility_new,
                            fit: BoxFit.fill,
                            cacheWidth: 512,
                          ),
                        ),
                        if (_tap != null)
                          Positioned(
                            left:
                                _tap!.dx * c.maxWidth - _size * c.maxWidth / 2,
                            top:
                                _tap!.dy * c.maxHeight - _size * c.maxWidth / 2,
                            width: _size * c.maxWidth,
                            height: _size * c.maxWidth,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.redAccent,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Text(l.markSize),
                  Expanded(
                    child: Slider(
                      key: const Key('mark-size'),
                      min: 0.08,
                      max: 0.6,
                      value: _size,
                      onChanged: (v) => setState(() => _size = v),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const Key('mark-save'),
          onPressed: _tap == null
              ? null
              : () => Navigator.pop(
                  context,
                  _MarkChoice(_segment, _tap!.dx, _tap!.dy, _size),
                ),
          child: Text(l.markSave),
        ),
      ],
    );
  }
}
