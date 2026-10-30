import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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

/// S06 - one photo with the faces (and optionally bodies) the PC found, drawn as boxes. Tap a box to
/// say who it is, that it is not them, or to open the person. "Who is in this photo" sits underneath.
class MediaScreen extends ConsumerStatefulWidget {
  const MediaScreen({super.key, required this.mediaId});

  final int mediaId;

  @override
  ConsumerState<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends ConsumerState<MediaScreen> {
  Future<_Loaded?>? _image;
  String? _assetId;
  var _showBodies = false;

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
          onRetry: () => ref.invalidate(mediaRowProvider(widget.mediaId)),
        ),
      ),
      data: (media) {
        if (media == null) {
          return Scaffold(
            appBar: AppBar(),
            body: EmptyState(icon: Icons.photo_outlined, title: l10n.photoGone),
          );
        }
        if (media.kind != 'video' && _assetId != media.assetId) {
          _assetId = media.assetId;
          _image = _load(media.assetId);
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
          appBar: AppBar(
            title: Text(
              taken ??
                  (media.kind == 'video' ? l10n.videoTitle : l10n.photoTitle),
            ),
            actions: [
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
            ],
          ),
          body: media.kind == 'video'
              ? VideoMediaView(
                  key: ValueKey(media.assetId),
                  assetId: media.assetId,
                  library: ref.watch(mediaLibraryProvider),
                  detections: detections,
                  people: people,
                  showBodies: _showBodies,
                  onTapBox: (d) => _boxMenu(context, d, people),
                )
              : Column(
                  children: [
                    Expanded(
                      child: FutureBuilder<_Loaded?>(
                        future: _image,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
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
                            detections: [...faces, if (_showBodies) ...bodies],
                            people: people,
                            onTapBox: (d) => _boxMenu(context, d, people),
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
                    ),
                  ],
                ),
        );
      },
    );
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
                            border: Border.all(
                              width: d.isFace ? 2.5 : 1.5,
                              color: d.isFace
                                  ? (d.personId == null
                                        ? Colors.amber
                                        : scheme.primary)
                                  : Colors.lightBlueAccent,
                            ),
                            borderRadius: BorderRadius.circular(
                              d.isFace ? 6 : 2,
                            ),
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

class _WhoIsHere extends StatelessWidget {
  const _WhoIsHere({
    required this.faces,
    required this.people,
    required this.mediaScanned,
  });

  final List<MediaDetection> faces;
  final Map<int, PersonSummary> people;
  final bool mediaScanned;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ids = <int>{
      for (final f in faces)
        if (f.personId != null) f.personId!,
    };
    final unsorted = faces.where((f) => f.personId == null).length;
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
                      for (final id in ids)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            key: Key('who-$id'),
                            avatar: PersonAvatar(
                              cropPath: people[id]?.avatarCropPath,
                              radius: 12,
                            ),
                            label: Text(personNameOf(l10n, id, people)),
                            onPressed: () =>
                                context.push('${Routes.people}/$id'),
                          ),
                        ),
                      if (unsorted > 0)
                        Chip(label: Text(l10n.unsortedFacesInPhoto(unsorted))),
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
