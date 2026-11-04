import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/router.dart';
import '../../data/db/app_database.dart';
import '../../data/media/media_library.dart';
import '../../data/platform/native_video_player.dart';
import '../../data/repositories/media_queries.dart';
import '../../data/repositories/people_repository.dart';
import '../../domain/actions/action_context.dart';
import '../../domain/actions/action_id.dart';
import '../../domain/actions/entity_ref.dart';
import '../../domain/corrections/correction_target.dart';
import '../../domain/corrections/correction_verb.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../../ui/actions/entity_action_sheet.dart';
import '../bodies/body_naming.dart';
import '../bodies/equipment_screens.dart';
import '../bodies/group_pose_screens.dart';
import '../inspector/media_inspector.dart';
import '../marks/mark_tattoo.dart';
import '../people/people_actions.dart' show moveToOtherKind;
import '../scan/redetect_flow.dart';
import '../scan/scan_progress_card.dart' show startScan;
import '../shared/empty_state.dart';
import '../shared/image_preview.dart';
import '../shared/person_picker.dart';
import '../video_actions/video_actions_screen.dart';
import '../inspector/targeted_detect_sheet.dart';
import '../../data/api/dtos/analyze.dart';
import '../../ui/sheets/undo_snackbar.dart';
import 'layers_popover.dart';
import 'media_chrome.dart';
import 'media_page_item.dart';
import 'roi_selection_overlay.dart';
import 'detection_actions.dart';

class MediaCollectionContext {
  const MediaCollectionContext({
    required this.ids,
    this.loadMore,
    this.source = 'library',
  });
  final List<int> ids;
  final Future<List<int>> Function()? loadMore;
  final String source;
}

