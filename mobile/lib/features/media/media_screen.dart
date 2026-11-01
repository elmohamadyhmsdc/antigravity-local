import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/router.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/media_queries.dart';
import '../../data/repositories/artifact_context.dart';
import '../../data/repositories/people_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../../studio_providers.dart';
import '../bodies/body_naming.dart';
import '../bodies/group_pose_screens.dart';
import '../bodies/equipment_screens.dart';
import '../marks/mark_tattoo.dart';
import '../jobs/jobs_screen.dart' show jobTypeLabel;
import '../shared/crop_image.dart';
import '../shared/empty_state.dart';
import '../people/people_actions.dart' show moveToOtherKind;
import '../scan/redetect_flow.dart';
import '../scan/scan_progress_card.dart' show startScan;
import '../video_actions/video_actions_screen.dart';
import '../shared/person_picker.dart';
import '../shared/image_preview.dart';
import 'video_media_view.dart';
import '../../domain/geometry/outline.dart';

final mediaRowProvider = StreamProvider.autoDispose.family<MediaRow?, int>(
  (ref, id) => ref.watch(libraryRepositoryProvider).watchMedia(id),
);

final detectionsProvider = StreamProvider.autoDispose
    .family<List<MediaDetection>, int>(
      (ref, id) => ref.watch(mediaQueriesProvider).watchDetections(id),
    );

class _Loaded {
  const _Loaded(this.bytes, this.width, this.height, {this.fallback = false});
  final Uint8List bytes;
  final int width;
  final int height;
  final bool fallback;
}

class MediaCollectionContext {
  const MediaCollectionContext({required this.ids, this.loadMore});
  final List<int> ids;
  final Future<List<int>> Function()? loadMore;
}

/// S06 - one photo/video viewer with swipe navigation (PageView) across the active filter,
/// toggleable face/body annotations, and Google Lens visual search.
class MediaScreen extends ConsumerStatefulWidget {
  const MediaScreen({
    super.key,
    required this.mediaId,
    this.initialTimestampMs,
    this.filter,
    this.collection,
  });

  final int mediaId;
  final int? initialTimestampMs;
  final MediaFilter? filter;
  final MediaCollectionContext? collection;

  @override
  ConsumerState<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends ConsumerState<MediaScreen> {
  late List<int> _mediaIds;
  int _currentIndex = 0;
  PageController? _pageController;
  Offset? _swipeStart;
  int _pointerCount = 0;
  bool _multiTouch = false;
  var _loadingMore = false;
  int? _selectedDetectionId;
  var _chromeVisible = true;
  var _detailsOpen = false;
  var _zoomed = false;
  var _showBodies = false;
  var _showFaces = false;

  @override
  void initState() {
    super.initState();
    _mediaIds = List.of(widget.collection?.ids ?? [widget.mediaId]);
    _currentIndex = _mediaIds.indexOf(widget.mediaId);
    if (_currentIndex < 0) {
      _mediaIds = [widget.mediaId];
      _currentIndex = 0;
    }
    _pageController = PageController(initialPage: _currentIndex);
    if (widget.collection == null) _loadIds();
    if (_currentIndex >= _mediaIds.length - 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadMore();
      });
    }
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

  Future<void> _loadMore() async {
    final load = widget.collection?.loadMore;
    if (load == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final ids = await load();
      if (mounted && ids.isNotEmpty) {
        setState(() {
          for (final id in ids) {
            if (!_mediaIds.contains(id)) _mediaIds.add(id);
          }
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not load more photos. Return to Gallery to retry.',
            ),
          ),
        );
      }
    } finally {
      _loadingMore = false;
    }
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  Future<void> _searchGoogleLens(BuildContext context, MediaRow media) async {
    await searchPreviewImage(
      context,
      ref,
      ImagePreviewSource.asset(media.assetId, video: media.kind == 'video'),
    );
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
      for (final p in [
        ...ref.watch(peopleProvider).value ?? const <PersonSummary>[],
        ...ref.watch(charactersProvider).value ?? const <PersonSummary>[],
      ])
        p.id: p,
    };

