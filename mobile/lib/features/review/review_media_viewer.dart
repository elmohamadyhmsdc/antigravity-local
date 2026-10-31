import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/review_visual_repository.dart';
import '../../data/repositories/media_queries.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../media/video_media_view.dart';
import '../shared/crop_image.dart';

Future<void> openReviewMedia(
  BuildContext context,
  List<ReviewTarget> targets, {
  int initialTarget = 0,
  String? title,
  Set<int>? selectedFaceIds,
  ValueChanged<Set<int>>? onSelectionChanged,
  Future<void> Function(bool)? onBodyDecision,
  String? personName,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => ReviewMediaViewer(
      targets: targets,
      initialTarget: initialTarget,
      title: title,
      selectedFaceIds: selectedFaceIds,
      onSelectionChanged: onSelectionChanged,
      onBodyDecision: onBodyDecision,
      personName: personName,
    ),
  ),
);

Future<void> reviewPersonPhotos(
  BuildContext context,
  WidgetRef ref,
  int personId,
  String name,
) async {
  final faces = await ref.read(peopleRepositoryProvider).personFaces(personId);
  if (context.mounted) {
    await openReviewMedia(context, [
      for (final f in faces.where((f) => !f.hidden)) ReviewTarget('f', f.id),
    ], title: name);
  }
}

class ReviewMediaViewer extends ConsumerStatefulWidget {
  const ReviewMediaViewer({
    super.key,
    required this.targets,
    this.initialTarget = 0,
    this.title,
    this.selectedFaceIds,
    this.onSelectionChanged,
    this.onBodyDecision,
    this.personName,
  });
  final List<ReviewTarget> targets;
  final int initialTarget;
  final String? title;
  final Set<int>? selectedFaceIds;
  final ValueChanged<Set<int>>? onSelectionChanged;
  final Future<void> Function(bool)? onBodyDecision;
  final String? personName;
  @override
  ConsumerState<ReviewMediaViewer> createState() => _ReviewMediaViewerState();
}

