import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/router.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/media_queries.dart';
import '../../data/repositories/people_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../shared/crop_image.dart';
import '../shared/empty_state.dart';
import '../shared/person_picker.dart';
import 'video_media_view.dart';

final mediaRowProvider = StreamProvider.autoDispose.family<MediaRow?, int>(
  (ref, id) => ref.watch(libraryRepositoryProvider).watchMedia(id),
);

final detectionsProvider = StreamProvider.autoDispose
    .family<List<MediaDetection>, int>(
      (ref, id) => ref.watch(mediaQueriesProvider).watchDetections(id),
    );

class _Loaded {
  const _Loaded(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

/// S06 - one photo/video viewer with swipe navigation (PageView) across the active filter,
/// toggleable face/body annotations, and Google Lens visual search.
class MediaScreen extends ConsumerStatefulWidget {
  const MediaScreen({
    super.key,
    required this.mediaId,
    this.initialTimestampMs,
    this.filter,
  });

  final int mediaId;
  final int? initialTimestampMs;
  final MediaFilter? filter;

  @override
  ConsumerState<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends ConsumerState<MediaScreen> {
  late List<int> _mediaIds;
  int _currentIndex = 0;
  PageController? _pageController;
  var _showBodies = false;
  var _showFaces = true;

  @override
  void initState() {
    super.initState();
    _mediaIds = [widget.mediaId];
    _currentIndex = 0;
    _pageController = PageController(initialPage: 0);
    _loadIds();
  }

  Future<void> _loadIds() async {
    try {
      final queries = ref.read(mediaQueriesProvider);
      final filter = widget.filter ?? const MediaFilter();
      final list = await queries.ids(filter);
      if (!mounted || list.isEmpty) return;
      final index = list.indexOf(widget.mediaId);
      setState(() {
        _mediaIds = list;
        _currentIndex = index >= 0 ? index : 0;
        _pageController?.dispose();
        _pageController = PageController(initialPage: _currentIndex);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  Future<void> _searchGoogleLens(BuildContext context, MediaRow media) async {
    final l10n = AppLocalizations.of(context);
    try {
      final lib = ref.read(mediaLibraryProvider);
      final entity = await AssetEntity.fromId(media.assetId);
      File? file = await entity?.originFile;
      file ??= await entity?.file;
      if (file == null) {
        final bytes = await lib.viewerImage(media.assetId);
        if (bytes != null) {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File(
            '${tempDir.path}/lens_${media.id}_${media.assetId.replaceAll(RegExp(r'[^\w\.-]'), '_')}.jpg',
          );
          await tempFile.writeAsBytes(bytes);
          file = tempFile;
        }
      }
      if (file == null || !file.existsSync()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.googleLensError)),
          );
        }
        return;
      }
      const channel = MethodChannel('antigravity/lens');
      await channel.invokeMethod('searchImage', {'path': file.path});
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.googleLensError)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final activeId = (_mediaIds.isNotEmpty && _currentIndex < _mediaIds.length)
        ? _mediaIds[_currentIndex]
        : widget.mediaId;
    final row = ref.watch(mediaRowProvider(activeId));
    final detections =
        ref.watch(detectionsProvider(activeId)).value ??
        const <MediaDetection>[];
    final people = {
      for (final p
          in ref.watch(peopleProvider).value ?? const <PersonSummary>[])
        p.id: p,
    };

    return row.when(
      loading: () => Scaffold(appBar: AppBar(), body: const LoadingBox()),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: RetryState(
          onRetry: () => ref.invalidate(mediaRowProvider(activeId)),
        ),
      ),
      data: (media) {
        if (media == null) {
          return Scaffold(
            appBar: AppBar(),
            body: EmptyState(icon: Icons.photo_outlined, title: l10n.photoGone),
          );
        }
        final taken = media.takenAt == null
            ? null
            : DateFormat.yMMMd().add_Hm().format(
                DateTime.fromMillisecondsSinceEpoch(media.takenAt!),
              );
        final faces = [
          for (final d in detections)
            if (d.isFace) d,
        ];
        final bodies = [
          for (final d in detections)
            if (!d.isFace) d,
        ];
        return Scaffold(
          bottomNavigationBar: media.scanError == null
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded),
                        const SizedBox(width: 10),
                        Expanded(child: Text(media.scanError!)),
                      ],
                    ),
                  ),
                ),
          appBar: AppBar(
            title: Text(
              taken ??
                  (media.kind == 'video' ? l10n.videoTitle : l10n.photoTitle),
            ),
            actions: [
              if (faces.isNotEmpty)
                IconButton(
                  key: const Key('toggle-faces'),
                  tooltip: _showFaces ? l10n.hideFaces : l10n.showFaces,
                  icon: Icon(
                    _showFaces ? Icons.face : Icons.face_outlined,
                  ),
                  onPressed: () => setState(() => _showFaces = !_showFaces),
                ),
              if (bodies.isNotEmpty)
                IconButton(
                  key: const Key('toggle-bodies'),
                  tooltip: _showBodies ? l10n.hideBodies : l10n.showBodies,
                  icon: Icon(
                    _showBodies
                        ? Icons.accessibility_new
                        : Icons.accessibility_outlined,
                  ),
                  onPressed: () => setState(() => _showBodies = !_showBodies),
                ),
              IconButton(
                key: const Key('google-lens'),
                tooltip: l10n.searchGoogleLens,
                icon: const Icon(Icons.camera_alt_outlined),
                onPressed: () => _searchGoogleLens(context, media),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  key: const Key('media-page-view'),
                  controller: _pageController,
                  itemCount: _mediaIds.length,
                  onPageChanged: (i) {
                    setState(() {
                      _currentIndex = i;
                    });
                  },
                  itemBuilder: (context, i) {
                    final itemMediaId = _mediaIds[i];
                    return _MediaPageViewItem(
                      key: ValueKey(itemMediaId),
                      mediaId: itemMediaId,
                      showFaces: _showFaces,
                      showBodies: _showBodies,
                      people: people,
                      onTapBox: (d) => _boxMenu(context, d, people),
                      initialTimestampMs: (itemMediaId == widget.mediaId)
                          ? widget.initialTimestampMs
                          : null,
                    );
                  },
                ),
              ),
              _WhoIsHere(
                faces: [
                  ...faces,
                  ...bodies.where((b) => b.personId != null),
                ],
                people: people,
                mediaScanned: media.scanStatus == 'done',
                onOpen: (d) => _boxMenu(context, d, people),
                onEdit: (d) => _reassign(context, d),
              ),
            ],
          ),
        );
      },
    );
  }

  /// "Who is this?" for one face (or a body without a person): pick or name someone.
  Future<void> _reassign(BuildContext context, MediaDetection d) async {
    final repo = ref.read(peopleRepositoryProvider);
    final choice = await pickPerson(
      context,
      excludePersonId: d.personId,
      allowNew: d.isFace,
    );
    if (choice == null) return;
    if (d.isFace) {
      final target = await resolveChoice(ref, choice, faceIds: [d.refId]);
      if (!choice.isNew) await repo.assignFaces([d.refId], target);
    } else if (choice.personId != null) {
      await repo.linkBody(d.refId, choice.personId!);
    }
  }

  Future<void> _boxMenu(
    BuildContext context,
    MediaDetection d,
    Map<int, PersonSummary> people,
  ) async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(peopleRepositoryProvider);
    final person = d.personId == null ? null : people[d.personId];
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: SizedBox(
                width: 44,
                height: 44,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CropImage(
                    path: d.cropPath,
                    placeholderIcon: d.isFace
                        ? Icons.face_outlined
                        : Icons.accessibility_new,
                  ),
                ),
              ),
              title: Text(
                person == null ? l10n.unsortedFace : personName(l10n, person),
              ),
              subtitle: Text(d.isFace ? l10n.faceBox : l10n.bodyBox),
            ),
            const Divider(height: 1),
            if (person != null)
              ListTile(
                key: const Key('box-open-person'),
                leading: const Icon(Icons.person_outline),
                title: Text(l10n.openPerson(personName(l10n, person))),
                onTap: () => Navigator.pop(context, 'open'),
              ),
            if (d.isFace || person == null)
              ListTile(
                key: const Key('box-assign'),
                leading: const Icon(Icons.drive_file_move_outline),
                title: Text(d.isFace ? l10n.assignTo : l10n.thisIsPerson),
                onTap: () => Navigator.pop(context, 'assign'),
              ),
            if (person != null)
              ListTile(
                key: const Key('box-reject'),
                leading: const Icon(Icons.person_off_outlined),
                title: Text(l10n.notPerson(personName(l10n, person))),
                onTap: () => Navigator.pop(context, 'reject'),
              ),
            if (d.isFace)
              ListTile(
                key: const Key('box-delete'),
                leading: const Icon(Icons.delete_outline),
                title: Text(l10n.deleteFace),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'open':
        context.push('${Routes.people}/${person!.id}');
      case 'assign':
        await _reassign(context, d);
      case 'reject':
        if (d.isFace) {
          await repo.rejectFaces([d.refId]);
        } else {
          await repo.rejectBody(d.refId, personId: d.personId);
        }
      case 'delete':
        final ok = await confirm(
          context,
          title: l10n.deleteFacesTitle(1),
          body: l10n.deleteFacesBody,
          confirmLabel: l10n.delete,
          cancelLabel: l10n.cancel,
          destructive: true,
        );
        if (ok) await repo.deleteFaces([d.refId]);
    }
  }
}