/// L3 / P5b — MediaViewerScreen: Full screen viewer for photos and videos with layers,
/// horizontal swiping, auto-play zero-copy video, gesture controls, and EntityActionSheet.
class MediaViewerScreen extends ConsumerStatefulWidget {
  const MediaViewerScreen({
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
  ConsumerState<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends ConsumerState<MediaViewerScreen> {
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
  var _layers = const ViewerLayers(faces: false, bodies: false);
  var _activeRoiMode = false;
  var _activeRoiKind = 'area';

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

  Future<void> _openNativeVideoPlayer(
    BuildContext context,
    MediaRow media,
  ) async {
    try {
      final library = ref.read(mediaLibraryProvider);
      String? uri;
      if (library is VideoMediaLibrary) {
        uri = await (library as VideoMediaLibrary).videoUri(media.assetId);
      }
      if (uri == null || uri.isEmpty) {
        if (library is VideoMediaLibrary) {
          final file = await (library as VideoMediaLibrary).videoFile(
            media.assetId,
          );
          uri = file?.uri.toString();
        }
      }
      if (uri == null || uri.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video unavailable to open')),
        );
        return;
      }
      final launched = await NativeVideoPlayer.openVideo(
        uri,
        title: media.assetId,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open external player')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to launch player: $e')));
    }
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

  void _showStudioMenu(BuildContext context, MediaRow media) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.face_retouching_natural),
              title: const Text('Reface'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('${Routes.studioReface}?target=media:${media.id}');
              },
            ),
            if (media.kind == 'photo') ...[
              ListTile(
                leading: const Icon(Icons.checkroom_outlined),
                title: const Text('Restyle'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('${Routes.restyle}?media=${media.id}');
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('Add to training dataset'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('${Routes.studioDatasetsNew}?media=${media.id}');
                },
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('Generate with this reference'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('${Routes.studioGenerate}?media=${media.id}');
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showTools(BuildContext context, MediaRow media) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
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
                  context.push(
                    '${Routes.studioReface}?target=media:${media.id}',
                  );
                },
              ),
              if (media.kind == 'photo') ...[
                ListTile(
                  leading: const Icon(Icons.checkroom_outlined),
                  title: const Text('Restyle'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.push('${Routes.restyle}?media=${media.id}');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Add to training dataset'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.push(
                      '${Routes.studioDatasetsNew}?media=${media.id}',
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showDetectionActions(
    BuildContext context,
    MediaDetection d,
    Map<int, PersonSummary> people,
  ) {
    final EntityRef entity;
    final String title;
    if (d.isFace) {
      entity = FaceEntityRef(
        d.refId,
        mediaId: widget.mediaId,
        personId: d.personId,
      );
      title = 'Face actions';
    } else if (d.isBody) {
      entity = BodyEntityRef(
        d.refId,
        mediaId: widget.mediaId,
        personId: d.personId,
      );
      title = 'Body actions';
    } else if (d.isArea) {
      entity = SensitiveRegionEntityRef(
        d.refId,
        mediaId: widget.mediaId,
        bodyId: d.personId,
      );
      title = d.label != null && d.label!.isNotEmpty
          ? d.label!
          : 'Area actions';
    } else {
      entity = EquipmentEntityRef(
        d.refId,
        mediaId: widget.mediaId,
        bodyId: d.personId,
        name: d.label,
      );
      title = d.label != null && d.label!.isNotEmpty
          ? d.label!
          : 'Equipment actions';
    }

    final actionContext = ActionContext(
      isMultiSelect: false,
      isVideo: d.frameNumber != null,
      hasPerson: d.personId != null,
      isPcConnected: ref.read(mobileApiProvider) != null,
    );

    EntityActionSheet.show(
      context: context,
      entity: entity,
      supportedActions: detectionActionsFor(d),
      title: title,
      actionContext: actionContext,
      onActionSelected: (id) =>
          _dispatchDetectionAction(context, d, id, people),
    );
  }

  Future<void> _dispatchDetectionAction(
    BuildContext context,
    MediaDetection d,
    ActionId action,
    Map<int, PersonSummary> people,
  ) async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(peopleRepositoryProvider);

    final activeId = _mediaIds[_currentIndex];
    switch (action) {
      case ActionId.open:
        if (d.personId != null) {
          context.push('${Routes.people}/${d.personId}');
        }
      case ActionId.assignPerson:
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
      case ActionId.notThisPerson:
        if (d.personId != null) {
          if (d.isFace) {
            await repo.rejectFaces([d.refId], fromPersonId: d.personId!);
          } else {
            await repo.rejectBody(d.refId, personId: d.personId!);
          }
        }
      case ActionId.changeKind:
        await moveToOtherKind(
          context,
          ref,
          fromKind: d.figure,
          faceIds: d.isFace ? [d.refId] : const [],
          bodyIds: d.isFace ? const [] : [d.refId],
        );
      case ActionId.refaceThis:
        context.push(
          '${Routes.studioReface}?target=media:$activeId,det:${d.id}',
        );
      case ActionId.restyleThis:
        context.push('${Routes.restyle}?media=$activeId&target=${d.id}');
      case ActionId.similarPose:
        context.push('${Routes.bodies}?similar=${d.refId}');
      case ActionId.similarColours:
        context.push('${Routes.bodies}?colours=${d.refId}');
      case ActionId.namePose:
        await nameBodyPose(context, ref, d.refId);
      case ActionId.nameOutfit:
        await nameBodyOutfit(context, ref, d.refId);
      case ActionId.nameGroupPose:
        await nameGroupPose(context, ref, activeId);
      case ActionId.markTattoo:
        await showMarkTattoo(context, ref, d.refId);
      case ActionId.boxEquipment:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EquipmentPhotoScreen(mediaId: activeId),
          ),
        );
      case ActionId.delete:
        if (!d.isFace) return;
        final ok = await confirm(
          context,
          title: l10n.deleteFacesTitle(1),
          body: l10n.deleteFacesBody,
          confirmLabel: l10n.delete,
          cancelLabel: l10n.cancel,
          destructive: true,
        );
        if (ok) await repo.deleteFaces([d.refId]);
      case ActionId.notARealThing:
        final service = ref.read(correctionServiceProvider);
        final CorrectionTarget target = d.isFace
            ? FaceLinkTarget(
                faceId: d.refId,
                mediaId: activeId,
                personId: d.personId,
              )
            : d.isBody
            ? BodyLinkTarget(
                bodyId: d.refId,
                mediaId: activeId,
                personId: d.personId,
              )
            : d.isArea
            ? SensitiveRegionTarget(regionId: d.refId, mediaId: activeId)
            : EquipmentOwnerTarget(objectId: d.refId, mediaId: activeId);
        try {
          final result = await service.apply(
            target,
            CorrectionVerb.notARealThing,
          );
          if (!mounted) return;
          UndoSnackbar.show(
            context: this.context,
            message: 'Detection excluded',
            onUndo: () async {
              await service.undo(result.undoToken);
            },
          );
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(this.context).showSnackBar(
              const SnackBar(
                content: Text("Couldn't update this detection. Try again."),
              ),
            );
          }
        }
      default:
        break;
    }
  }

  void _showDetails(
    BuildContext context,
    MediaRow media,
    List<MediaDetection> faces,
    List<MediaDetection> bodies,
    List<MediaDetection> areas,
    List<MediaDetection> equipment,
    Map<int, PersonSummary> people,
  ) {
    setState(() => _detailsOpen = true);
    MediaInspector.show(
      context: context,
      media: media,
      faces: faces,
      bodies: bodies,
      areas: areas,
      equipment: equipment,
      people: people,
      selectedDetectionId: _selectedDetectionId,
      onSelectDetection: (d) => setState(() => _selectedDetectionId = d.id),
      onAction: (d, action) =>
          _dispatchDetectionAction(context, d, action, people),
      durationMs: media.durationMs,
      onDetect: () => _startTargetedDetect(context, media),
    ).whenComplete(() {
      if (mounted) setState(() => _detailsOpen = false);
    });
  }

  void _startTargetedDetect(BuildContext context, MediaRow media) {
    TargetedDetectSheet.show(
      context: context,
      onStart: (kind, isRoiMode) {
        if (isRoiMode) {
          setState(() {
            _activeRoiKind = kind;
            _activeRoiMode = true;
          });
        } else {
          _submitTargetedDetect(media, kind, null);
        }
      },
    );
  }

  Future<void> _submitTargetedDetect(
    MediaRow media,
    String kind,
    BBox? roi,
  ) async {
    setState(() => _activeRoiMode = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Analyzing with high accuracy...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final bytes = await ref
          .read(mediaLibraryProvider)
          .viewerImage(media.assetId);
      if (bytes == null || !mounted) return;
      final api = ref.read(mobileApiProvider);
      if (api == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connect to your PC first to run AI detection'),
          ),
        );
        return;
      }
      final response = await api.analyzeTargeted(
        bytes,
        targetKind: kind,
        roi: roi,
      );

      if (!mounted) return;
      final first = response.detections.isNotEmpty
          ? response.detections.first
          : null;
      final targetBBox =
          first?.bbox ?? roi ?? const BBox(x: 0.25, y: 0.25, w: 0.5, h: 0.5);

      TargetedNameSheet.show(
        context: context,
        kind: kind,
        bbox: targetBBox,
        initialName: first?.label ?? '',
        isVideo: media.kind == 'video',
        onSave: (name, personId, scope) async {
          final entry = TargetedEntry(
            mediaId: media.id,
            kind: kind,
            bbox: targetBBox,
            label: name.isNotEmpty ? name : (first?.label ?? 'custom'),
            personId: personId,
            outline: first?.outline,
            keypoints: first?.keypoints,
            scope: scope,
          );
          final res = await ref
              .read(targetedDetectionServiceProvider)
              .apply(entry);
          if (!mounted) return;
          setState(() {
            if (kind == 'area') {
              _layers = _layers.copyWith(areas: true);
            } else if (kind == 'object') {
              _layers = _layers.copyWith(equipment: true);
            } else if (kind == 'body') {
              _layers = _layers.copyWith(bodies: true);
            } else if (kind == 'face') {
              _layers = _layers.copyWith(faces: true);
            }
          });
          UndoSnackbar.show(
            context: context,
            message: 'Saved $kind detection',
            onUndo: () =>
                ref.read(targetedDetectionServiceProvider).undo(res.undoToken),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Targeted detection failed: $e')));
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
      for (final p in [
        ...ref.watch(peopleProvider).value ?? const <PersonSummary>[],
        ...ref.watch(charactersProvider).value ?? const <PersonSummary>[],
      ])
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
            if (d.isBody) d,
        ];
        final areas = [
          for (final d in detections)
            if (d.isArea) d,
        ];
        final equipment = [
          for (final d in detections)
            if (d.isEquipment) d,
        ];

        final availability = LayerAvailability(
          hasFaces: faces.isNotEmpty,
          hasBodies: bodies.isNotEmpty,
          hasAreas: areas.isNotEmpty,
          hasEquipment: equipment.isNotEmpty,
        );

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: PreferredSize(
            preferredSize: Size.fromHeight(_chromeVisible ? kToolbarHeight : 0),
            child: MediaChromeTopBar(
              media: media,
              title:
                  taken ??
                  (media.kind == 'video' ? l10n.videoTitle : l10n.photoTitle),
              layers: _layers,
              availability: availability,
              visible: _chromeVisible,
              onLayersChanged: (updated) => setState(() => _layers = updated),
              onOpenNativePlayer: () => _openNativeVideoPlayer(context, media),
              onRedetect: () => redetectFlow(context, ref, mediaId: media.id),
              onChangeFileKind: () => _fileKindMenu(context, media),
              onLens: () => _searchGoogleLens(context, media),
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
                          _showDetails(
                            context,
                            media,
                            faces,
                            bodies,
                            areas,
                            equipment,
                            people,
                          );
                        }
                        if (_pointerCount == 0) _swipeStart = null;
                      },
                      onPointerCancel: (_) {
                        _pointerCount = 0;
                        _swipeStart = null;
                        _multiTouch = true;
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          PageView.builder(
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
                              return MediaPageViewItem(
                                key: ValueKey(itemMediaId),
                                mediaId: itemMediaId,
                                isActive: i == _currentIndex,
                                layers: _layers,
                                people: people,
                                onToggleChrome: () => setState(
                                  () => _chromeVisible = !_chromeVisible,
                                ),
                                onZoomChanged: (zoomed) {
                                  if (_zoomed != zoomed &&
                                      itemMediaId == _mediaIds[_currentIndex]) {
                                    setState(() => _zoomed = zoomed);
                                  }
                                },
                                onTapBox: (d) =>
                                    _showDetectionActions(context, d, people),
                                initialTimestampMs:
                                    (itemMediaId == widget.mediaId)
                                    ? widget.initialTimestampMs
                                    : null,
                                onOpenNativePlayer: () async {
                                  final row = await ref
                                      .read(libraryRepositoryProvider)
                                      .mediaById(itemMediaId);
                                  if (row != null && context.mounted) {
                                    _openNativeVideoPlayer(context, row);
                                  }
                                },
                              );
                            },
                          ),
                          if (_activeRoiMode)
                            LayoutBuilder(
                              builder: (context, constraints) =>
                                  RoiSelectionOverlay(
                                    fittedSize: Size(
                                      constraints.maxWidth,
                                      constraints.maxHeight,
                                    ),
                                    onChanged: (_) {},
                                    onConfirm: (bbox) => _submitTargetedDetect(
                                      media,
                                      _activeRoiKind,
                                      bbox,
                                    ),
                                    onCancel: () =>
                                        setState(() => _activeRoiMode = false),
                                  ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              MediaChromeBottomBar(
                media: media,
                visible: _chromeVisible,
                onShare: () => _shareOriginal(context, media),
                onStudio: () => _showStudioMenu(context, media),
                onTools: () => _showTools(context, media),
                onDetect: () => _startTargetedDetect(context, media),
                onDetails: () => _showDetails(
                  context,
                  media,
                  faces,
                  bodies,
                  areas,
                  equipment,
                  people,
                ),
                onLens: () => _searchGoogleLens(context, media),
                onOpenNativePlayer: () =>
                    _openNativeVideoPlayer(context, media),
              ),
            ],
          ),
        );
      },
    );
  }
}
