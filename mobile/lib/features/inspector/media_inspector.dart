import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/router.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/media_queries.dart';
import '../../data/repositories/people_repository.dart';
import '../../domain/actions/action_id.dart';
import '../../domain/actions/entity_ref.dart';
import '../../domain/corrections/correction_scope.dart';
import '../../domain/corrections/correction_target.dart';
import '../../domain/corrections/correction_verb.dart';
import '../../domain/corrections/corrections_queries.dart';
import '../../library_providers.dart';
import '../../ui/actions/entity_action_sheet.dart';
import '../../ui/sheets/undo_snackbar.dart';
import '../bodies/group_pose_screens.dart';
import '../marks/mark_tattoo.dart';
import '../scan/redetect_flow.dart';
import '../scan/scan_progress_card.dart' show startScan;
import '../shared/crop_image.dart';
import '../shared/person_picker.dart';
import 'correction_sheet.dart';
import 'video_track_strip.dart';

/// L3a / P5c — MediaInspector: All-in-one panel for a photo or video
/// containing Peek bar, Detections, Links, Activities/Marks, Studio actions, and File info.
class MediaInspector extends ConsumerStatefulWidget {
  const MediaInspector({
    super.key,
    required this.media,
    required this.faces,
    required this.bodies,
    required this.people,
    this.selectedDetectionId,
    this.onSelectDetection,
    this.onAction,
    this.currentPositionMs,
    this.durationMs,
    this.onSeek,
  });

  final MediaRow media;
  final List<MediaDetection> faces;
  final List<MediaDetection> bodies;
  final Map<int, PersonSummary> people;
  final int? selectedDetectionId;
  final ValueChanged<MediaDetection>? onSelectDetection;
  final void Function(MediaDetection d, ActionId action)? onAction;
  final int? currentPositionMs;
  final int? durationMs;
  final ValueChanged<int>? onSeek;

  static Future<void> show({
    required BuildContext context,
    required MediaRow media,
    required List<MediaDetection> faces,
    required List<MediaDetection> bodies,
    required Map<int, PersonSummary> people,
    int? selectedDetectionId,
    ValueChanged<MediaDetection>? onSelectDetection,
    void Function(MediaDetection d, ActionId action)? onAction,
    int? currentPositionMs,
    int? durationMs,
    ValueChanged<int>? onSeek,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (context, scrollController) => MediaInspectorContent(
          media: media,
          faces: faces,
          bodies: bodies,
          people: people,
          scrollController: scrollController,
          selectedDetectionId: selectedDetectionId,
          onSelectDetection: onSelectDetection,
          onAction: onAction,
          currentPositionMs: currentPositionMs,
          durationMs: durationMs,
          onSeek: onSeek,
        ),
      ),
    );
  }

  @override
  ConsumerState<MediaInspector> createState() => _MediaInspectorState();
}

class _MediaInspectorState extends ConsumerState<MediaInspector> {
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      key: const Key('media-inspector'),
      initialChildSize: 0.12,
      minChildSize: 0.08,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: const [0.12, 0.6, 0.92],
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: MediaInspectorContent(
          media: widget.media,
          faces: widget.faces,
          bodies: widget.bodies,
          people: widget.people,
          scrollController: controller,
          selectedDetectionId: widget.selectedDetectionId,
          onSelectDetection: widget.onSelectDetection,
          onAction: widget.onAction,
          currentPositionMs: widget.currentPositionMs,
          durationMs: widget.durationMs,
          onSeek: widget.onSeek,
        ),
      ),
    );
  }
}

class MediaInspectorContent extends ConsumerStatefulWidget {
  const MediaInspectorContent({
    super.key,
    required this.media,
    required this.faces,
    required this.bodies,
    required this.people,
    required this.scrollController,
    this.selectedDetectionId,
    this.onSelectDetection,
    this.onAction,
    this.currentPositionMs,
    this.durationMs,
    this.onSeek,
  });