class _MediaPageViewItem extends ConsumerStatefulWidget {
  const _MediaPageViewItem({
    super.key,
    required this.mediaId,
    required this.showFaces,
    required this.showBodies,
    required this.people,
    required this.onTapBox,
    this.initialTimestampMs,
  });

  final int mediaId;
  final bool showFaces;
  final bool showBodies;
  final Map<int, PersonSummary> people;
  final void Function(MediaDetection) onTapBox;
  final int? initialTimestampMs;

  @override
  ConsumerState<_MediaPageViewItem> createState() =>
      _MediaPageViewItemState();
}

class _MediaPageViewItemState extends ConsumerState<_MediaPageViewItem> {
  Future<_Loaded?>? _image;
  String? _assetId;

  Future<_Loaded?> _load(String assetId) async {
    final bytes = await ref.read(mediaLibraryProvider).viewerImage(assetId);
    if (bytes == null) return null;
    final decoded = await ui.instantiateImageCodec(bytes);
    final frame = await decoded.getNextFrame();
    final loaded = _Loaded(bytes, frame.image.width, frame.image.height);
    frame.image.dispose();
    decoded.dispose();
    return loaded;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final row = ref.watch(mediaRowProvider(widget.mediaId));
    final detections =
        ref.watch(detectionsProvider(widget.mediaId)).value ??
        const <MediaDetection>[];

    return row.when(
      loading: () => const LoadingBox(),
      error: (_, _) => EmptyState(
        icon: Icons.photo_outlined,
        title: l10n.photoGone,
      ),
      data: (media) {
        if (media == null) {
          return EmptyState(
            icon: Icons.photo_outlined,
            title: l10n.photoGone,
          );
        }
        if (media.kind == 'video') {
          return VideoMediaView(
            key: ValueKey(media.assetId),
            assetId: media.assetId,
            initialTimestampMs: widget.initialTimestampMs,
            library: ref.watch(mediaLibraryProvider),
            detections: detections,
            people: widget.people,
            showBodies: widget.showBodies,
            showFaces: widget.showFaces,
            onTapBox: widget.onTapBox,
          );
        }
        if (_assetId != media.assetId) {
          _assetId = media.assetId;
          _image = _load(media.assetId);
        }
        final faces = [
          for (final d in detections)
            if (d.isFace) d,
        ];
        final bodies = [
          for (final d in detections)
            if (!d.isFace) d,
        ];
        return FutureBuilder<_Loaded?>(
          future: _image,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LoadingBox();
            }
            final image = snapshot.data;
            if (image == null) {
              return EmptyState(
                icon: Icons.photo_outlined,
                title: l10n.photoGone,
                body: l10n.photoGoneBody,
              );
            }
            return _AnnotatedPhoto(
              image: image,
              detections: [
                if (widget.showFaces) ...faces,
                if (widget.showBodies) ...bodies,
              ],
              people: widget.people,
              onTapBox: widget.onTapBox,
            );
          },
        );
      },
    );
  }
}