    if (row.value != null &&
        row.value!.kind == 'photo' &&
        detections.any((d) => d.outline == null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(outlineBackfillProvider)
            .backfillPhoto(
              row.value!.id,
              assetId: row.value!.assetId,
              width: row.value!.width,
              height: row.value!.height,
            );
      });
    }

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
          backgroundColor: Colors.black,
          appBar: PreferredSize(
            preferredSize: Size.fromHeight(_chromeVisible ? kToolbarHeight : 0),
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: AnimatedOpacity(
                opacity: _chromeVisible ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: AppBar(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  leading: BackButton(
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go(Routes.library);
                      }
                    },
                  ),
                  title: Text(
                    taken ??
                        (media.kind == 'video'
                            ? l10n.videoTitle
                            : l10n.photoTitle),
                  ),
                  actions: [
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'faces') {
                          setState(() => _showFaces = !_showFaces);
                        }
                        if (value == 'bodies') {
                          setState(() => _showBodies = !_showBodies);
                        }
                        if (value == 'redetect') {
                          redetectFlow(context, ref, mediaId: media.id);
                        }
                        if (value == 'kind') _fileKindMenu(context, media);
                      },
                      itemBuilder: (_) => [
                        if (faces.isNotEmpty)
                          PopupMenuItem(
                            key: const Key('toggle-faces'),
                            value: 'faces',
                            child: Text(
                              _showFaces ? l10n.hideFaces : l10n.showFaces,
                            ),
                          ),
                        if (bodies.isNotEmpty)
                          PopupMenuItem(
                            key: const Key('toggle-bodies'),
                            value: 'bodies',
                            child: Text(
                              _showBodies ? l10n.hideBodies : l10n.showBodies,
                            ),
                          ),
                        if (media.kind == 'photo')
                          PopupMenuItem(
                            value: 'redetect',
                            child: Text(l10n.redetectTitle),
                          ),
                        PopupMenuItem(
                          value: 'kind',
                          child: Text(l10n.mediaKindTitle),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => AnimatedPadding(
                    duration: const Duration(milliseconds: 200),
                    padding: EdgeInsets.only(
                      bottom: _detailsOpen
                          ? (constraints.maxHeight -
                                    (MediaQuery.sizeOf(context).height * .25 -
                                        kToolbarHeight))
                                .clamp(0.0, constraints.maxHeight)
                          : 0,
                    ),
                    child: Listener(
                      onPointerDown: (event) {
                        _pointerCount++;
                        if (_pointerCount == 1) {
                          _swipeStart = event.position;
                          _multiTouch = false;
                        } else {
                          _multiTouch = true;
                        }
                      },
                      onPointerUp: (event) {
                        _pointerCount--;
                        final start = _swipeStart;
                        if (!_multiTouch &&
                            !_zoomed &&
                            media.kind == 'photo' &&
                            start != null &&
                            start.dy >
                                MediaQuery.sizeOf(context).height * .65 &&
                            start.dy - event.position.dy > 80 &&
                            (start.dx - event.position.dx).abs() < 60) {
                          _showDetails(context, media, faces, bodies, people);
                        }
                        if (_pointerCount == 0) _swipeStart = null;
                      },
                      onPointerCancel: (_) {
                        _pointerCount = 0;
                        _swipeStart = null;
                        _multiTouch = true;
                      },
                      child: PageView.builder(
                        key: const Key('media-page-view'),
                        controller: _pageController,
                        physics: _zoomed
                            ? const NeverScrollableScrollPhysics()
                            : null,
                        itemCount: _mediaIds.length,
                        onPageChanged: (i) {
                          setState(() {
                            _currentIndex = i;
                            _selectedDetectionId = null;
                          });
                          if (i >= _mediaIds.length - 3) _loadMore();
                        },
                        itemBuilder: (context, i) {
                          final itemMediaId = _mediaIds[i];
                          return _MediaPageViewItem(
                            key: ValueKey(itemMediaId),
                            mediaId: itemMediaId,
                            onToggleChrome: () => setState(
                              () => _chromeVisible = !_chromeVisible,
                            ),
                            onZoomChanged: (zoomed) {
                              if (_zoomed != zoomed &&
                                  itemMediaId == _mediaIds[_currentIndex]) {
                                setState(() => _zoomed = zoomed);
                              }
                            },
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
                  ),
                ),
              ),
              if (_chromeVisible)
                IgnorePointer(
                  ignoring: !_chromeVisible,
                  child: AnimatedOpacity(
                    opacity: _chromeVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: SafeArea(
                      top: false,
                      child: GestureDetector(
                        onVerticalDragEnd: (details) {
                          if ((details.primaryVelocity ?? 0) < -200) {
                            _showDetails(context, media, faces, bodies, people);
                          }
                        },
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => _shareOriginal(context, media),
                                icon: const Icon(Icons.share_outlined),
                                label: const Text('Share'),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => _showDetails(
                                  context,
                                  media,
                                  faces,
                                  bodies,
                                  people,
                                ),
                                icon: const Icon(Icons.info_outline),
                                label: const Text('Details'),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => _showTools(context, media),
                                icon: const Icon(Icons.build_outlined),
                                label: const Text('Tools'),
                              ),
                              TextButton.icon(
                                key: const Key('google-lens'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () =>
                                    _searchGoogleLens(context, media),
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: const Text('Lens'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _shareOriginal(BuildContext context, MediaRow media) async {
    try {
      final asset = await AssetEntity.fromId(media.assetId);
      final file = await asset?.originFile;
      if (file == null) throw StateError('Original file unavailable');
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  void _showDetails(
    BuildContext context,
    MediaRow media,
    List<MediaDetection> faces,
    List<MediaDetection> bodies,
    Map<int, PersonSummary> people,
  ) {
    final viewerContext = context;
    setState(() => _detailsOpen = true);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .75,
          minChildSize: .3,
          maxChildSize: .9,
          builder: (context, controller) => ListView(
            controller: controller,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Details',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              _WhoIsHere(
                label: media.kind == 'video' ? 'People in this video' : null,
                faces: [...faces, ...bodies.where((b) => b.personId != null)],
                people: people,
                mediaScanned: media.scanStatus == 'done',
                selectedId: _selectedDetectionId,
                onSelect: (d) {
                  setSheetState(() => _selectedDetectionId = d.id);
                },
                onOpen: (d) => _boxMenu(context, d, people),
                onEdit: (d) => _reassign(context, d),
              ),
              if (_selectedDetectionId != null)
                for (final detection in [...faces, ...bodies])
                  if (detection.id == _selectedDetectionId)
                    ListTile(
                      leading: const Icon(Icons.check_circle_outline),
                      title: Text(
                        detection.personId == null
                            ? 'Selected target: Unknown'
                            : 'Selected target: ${personNameOf(AppLocalizations.of(context), detection.personId!, people)}',
                      ),
                      subtitle: const Text('Choose an action for this target'),
                      trailing: TextButton(
                        onPressed: () => _boxMenu(context, detection, people),
                        child: const Text('Tools'),
                      ),
                    ),
              for (final personId in {
                ...faces.map((d) => d.personId),
                ...bodies.map((d) => d.personId),
              })
                if (personId != null && people[personId] != null)
                  _PersonContext(
                    person: people[personId]!,
                    initiallyExpanded:
                        {
                          ...faces.map((d) => d.personId),
                          ...bodies.map((d) => d.personId),
                        }.whereType<int>().length ==
                        1,
                    mediaId: media.id,
                    isPhoto: media.kind == 'photo',
                    detection: [
                      ...faces,
                      ...bodies,
                    ].firstWhere((d) => d.personId == personId),
                    onTools: (d) => _boxMenu(context, d, people),
                  ),
              StreamBuilder<List<ResultRow>>(
                stream: ref
                    .read(studioRepositoryProvider)
                    .watchResultsForMedia(media.id, assetId: media.assetId),
                builder: (context, snapshot) {
                  final results = snapshot.data ?? const <ResultRow>[];
                  if (results.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        child: Text('Related results'),
                      ),
                      for (final result in results)
                        FutureBuilder<ArtifactContext?>(
                          future: ref
                              .read(studioRepositoryProvider)
                              .contextFor(result.id),
                          builder: (context, relation) => ListTile(
                            leading: const Icon(Icons.auto_awesome_outlined),
                            title: Text(
                              jobTypeLabel(
                                AppLocalizations.of(context),
                                result.type,
                              ),
                            ),
                            subtitle: relation.data == null
                                ? null
                                : Text(
                                    relation.data!.referenceMediaId ==
                                                media.id &&
                                            relation.data!.mediaId != media.id
                                        ? 'Used as reference'
                                        : 'Created from this media',
                                  ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () =>
                                context.push('${Routes.results}/${result.id}'),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(media.kind == 'video' ? 'Video' : 'Photo'),
                subtitle: Text(
                  [
                    if (media.takenAt != null && media.takenAt! > 0)
                      DateFormat.yMMMd().add_Hm().format(
                        DateTime.fromMillisecondsSinceEpoch(media.takenAt!),
                      ),
                    if (media.width != null && media.height != null)
                      '${media.width} × ${media.height}',
                    if (media.kind == 'video' && media.durationMs != null)
                      videoTime(media.durationMs!),
                    if (media.scanStatus == 'done')
                      'Analysis complete'
                    else if (media.scanStatus == 'failed')
                      'Analysis failed'
                    else if (media.scanStatus == 'scanning')
                      'Analysis in progress'
                    else if (media.scanStatus == 'pending')
                      'Waiting for analysis'
                    else
                      'Not analyzed',
                  ].join(' · '),
                ),
              ),
              Consumer(
                builder: (context, ref, _) {
                  final location = ref.watch(
                    mediaLocationProvider(media.assetId),
                  );
                  return ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(
                      location.value?.fileName ?? 'Filename unavailable',
                    ),
                    subtitle: Text(
                      location.value?.folderName ?? 'Folder unavailable',
                    ),
                  );
                },
              ),
              if (media.scanError != null)
                ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: Text(media.scanError!),
                ),
              ListTile(
                leading: const Icon(Icons.build_outlined),
                title: const Text('Tools'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showTools(viewerContext, media);
                },
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _detailsOpen = false);
    });
  }

  void _showTools(BuildContext context, MediaRow media) {
    final selected = (ref.read(detectionsProvider(media.id)).value ?? const <MediaDetection>[]).where((d) => d.id == _selectedDetectionId).firstOrNull;
    final allowStudio = selected?.figure != 'character';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (allowStudio) ListTile(
                leading: const Icon(Icons.motion_photos_on_outlined),
                title: const Text('Name an action'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ActionExampleScreen(media: media),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.face_retouching_natural),
                title: const Text('Reface'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('${Routes.reface}?media=${media.id}${selected == null ? '' : '&target=${selected.id}'}');
                },
              ),
              if (media.kind == 'photo' && allowStudio) ...[
                ListTile(
                  leading: const Icon(Icons.checkroom_outlined),
                  title: const Text('Restyle'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.push('${Routes.restyle}?media=${media.id}${selected == null ? '' : '&target=${selected.id}'}');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Add to dataset'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.push('${Routes.loraBuild}?media=${media.id}');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('Generate with this reference'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.push('${Routes.loraGenerate}?media=${media.id}');
                  },
                ),
              ],
              if (media.kind == 'photo')
                ListTile(
                  leading: const Icon(Icons.center_focus_strong),
                  title: Text(
                    media.scanStatus == 'done'
                        ? AppLocalizations.of(context).redetectTitle
                        : 'Analyze photo',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    if (ref.read(mobileApiProvider) == null) {
                      context.push(Routes.connection);
                    } else {
                      redetectFlow(context, ref, mediaId: media.id);
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: Text(AppLocalizations.of(context).mediaKindTitle),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _fileKindMenu(context, media);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Who is this?" for one face (or a body without a person): pick or name someone.
  Future<void> _reassign(BuildContext context, MediaDetection d) async {
    final repo = peopleRepositoryFor(ref, d.figure);
    final choice = await pickPerson(
      context,
      excludePersonId: d.personId,
      allowNew: d.isFace,
      kind: d.figure,
    );
    if (choice == null) return;
    if (d.isFace) {
      final target = await resolveChoice(
        ref,
        choice,
        faceIds: [d.refId],
        kind: d.figure,
      );
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
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: SingleChildScrollView(
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
                    person == null
                        ? l10n.unsortedFace
                        : personName(l10n, person),
                  ),
                  subtitle: Text(d.isFace ? l10n.faceBox : l10n.bodyBox),
                ),
                const Divider(height: 1),
                if (d.isFace && d.figure == 'person') ...[
                  ListTile(
                    leading: const Icon(Icons.face_retouching_natural),
                    title: const Text('Reface this target'),
                    onTap: () => Navigator.pop(context, 'reface-target'),
                  ),
                  if (d.frameNumber == null)
                    ListTile(
                      leading: const Icon(Icons.checkroom_outlined),
                      title: const Text('Restyle this target'),
                      onTap: () => Navigator.pop(context, 'restyle-target'),
                    ),
                ],
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
                ListTile(
                  key: const Key('box-kind'),
                  leading: const Icon(Icons.swap_horiz),
                  title: Text(
                    d.figure == 'person'
                        ? l10n.boxIsCharacter
                        : l10n.boxIsPerson,
                  ),
                  onTap: () => Navigator.pop(context, 'kind'),
                ),
                if (!d.isFace) ...[
                  ListTile(
                    key: const Key('box-name-group-pose'),
                    leading: const Icon(Icons.groups_outlined),
                    title: Text(l10n.groupPoseName),
                    onTap: () => Navigator.pop(context, 'group-pose'),
                  ),
                  ListTile(
                    key: const Key('box-equipment'),
                    leading: const Icon(Icons.sports_tennis_outlined),
                    title: Text(l10n.bodiesTabEquipment),
                    onTap: () => Navigator.pop(context, 'equipment'),
                  ),
                  ListTile(
                    key: const Key('box-similar-pose'),
                    leading: const Icon(Icons.compare_outlined),
                    title: Text(l10n.bodyActionSimilarPose),
                    onTap: () => Navigator.pop(context, 'similar-pose'),
                  ),
                  ListTile(
                    key: const Key('box-similar-colours'),
                    leading: const Icon(Icons.palette_outlined),
                    title: Text(l10n.bodyActionSimilarColours),
                    onTap: () => Navigator.pop(context, 'similar-colours'),
                  ),
                  ListTile(
                    key: const Key('box-name-pose'),
                    leading: const Icon(Icons.accessibility_new),
                    title: Text(l10n.bodyActionNamePose),
                    onTap: () => Navigator.pop(context, 'name-pose'),
                  ),
                  ListTile(
                    key: const Key('box-mark-tattoo'),
                    leading: const Icon(Icons.draw_outlined),
                    title: Text(l10n.bodyActionMarkTattoo),
                    onTap: () => Navigator.pop(context, 'mark-tattoo'),
                  ),
                  ListTile(
                    key: const Key('box-name-outfit'),
                    leading: const Icon(Icons.checkroom_outlined),
                    title: Text(l10n.bodyActionNameOutfit),
                    onTap: () => Navigator.pop(context, 'name-outfit'),
                  ),
                ],
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
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'reface-target':
        context.push(
          '${Routes.reface}?media=${_mediaIds[_currentIndex]}&target=${d.id}',
        );
      case 'restyle-target':
        context.push(
          '${Routes.restyle}?media=${_mediaIds[_currentIndex]}&target=${d.id}',
        );
      case 'open':
        context.push('${Routes.people}/${person!.id}');
      case 'similar-pose':
        context.push('${Routes.bodies}?similar=${d.refId}');
      case 'similar-colours':
        context.push('${Routes.bodies}?colours=${d.refId}');
      case 'group-pose':
        await nameGroupPose(context, ref, _mediaIds[_currentIndex]);
      case 'equipment':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                EquipmentPhotoScreen(mediaId: _mediaIds[_currentIndex]),
          ),
        );
      case 'name-pose':
        await nameBodyPose(context, ref, d.refId);
      case 'mark-tattoo':
        await showMarkTattoo(context, ref, d.refId);
      case 'name-outfit':
        await nameBodyOutfit(context, ref, d.refId);
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
      case 'kind':
        await moveToOtherKind(
          context,
          ref,
          fromKind: d.figure,
          faceIds: d.isFace ? [d.refId] : const [],
          bodyIds: d.isFace ? const [] : [d.refId],
        );
    }
  }

  /// The whole file is people, characters, or decided per detection; it is scanned again.
  Future<void> _fileKindMenu(BuildContext context, MediaRow media) async {
    final l10n = AppLocalizations.of(context);
    final corrections = ref.read(kindCorrectionsProvider);
    final current = await corrections.mediaKind(media.id);
    if (!context.mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                l10n.mediaKindTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(l10n.mediaKindNote),
            ),
            const Divider(height: 1),
            for (final (value, label, icon) in [
              ('auto', l10n.mediaKindAuto, Icons.auto_awesome),
              ('person', l10n.mediaKindPeople, Icons.person_outline),
              ('character', l10n.mediaKindCharacters, Icons.draw_outlined),
            ])
              ListTile(
                key: Key('media-kind-$value'),
                leading: Icon(icon),
                title: Text(label),
                trailing: (current ?? 'auto') == value
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    );
    if (choice == null || choice == (current ?? 'auto')) return;
    await corrections.setMediaKind(media.id, choice == 'auto' ? null : choice);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.kindMoved(1))));
    await startScan(ref, enumerate: false);
  }
}

class _PersonContext extends ConsumerWidget {
  const _PersonContext({
    required this.person,
    required this.initiallyExpanded,
    required this.mediaId,
    required this.isPhoto,
    required this.detection,
    required this.onTools,
  });
  final PersonSummary person;
  final bool initiallyExpanded;
  final int mediaId;
  final bool isPhoto;
  final MediaDetection detection;
  final void Function(MediaDetection) onTools;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final models = ref.watch(lorasProvider);
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      leading: PersonAvatar(
        cropPath: person.avatarCropPath,
        radius: 20,
        expandable: false,
      ),
      title: Text(personName(l, person)),
      subtitle: Text(person.kind == 'person' ? 'Person tools and models' : 'Character tools'),
      children: [
        if (person.kind == 'person' && models.isLoading) const LinearProgressIndicator(),
        if (person.kind == 'person' && models.hasError)
          ListTile(
            title: const Text('Could not load models'),
            trailing: TextButton(
              onPressed: () => ref.invalidate(lorasProvider),
              child: const Text('Retry'),
            ),
          ),
        for (final model in models.value ?? const [])
          if (person.kind == 'person' && model.personId == person.id)
            ListTile(
              leading: const Icon(Icons.model_training_outlined),
              title: Text(model.triggerWord),
              subtitle: const Text('Trained model'),
              trailing: isPhoto
                  ? IconButton(
                      tooltip: 'Generate with this reference',
                      icon: const Icon(Icons.auto_awesome_outlined),
                      onPressed: () async {
                        final available = await ref
                            .read(fileStoreProvider)
                            .resolve(model.path)
                            .exists();
                        if (!context.mounted) return;
                        if (available) {
                          context.push(
                            '${Routes.loraGenerate}?id=${model.id}&media=$mediaId',
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Model file unavailable'),
                            ),
                          );
                        }
                      },
                    )
                  : const Icon(Icons.chevron_right),
              onTap: () => context.push('${Routes.lora}/model/${model.id}'),
            ),
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('Open person'),
          onTap: () => context.push('${Routes.people}/${person.id}'),
        ),
        ListTile(
          leading: const Icon(Icons.build_outlined),
          title: const Text('Person tools'),
          onTap: () => onTools(detection),
        ),
      ],
    );
  }
}

class _MediaPageViewItem extends ConsumerStatefulWidget {
  const _MediaPageViewItem({
    super.key,
    required this.mediaId,
    required this.onToggleChrome,
    required this.onZoomChanged,
    required this.showFaces,
    required this.showBodies,
    required this.people,
    required this.onTapBox,
    this.initialTimestampMs,
  });

  final int mediaId;
  final VoidCallback onToggleChrome;
  final ValueChanged<bool> onZoomChanged;
  final bool showFaces;
  final bool showBodies;
  final Map<int, PersonSummary> people;
  final void Function(MediaDetection) onTapBox;
  final int? initialTimestampMs;

  @override
  ConsumerState<_MediaPageViewItem> createState() => _MediaPageViewItemState();
}

class _MediaPageViewItemState extends ConsumerState<_MediaPageViewItem> {
  Future<_Loaded?>? _image;
  String? _assetId;
  final _transform = TransformationController();
  Offset _doubleTap = Offset.zero;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_reportZoom);
  }

  void _reportZoom() =>
      widget.onZoomChanged(_transform.value.getMaxScaleOnAxis() > 1.01);

  @override
  void dispose() {
    _transform.removeListener(_reportZoom);
    _transform.dispose();
    super.dispose();
  }

  Future<_Loaded?> _load(String assetId, int width, int height) async {
    var bytes = await ref.read(mediaLibraryProvider).viewerImage(assetId);
    final fallback = bytes == null;
    bytes ??= await ref
        .read(thumbnailServiceProvider)
        .get(assetId, width: width, height: height);
    if (bytes == null) return null;
    final decoded = await ui.instantiateImageCodec(bytes);
    final frame = await decoded.getNextFrame();
    final loaded = _Loaded(
      bytes,
      frame.image.width,
      frame.image.height,
      fallback: fallback,
    );
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
      error: (_, _) =>
          EmptyState(icon: Icons.photo_outlined, title: l10n.photoGone),
      data: (media) {
        if (media == null) {
          return EmptyState(icon: Icons.photo_outlined, title: l10n.photoGone);
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
          _image = _load(media.assetId, media.width ?? 1, media.height ?? 1);
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
            return Stack(
              children: [
                _AnnotatedPhoto(
                  image: image,
                  onTap: widget.onToggleChrome,
                  onDoubleTapDown: (details) =>
                      _doubleTap = details.localPosition,
                  onDoubleTap: () {
                    _transform.value =
                        _transform.value.getMaxScaleOnAxis() > 1.01
                        ? Matrix4.identity()
                        : (Matrix4.identity()
                            ..translateByDouble(
                              -_doubleTap.dx * 2,
                              -_doubleTap.dy * 2,
                              0,
                              1,
                            )
                            ..scaleByDouble(3, 3, 1, 1));
                  },
                  controller: _transform,
                  detections: [
                    if (!image.fallback && widget.showFaces) ...faces,
                    if (!image.fallback && widget.showBodies) ...bodies,
                  ],
                  people: widget.people,
                  onTapBox: widget.onTapBox,
                ),
                if (image.fallback)
                  const Positioned(
                    bottom: 8,
                    left: 8,
                    child: ColoredBox(
                      color: Colors.black87,
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          'Preview only · original unavailable',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
              ],
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
    required this.onTap,
    required this.onDoubleTap,
    required this.onDoubleTapDown,
    required this.controller,
    required this.detections,
    required this.people,
    required this.onTapBox,
  });

  final _Loaded image;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final GestureTapDownCallback onDoubleTapDown;
  final TransformationController controller;
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
          child: GestureDetector(
            onTap: onTap,
            onDoubleTap: onDoubleTap,
            onDoubleTapDown: onDoubleTapDown,
            child: InteractiveViewer(
              transformationController: controller,
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
                          child: CustomPaint(
                            painter: DetectionBoxPainter(
                              isFace: d.isFace,
                              outline: d.outline,
                              fillColor: d.isFace
                                  ? (d.personId == null
                                        ? Colors.amber.withValues(alpha: 0.10)
                                        : scheme.primary.withValues(
                                            alpha: 0.12,
                                          ))
                                  : Colors.lightBlueAccent.withValues(
                                      alpha: 0.18,
                                    ),
                              borderColor: d.isFace
                                  ? (d.personId == null
                                        ? Colors.amber
                                        : scheme.primary)
                                  : Colors.lightBlueAccent,
                              borderWidth: d.isFace ? 2.5 : 2.0,
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
    this.label,
    this.selectedId,
    required this.onSelect,
    required this.faces,
    required this.people,
    required this.mediaScanned,
    required this.onOpen,
    required this.onEdit,
  });

  final String? label;
  final int? selectedId;
  final void Function(MediaDetection) onSelect;
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
                label ?? l10n.whoIsHere,
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
                                backgroundColor: selectedId == d.id
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer
                                    : null,
                                key: d.personId != null && seen.add(d.personId!)
                                    ? Key('who-${d.personId}')
                                    : Key('who-${d.kind}-${d.refId}'),
                                avatar: ClipOval(
                                  child: CropImage(
                                    path: d.cropPath,
                                    expandable: false,
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
                              IconButton(
                                tooltip: selectedId == d.id
                                    ? 'Target selected'
                                    : 'Select for actions',
                                icon: Icon(
                                  selectedId == d.id
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  size: 18,
                                ),
                                onPressed: () => onSelect(d),
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