class _ReviewMediaViewerState extends ConsumerState<ReviewMediaViewer> {
  late Future<List<ReviewVisual>> future;
  PageController? controller;
  int page = 0;
  bool showCrop = false;
  bool deciding = false;
  late final selected = {...?widget.selectedFaceIds};
  @override
  void initState() {
    super.initState();
    future = ReviewVisualRepository(ref.read(databaseProvider))
        .load(widget.targets)
        .then((items) {
          if (!mounted) return items;
          if (items.isNotEmpty && widget.targets.isNotEmpty) {
            final target =
                widget.targets[widget.initialTarget.clamp(
                  0,
                  widget.targets.length - 1,
                )];
            final index = items.indexWhere(
              (v) => v.target.kind == target.kind && v.target.id == target.id,
            );
            page = index < 0 ? 0 : index;
          }
          controller = PageController(initialPage: page);
          return items;
        });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title ?? l.reviewPhotos,
          maxLines: 2,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        actions: [
          IconButton(
            key: const Key('review-toggle-crop'),
            tooltip: showCrop ? l.reviewFullPhoto : l.reviewCrop,
            onPressed: () => setState(() => showCrop = !showCrop),
            icon: Icon(showCrop ? Icons.photo_outlined : Icons.crop),
          ),
        ],
      ),
      body: FutureBuilder<List<ReviewVisual>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(l.peopleActionError('${snapshot.error}')),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) return Center(child: Text(l.reviewNoPhotos));
          final current = items[page];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Column(
                  children: [
                    Text(
                      current.target.kind == 'f'
                          ? l.reviewFaceHighlighted
                          : l.reviewBodyHighlighted,
                      key: const Key('review-target-label'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      current.mediaKind == 'video'
                          ? l.reviewVideoHint
                          : l.reviewViewerHint,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  key: const Key('review-photo-pages'),
                  controller: controller,
                  itemCount: items.length,
                  onPageChanged: (i) => setState(() => page = i),
                  itemBuilder: (_, i) => _ReviewSource(
                    key: ValueKey(
                      '${items[i].target.kind}:${items[i].target.id}:$i',
                    ),
                    visual: items[i],
                    crop: showCrop,
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          key: const Key('review-photo-previous'),
                          tooltip: l.reviewPreviousPhoto,
                          onPressed: page == 0
                              ? null
                              : () => controller!.jumpToPage(page - 1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text(
                          '${page + 1} / ${items.length}',
                          key: const Key('review-photo-count'),
                        ),
                        IconButton(
                          key: const Key('review-photo-next'),
                          tooltip: l.reviewNextPhoto,
                          onPressed: page == items.length - 1
                              ? null
                              : () => controller!.jumpToPage(page + 1),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    if (current.timestampMs != null)
                      Text(videoTime(current.timestampMs!)),
                    if (widget.onSelectionChanged != null &&
                        current.target.kind == 'f')
                      CheckboxListTile(
                        key: const Key('review-viewer-include'),
                        title: Text(l.reviewIncludeFace),
                        dense: true,
                        value: selected.contains(current.target.id),
                        onChanged: (_) => setState(() {
                          if (!selected.remove(current.target.id)) {
                            selected.add(current.target.id);
                          }
                          widget.onSelectionChanged!({...selected});
                        }),
                      ),
                    if (widget.onBodyDecision != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            FilledButton(
                              key: const Key('review-viewer-yes'),
                              onPressed: deciding ? null : () => _decide(true),
                              child: Text(
                                l.reviewYesPerson(widget.personName ?? ''),
                              ),
                            ),
                            OutlinedButton(
                              key: const Key('review-viewer-no'),
                              onPressed: deciding ? null : () => _decide(false),
                              child: Text(l.reviewNotPerson),
                            ),
                          ],
                        ),
                      ),
                    SizedBox(
                      height: 72,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: items.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.all(4),
                          child: Semantics(
                            selected: page == i,
                            child: InkWell(
                              key: Key('review-photo-thumb-$i'),
                              onTap: () => controller!.jumpToPage(i),
                              child: Container(
                                width: 64,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    width: page == i ? 3 : 1,
                                    color: page == i
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.outlineVariant,
                                  ),
                                ),
                                child: CropImage(path: items[i].cropPath),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _decide(bool yes) async {
    setState(() => deciding = true);
    try {
      await widget.onBodyDecision!(yes);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => deciding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).peopleActionError('$e')),
          ),
        );
      }
    }
  }
}

class _ReviewSource extends ConsumerStatefulWidget {
  const _ReviewSource({super.key, required this.visual, required this.crop});
  final ReviewVisual visual;
  final bool crop;
  @override
  ConsumerState<_ReviewSource> createState() => _ReviewSourceState();
}

class _ReviewSourceState extends ConsumerState<_ReviewSource> {
  late Future<(Uint8List, int, int)?> photo;
  @override
  void initState() {
    super.initState();
    photo = _load();
  }

  Future<(Uint8List, int, int)?> _load() async {
    final v = widget.visual;
    if (v.assetId == null || v.mediaKind == 'video') return null;
    try {
      final bytes = await ref
          .read(mediaLibraryProvider)
          .viewerImage(v.assetId!, maxSide: 2560);
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
  }

  Widget _crop(BuildContext context, {bool missing = false}) => Column(
    children: [
      if (missing)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(AppLocalizations.of(context).reviewOriginalMissing),
        ),
      Expanded(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 6,
          child: Center(
            child: CropImage(
              path: widget.visual.cropPath,
              fit: BoxFit.contain,
              cacheWidth: 1200,
            ),
          ),
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final v = widget.visual;
    final l = AppLocalizations.of(context);
    if (widget.crop) return _crop(context);
    if (v.mediaKind == 'video' && v.assetId != null) {
      final target = MediaDetection(
        id: -1,
        kind: v.target.kind,
        refId: v.target.id,
        x: v.x,
        y: v.y,
        w: v.w,
        h: v.h,
        personId: null,
        cropPath: v.cropPath,
        timestampMs: v.timestampMs ?? 0,
      );
      return VideoMediaView(
        key: ValueKey('${v.assetId}:${v.timestampMs}'),
        assetId: v.assetId!,
        library: ref.watch(mediaLibraryProvider),
        detections: [target],
        people: const {},
        showBodies: true,
        initialTimestampMs: v.timestampMs ?? 0,
        onTapBox: (_) {},
        focusKind: v.target.kind,
        focusRefId: v.target.id,
      );
    }
    return FutureBuilder(
      future: photo,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final image = snapshot.data;
        if (image == null) return _crop(context, missing: true);
        return Center(
          child: AspectRatio(
            aspectRatio: image.$2 / image.$3,
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 6,
              child: Semantics(
                label: v.target.kind == 'f'
                    ? l.reviewFaceHighlighted
                    : l.reviewBodyHighlighted,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(image.$1, fit: BoxFit.fill),
                    IgnorePointer(
                      child: CustomPaint(
                        key: const Key('review-target-highlight'),
                        painter: ReviewHighlightPainter(
                          Rect.fromLTWH(v.x, v.y, v.w, v.h),
                          label: v.target.kind == 'f'
                              ? l.reviewFace
                              : l.reviewBody,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ReviewHighlightPainter extends CustomPainter {
  const ReviewHighlightPainter(this.box, {required this.label});
  final Rect box;
  final String label;
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final target = Rect.fromLTRB(
      box.left * size.width,
      box.top * size.height,
      box.right * size.width,
      box.bottom * size.height,
    ).intersect(bounds);
    if (target.isEmpty) return;
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(bounds),
        Path()..addRect(target),
      ),
      Paint()..color = Colors.black.withValues(alpha: .5),
    );
    canvas.drawRect(
      target,
      Paint()
        ..color = Colors.amberAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    final x = target.left.clamp(
      0.0,
      (size.width - text.width - 12).clamp(0.0, size.width),
    );
    final y = (target.top - text.height - 8).clamp(
      0.0,
      (size.height - text.height - 8).clamp(0.0, size.height),
    );
    canvas.drawRect(
      Rect.fromLTWH(x, y, text.width + 12, text.height + 8),
      Paint()..color = Colors.amberAccent,
    );
    text.paint(canvas, Offset(x + 6, y + 4));
  }

  @override
  bool shouldRepaint(ReviewHighlightPainter oldDelegate) =>
      oldDelegate.box != box || oldDelegate.label != label;
}