/// The photo with boxes. Boxes are normalised to the photo, so they stay put when it is zoomed.
class _AnnotatedPhoto extends StatelessWidget {
  const _AnnotatedPhoto({
    required this.image,
    required this.detections,
    required this.people,
    required this.onTapBox,
  });

  final _Loaded image;
  final List<MediaDetection> detections;
  final Map<int, PersonSummary> people;
  final void Function(MediaDetection) onTapBox;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fitted = applyBoxFit(
          BoxFit.contain,
          Size(image.width.toDouble(), image.height.toDouble()),
          constraints.biggest,
        ).destination;
        return Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: SizedBox(
              key: const Key('annotated-photo'),
              width: fitted.width,
              height: fitted.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    image.bytes,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  ),
                  for (final d in detections)
                    Positioned(
                      left: d.x * fitted.width,
                      top: d.y * fitted.height,
                      width: d.w * fitted.width,
                      height: d.h * fitted.height,
                      child: GestureDetector(
                        key: Key('box-${d.kind}-${d.refId}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onTapBox(d),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: d.isFace ? BoxShape.circle : BoxShape.rectangle,
                            color: d.isFace
                                ? (d.personId == null
                                      ? Colors.amber.withValues(alpha: 0.10)
                                      : scheme.primary.withValues(alpha: 0.12))
                                : Colors.lightBlueAccent.withValues(alpha: 0.18),
                            border: Border.all(
                              width: d.isFace ? 2.5 : 2.0,
                              color: d.isFace
                                  ? (d.personId == null
                                        ? Colors.amber
                                        : scheme.primary)
                                  : Colors.lightBlueAccent,
                            ),
                            borderRadius:
                                d.isFace ? null : BorderRadius.circular(12),
                          ),
                          child:
                              d.personId != null &&
                                  people[d.personId] != null &&
                                  d.isFace
                              ? Align(
                                  alignment: Alignment.topLeft,
                                  child: ColoredBox(
                                    color: scheme.primary,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 3,
                                      ),
                                      child: Text(
                                        personName(l10n, people[d.personId]!),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: scheme.onPrimary,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : null,
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
  }
}

/// "People in this photo": one entry per detected face (and body linked to someone), each with a
/// pencil to say who it really is.
class _WhoIsHere extends StatelessWidget {
  const _WhoIsHere({
    required this.faces,
    required this.people,
    required this.mediaScanned,
    required this.onOpen,
    required this.onEdit,
  });

  final List<MediaDetection> faces;
  final Map<int, PersonSummary> people;
  final bool mediaScanned;
  final void Function(MediaDetection) onOpen;
  final void Function(MediaDetection) onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final seen = <int>{};
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.whoIsHere,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              if (faces.isNotEmpty) ...[
                Text(
                  l10n.mediaPeopleHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
              ],
              if (faces.isEmpty)
                Text(mediaScanned ? l10n.noFacesInPhoto : l10n.notScannedYet)
              else
                SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(16) + 32,
                  child: ListView(
                    key: const Key('who-is-here'),
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final d in faces)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ActionChip(
                                key: d.personId != null && seen.add(d.personId!)
                                    ? Key('who-${d.personId}')
                                    : Key('who-${d.kind}-${d.refId}'),
                                avatar: ClipOval(
                                  child: CropImage(
                                    path: d.cropPath,
                                    placeholderIcon: d.isFace
                                        ? Icons.face_outlined
                                        : Icons.accessibility_new,
                                  ),
                                ),
                                label: Text(
                                  d.personId == null
                                      ? l10n.viewerUnknownPerson
                                      : personNameOf(l10n, d.personId!, people),
                                ),
                                onPressed: () => d.personId == null
                                    ? onOpen(d)
                                    : context.push(
                                        '${Routes.people}/${d.personId}',
                                      ),
                              ),
                              if (d.isFace)
                                IconButton(
                                  key: Key('who-edit-${d.refId}'),
                                  tooltip: l10n.viewerReassign,
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                  onPressed: () => onEdit(d),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