  final MediaRow media;
  final List<MediaDetection> faces;
  final List<MediaDetection> bodies;
  final Map<int, PersonSummary> people;
  final ScrollController scrollController;
  final int? selectedDetectionId;
  final ValueChanged<MediaDetection>? onSelectDetection;
  final void Function(MediaDetection d, ActionId action)? onAction;
  final int? currentPositionMs;
  final int? durationMs;
  final ValueChanged<int>? onSeek;

  @override
  ConsumerState<MediaInspectorContent> createState() =>
      _MediaInspectorContentState();
}

class _MediaInspectorContentState extends ConsumerState<MediaInspectorContent> {
  List<MediaLinkItem> _links = [];
  bool _loadingLinks = true;

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  @override
  void didUpdateWidget(MediaInspectorContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.id != widget.media.id) {
      _loadLinks();
    }
  }

  Future<void> _loadLinks() async {
    try {
      final queries = ref.read(correctionsQueriesProvider);
      final list = await queries.linksForMedia(widget.media.id);
      if (mounted) {
        setState(() {
          _links = list;
          _loadingLinks = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingLinks = false);
    }
  }

  Color _chipBorderColor(ThemeData theme, MediaDetection d) {
    if (d.personId == null) {
      return Colors.amber; // unassigned
    }
    if (d.linkMethod == 'manual' || d.linkMethod == null && d.isFace) {
      return theme.colorScheme.primary; // manual / verified
    }
    return Colors.teal; // auto
  }

  Future<void> _openCorrectionSheet(
    BuildContext context,
    MediaDetection d,
  ) async {
    final target = d.isFace
        ? FaceLinkTarget(
            faceId: d.refId,
            mediaId: widget.media.id,
            personId: d.personId,
          )
        : BodyLinkTarget(
            bodyId: d.refId,
            mediaId: widget.media.id,
            personId: d.personId,
          );

    final personName = d.personId != null && widget.people[d.personId] != null
        ? widget.people[d.personId]!.name
        : null;

    final updated = await CorrectionSheet.show(
      context: context,
      target: target,
      cropPath: d.cropPath,
      title: d.isFace ? 'Face detection' : 'Body detection',
      subtitle: personName != null
          ? 'Linked to $personName (${d.linkMethod ?? "auto"})'
          : 'Unassigned detection',
      isVideo: widget.media.kind == 'video',
      onApplied: () => _loadLinks(),
    );

    if (updated == true) {
      _loadLinks();
    }
  }

  Future<void> _reassignFaceDirect(
    BuildContext context,
    MediaDetection d,
  ) async {
    final choice = await pickPerson(
      context,
      excludePersonId: d.personId,
      allowNew: true,
      kind: d.figure,
    );
    if (choice == null || !mounted) return;
    final repo = ref.read(peopleRepositoryProvider);
    final target = await resolveChoice(
      ref,
      choice,
      faceIds: [d.refId],
      kind: d.figure,
    );
    if (!choice.isNew) {
      await repo.assignFaces([d.refId], target);
    }
  }

  Future<void> _confirmLink(MediaLinkItem link) async {
    final service = ref.read(correctionServiceProvider);
    CorrectionTarget target;
    if (link.type == 'body_person') {
      target = BodyLinkTarget(
        bodyId: link.elementId,
        mediaId: widget.media.id,
        personId: link.targetId,
      );
    } else if (link.type == 'equipment_owner') {
      target = EquipmentOwnerTarget(
        objectId: link.elementId,
        mediaId: widget.media.id,
        bodyId: link.targetId,
      );
    } else {
      return;
    }

    final result = await service.apply(
      target,
      CorrectionVerb.confirm,
      scope: widget.media.kind == 'video'
          ? CorrectionScope.track
          : CorrectionScope.single,
    );

    if (!mounted) return;
    _loadLinks();

    UndoSnackbar.show(
      context: context,
      message: 'Confirmed link (${result.affectedCount})',
      onUndo: () async {
        await service.undo(result.undoToken);
        _loadLinks();
      },
    );
  }

  void _showDetectionMenu(BuildContext context, MediaDetection d) {
    EntityRef entityRef;
    if (d.isFace) {
      entityRef = FaceEntityRef(
        d.refId,
        mediaId: widget.media.id,
        personId: d.personId,
      );
    } else {
      entityRef = BodyEntityRef(
        d.refId,
        mediaId: widget.media.id,
        personId: d.personId,
      );
    }

    EntityActionSheet.show(
      context: context,
      entity: entityRef,
      onActionSelected: (action) {
        widget.onAction?.call(d, action);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allDetections = [...widget.faces, ...widget.bodies];
    final isVideo = widget.media.kind == 'video';

    final groupedByPerson = <int, List<MediaDetection>>{};
    final unassigned = <MediaDetection>[];

    for (final d in allDetections) {
      if (d.personId != null) {
        groupedByPerson.putIfAbsent(d.personId!, () => []).add(d);
      } else {
        unassigned.add(d);
      }
    }

    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.zero,
      children: [
        // 0. Peek Bar Header
        Container(
          key: const Key('inspector-peek-bar'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Inspector',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${allDetections.length} item${allDetections.length == 1 ? "" : "s"}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Peek Chips Row
              if (allDetections.isEmpty)
                Text(
                  widget.media.scanStatus == 'done'
                      ? 'No items detected'
                      : 'Not analyzed yet',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final d in allDetections) ...[
                        GestureDetector(
                          key: Key('peek-chip-${d.id}'),
                          onTap: () {
                            widget.onSelectDetection?.call(d);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: d.id == widget.selectedDetectionId
                                    ? theme.colorScheme.primary
                                    : _chipBorderColor(theme, d),
                                width: d.id == widget.selectedDetectionId
                                    ? 2.5
                                    : 1.5,
                              ),
                            ),
                            child: ClipOval(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CropImage(
                                  path: d.cropPath,
                                  placeholderIcon: d.isFace
                                      ? Icons.face_outlined
                                      : Icons.accessibility_new,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),

        // Video Timeline Track Strip
        if (isVideo && widget.durationMs != null && widget.durationMs! > 0) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: VideoTrackStrip(
              durationMs: widget.durationMs!,
              currentPositionMs: widget.currentPositionMs ?? 0,
              detections: allDetections,
              people: widget.people,
              selectedDetectionId: widget.selectedDetectionId,
              onSeek: widget.onSeek,
              onSelect: widget.onSelectDetection,
            ),
          ),
        ],

        const Divider(),

        // SECTION 1: Who is here (اللي في الصورة)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Who is here',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (groupedByPerson.isNotEmpty || unassigned.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in groupedByPerson.entries)
                  ActionChip(
                    key: Key('who-${entry.key}'),
                    avatar: CircleAvatar(
                      radius: 12,
                      child: Text(
                        widget.people[entry.key]?.name?.isNotEmpty == true
                            ? widget.people[entry.key]!.name![0]
                            : '?',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    label: Text(
                      widget.people[entry.key]?.name ?? 'Person #${entry.key}',
                    ),
                    onPressed: () =>
                        context.push('${Routes.people}/${entry.key}'),
                  ),
                if (unassigned.isNotEmpty)
                  const ActionChip(label: Text('Unknown'), onPressed: null),
              ],
            ),
          ),
        if (widget.media.scanStatus != 'done')
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('This photo has not been scanned yet.'),
          )
        else if (widget.faces.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('No faces were found in this photo.'),
          ),
        if (allDetections.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('No detections in this media'),
          )
        else ...[
          // Persons groups
          for (final entry in groupedByPerson.entries) ...[
            Builder(
              builder: (context) {
                final person = widget.people[entry.key];
                final name = person?.name ?? 'Person #${entry.key}';
                final primaryDetection = entry.value.first;
                return ExpansionTile(
                  key: Key('inspector-person-${entry.key}'),
                  initiallyExpanded: true,
                  leading: CircleAvatar(
                    radius: 16,
                    child: Text(name.isNotEmpty ? name[0] : '?'),
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: const Text('Open person'),
                      trailing: IconButton(
                        tooltip: 'Select for actions',
                        icon: const Icon(Icons.more_horiz),
                        onPressed: () =>
                            _showDetectionMenu(context, primaryDetection),
                      ),
                      onTap: () =>
                          context.push('${Routes.people}/${entry.key}'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.build_outlined),
                      title: const Text('Person tools'),
                      onTap: () =>
                          _showDetectionMenu(context, primaryDetection),
                    ),
                    for (final d in entry.value)
                      ListTile(
                        key: Key('inspector-detection-${d.id}'),
                        leading: SizedBox(
                          width: 40,
                          height: 40,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: CropImage(
                              path: d.cropPath,
                              placeholderIcon: d.isFace
                                  ? Icons.face_outlined
                                  : Icons.accessibility_new,
                            ),
                          ),
                        ),
                        title: Text(d.isFace ? 'Face' : 'Body'),
                        subtitle: Text(
                          d.linkMethod != null
                              ? 'Via ${d.linkMethod}'
                              : (d.isFace ? 'Direct match' : 'Auto'),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: Key(
                                d.isFace
                                    ? 'who-edit-${d.refId}'
                                    : 'inspect-correct-${d.id}',
                              ),
                              icon: const Icon(Icons.edit_note, size: 20),
                              tooltip: 'Correct',
                              onPressed: () {
                                if (d.isFace) {
                                  _reassignFaceDirect(context, d);
                                } else {
                                  _openCorrectionSheet(context, d);
                                }
                              },
                            ),
                            IconButton(
                              key: Key('inspect-more-${d.id}'),
                              icon: const Icon(Icons.more_vert, size: 20),
                              onPressed: () => _showDetectionMenu(context, d),
                            ),
                          ],
                        ),
                        onTap: () => widget.onSelectDetection?.call(d),
                      ),
                  ],
                );
              },
            ),
          ],

          // Unassigned detections
          if (unassigned.isNotEmpty)
            ExpansionTile(
              key: const Key('inspector-unassigned-group'),
              initiallyExpanded: true,
              leading: const CircleAvatar(
                radius: 16,
                backgroundColor: Colors.amber,
                child: Icon(
                  Icons.help_outline,
                  color: Colors.black87,
                  size: 18,
                ),
              ),
              title: const Text(
                'Unassigned',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              children: [
                for (final d in unassigned)
                  ListTile(
                    key: Key('inspector-detection-${d.id}'),
                    leading: SizedBox(
                      width: 40,
                      height: 40,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: CropImage(
                          path: d.cropPath,
                          placeholderIcon: d.isFace
                              ? Icons.face_outlined
                              : Icons.accessibility_new,
                        ),
                      ),
                    ),
                    title: Text(
                      d.isFace ? 'Unassigned face' : 'Unassigned body',
                    ),
                    subtitle: const Text('Needs decision'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton.tonal(
                          key: Key(
                            d.isFace
                                ? 'who-edit-${d.refId}'
                                : 'inspect-correct-${d.id}',
                          ),
                          onPressed: () {
                            if (d.isFace) {
                              _reassignFaceDirect(context, d);
                            } else {
                              _openCorrectionSheet(context, d);
                            }
                          },
                          child: const Text('Assign'),
                        ),
                        IconButton(
                          key: Key('inspect-more-${d.id}'),
                          icon: const Icon(Icons.more_vert, size: 20),
                          onPressed: () => _showDetectionMenu(context, d),
                        ),
                      ],
                    ),
                    onTap: () => widget.onSelectDetection?.call(d),
                  ),
              ],
            ),
        ],

        const Divider(),

        // SECTION 2: Links (الروابط)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Links',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (_loadingLinks)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: LinearProgressIndicator(),
          )
        else if (_links.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('No active links for this media'),
          )
        else
          for (final link in _links)
            ListTile(
              key: Key('inspector-link-${link.elementId}'),
              leading: const Icon(Icons.link),
              title: Text(
                '${link.type == "body_person" ? "Body" : "Equipment"} #${link.elementId} → ${link.targetLabel}',
              ),
              subtitle: link.methodLabel != null
                  ? Text('Via ${link.methodLabel}')
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    key: Key('link-confirm-${link.elementId}'),
                    onPressed: () => _confirmLink(link),
                    child: const Text('Confirm'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    key: Key('link-correct-${link.elementId}'),
                    onPressed: () {
                      final d = widget.bodies
                          .where((b) => b.refId == link.elementId)
                          .firstOrNull;
                      if (d != null) {
                        _openCorrectionSheet(context, d);
                      }
                    },
                    child: const Text('Correct'),
                  ),
                ],
              ),
            ),

        const Divider(),

        // SECTION 3: Activities & Marks (الأنشطة والوشوم)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Activities & Marks',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ListTile(
          key: const Key('inspect-mark-tattoo'),
          leading: const Icon(Icons.draw_outlined),
          title: const Text('Mark tattoo'),
          subtitle: const Text('Save tattoo patch anchored to body keypoints'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final activeBody = widget.bodies.firstOrNull;
            if (activeBody != null) {
              await showMarkTattoo(context, ref, activeBody.refId);
            }
          },
        ),
        if (widget.bodies.length >= 2)
          ListTile(
            key: const Key('inspect-group-pose'),
            leading: const Icon(Icons.groups_outlined),
            title: const Text('Name group pose'),
            subtitle: const Text('Define interaction between multiple people'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await nameGroupPose(context, ref, widget.media.id);
            },
          ),

        const Divider(),

        // SECTION 4: Create (إنشاء)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Create with AI',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              key: const Key('inspect-create-reface'),
              avatar: const Icon(Icons.face_retouching_natural, size: 18),
              label: const Text('Reface'),
              onPressed: () {
                context.push(
                  '${Routes.studioReface}?target=media:${widget.media.id}',
                );
              },
            ),
            ActionChip(
              key: const Key('inspect-create-restyle'),
              avatar: const Icon(Icons.checkroom_outlined, size: 18),
              label: const Text('Restyle'),
              onPressed: isVideo
                  ? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Restyle is not supported for video frames',
                          ),
                        ),
                      );
                    }
                  : () {
                      context.push(
                        '${Routes.restyle}?media=${widget.media.id}',
                      );
                    },
            ),
            if (widget.bodies.isNotEmpty) ...[
              ActionChip(
                key: const Key('inspect-create-similar-pose'),
                avatar: const Icon(Icons.accessibility_new, size: 18),
                label: const Text('Similar pose'),
                onPressed: () {
                  final bodyId = widget.bodies.first.refId;
                  context.push('${Routes.bodies}?similar=$bodyId');
                },
              ),
              ActionChip(
                key: const Key('inspect-create-similar-colours'),
                avatar: const Icon(Icons.palette_outlined, size: 18),
                label: const Text('Similar colours'),
                onPressed: () {
                  final bodyId = widget.bodies.first.refId;
                  context.push('${Routes.bodies}?colours=$bodyId');
                },
              ),
            ],
            ActionChip(
              key: const Key('inspect-create-dataset'),
              avatar: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Add to dataset'),
              onPressed: () {
                context.push(
                  '${Routes.studioDatasetsNew}?mediaId=${widget.media.id}',
                );
              },
            ),
          ],
        ),

        const Divider(),

        // SECTION 5: File Info (معلومات الملف)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'File info',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ListTile(
          leading: Icon(
            isVideo ? Icons.videocam_outlined : Icons.image_outlined,
          ),
          title: Text(isVideo ? 'Video file' : 'Photo file'),
          subtitle: Text(
            [
              if (widget.media.takenAt != null && widget.media.takenAt! > 0)
                DateFormat.yMMMd().add_Hm().format(
                  DateTime.fromMillisecondsSinceEpoch(widget.media.takenAt!),
                ),
              if (widget.media.width != null && widget.media.height != null)
                '${widget.media.width} × ${widget.media.height}',
              widget.media.scanStatus == 'done' ? 'Analyzed' : 'Not analyzed',
            ].join(' · '),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('inspect-redetect'),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Redetect'),
                  onPressed: () =>
                      redetectFlow(context, ref, mediaId: widget.media.id),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('inspect-analyze-now'),
                  icon: const Icon(Icons.document_scanner),
                  label: const Text('Analyze now'),
                  onPressed: () => startScan(ref),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
