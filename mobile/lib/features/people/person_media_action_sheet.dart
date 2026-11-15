import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/router.dart';
import '../../data/repositories/media_queries.dart';
import '../../data/repositories/people_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../ui/actions/action_section.dart';
import '../../ui/scaffolds/sheet_scaffold.dart';
import '../shared/crop_image.dart';
import '../shared/person_picker.dart';
import 'people_actions.dart';

/// Shows the context-aware Long Press action sheet for a photo in a person's / character's album.
Future<void> showPersonMediaActionSheet(
  BuildContext context, {
  required PersonSummary person,
  required MediaListItem item,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (_) => PersonMediaActionSheet(person: person, item: item),
  );
}

class PersonMediaActionSheet extends ConsumerWidget {
  const PersonMediaActionSheet({
    super.key,
    required this.person,
    required this.item,
  });

  final PersonSummary person;
  final MediaListItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final queries = ref.watch(mediaQueriesProvider);

    return StreamBuilder<List<MediaDetection>>(
      stream: queries.watchDetections(item.id),
      builder: (context, snapshot) {
        final detections = snapshot.data ?? const <MediaDetection>[];
        final personFaces =
            detections.where((d) => d.isFace && d.personId == person.id).toList();
        final personBodies =
            detections.where((d) => d.isBody && d.personId == person.id).toList();
        final hasFace = personFaces.isNotEmpty;
        final hasBody = personBodies.isNotEmpty;

        final otherPersonIds = detections
            .map((d) => d.personId)
            .whereType<int>()
            .where((id) => id != person.id)
            .toSet();

        return SheetScaffold(
          title: personName(l10n, person),
          subtitle: hasFace && hasBody
              ? l10n.linkedByFaceAndBody
              : hasFace
                  ? l10n.linkedByFaceOnly
                  : hasBody
                      ? l10n.linkedByBodyOnly
                      : l10n.noPhotosOfPerson,
          leading: PersonAvatar(cropPath: person.avatarCropPath, radius: 24),
          trailing: IconButton(
            key: const Key('person-media-actions-close'),
            tooltip: l10n.cancel,
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Hero Detection Card: shows visual evidence of why this photo is here
              _HeroDetectionCard(
                item: item,
                person: person,
                personFaces: personFaces,
                personBodies: personBodies,
                hasFace: hasFace,
                hasBody: hasBody,
              ),
              const SizedBox(height: 12),

              // 2. Identity & Link Corrections
              ActionSection(
                key: const Key('person-media-identity-section'),
                title: l10n.peopleMatching,
                icon: Icons.person_search_outlined,
                children: [
                  if (hasFace)
                    ListTile(
                      key: const Key('action-not-this-person'),
                      leading: Icon(
                        Icons.person_off_outlined,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        l10n.notThisPerson,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      subtitle: const Text('Unlink and reject face from this person'),
                      onTap: () => _rejectFace(context, ref, personFaces),
                    ),
                  if (hasBody)
                    ListTile(
                      key: const Key('action-not-this-body'),
                      leading: Icon(
                        Icons.accessibility_new,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        l10n.notThisBody,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      subtitle: const Text('Unlink outfit and body from this person'),
                      onTap: () => _rejectBody(context, ref, personBodies),
                    ),
                  ListTile(
                    key: const Key('action-another-person'),
                    leading: Icon(
                      Icons.drive_file_move_outline,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(l10n.reassignToOtherPerson),
                    subtitle: const Text('Move photo to someone else and open their album'),
                    onTap: () => _reassignAndNavigate(
                      context,
                      ref,
                      personFaces: personFaces,
                      personBodies: personBodies,
                    ),
                  ),
                  if (otherPersonIds.isNotEmpty)
                    _CoOccurringPeopleRow(
                      personIds: otherPersonIds,
                      onPersonSelected: (targetId) => _moveToTargetPerson(
                        context,
                        ref,
                        targetId: targetId,
                        personFaces: personFaces,
                        personBodies: personBodies,
                      ),
                    ),
                  ListTile(
                    key: const Key('action-change-kind'),
                    leading: const Icon(Icons.swap_horiz),
                    title: Text(
                      person.kind == 'person'
                          ? l10n.peopleAction('toCharacters')
                          : l10n.peopleAction('toPeople'),
                    ),
                    onTap: () => _changeKind(context, ref, personFaces, personBodies),
                  ),
                ],
              ),

              // 3. Quick Shortcuts & Tools
              ActionSection(
                key: const Key('person-media-tools-section'),
                title: l10n.peopleTools,
                icon: Icons.tune,
                children: [
                  if (hasFace)
                    ListTile(
                      key: const Key('action-set-cover'),
                      leading: const Icon(Icons.account_circle_outlined),
                      title: Text(l10n.setAsPersonCover),
                      onTap: () => _setAsCover(context, ref, personFaces.first),
                    ),
                  ListTile(
                    key: const Key('action-view-full'),
                    leading: const Icon(Icons.fullscreen),
                    title: Text(l10n.viewFullMedia),
                    onTap: () {
                      Navigator.pop(context);
                      context.push(
                        '${Routes.media}/${item.id}?personId=${person.id}',
                      );
                    },
                  ),
                  ListTile(
                    key: const Key('action-photo-edit'),
                    leading: const Icon(Icons.auto_fix_high),
                    title: const Text('AI Edit (تعديل بالذكاء الاصطناعي)'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('${Routes.photoEdit}?mediaId=${item.id}');
                    },
                  ),
                  if (person.kind == 'person' && hasFace)
                    ListTile(
                      key: const Key('action-studio-reface'),
                      leading: const Icon(Icons.face_retouching_natural),
                      title: const Text('Studio Reface (تبديل الوجه)'),
                      onTap: () {
                        Navigator.pop(context);
                        context.push(
                          '${Routes.reface}?face=${personFaces.first.refId}',
                        );
                      },
                    ),
                  ListTile(
                    key: const Key('action-share'),
                    leading: const Icon(Icons.share_outlined),
                    title: const Text('Share photo'),
                    onTap: () => _shareMedia(context, ref),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _rejectFace(
    BuildContext context,
    WidgetRef ref,
    List<MediaDetection> faces,
  ) async {
    final ids = faces.map((f) => f.refId).toList();
    await ref.read(peopleRepositoryProvider).rejectFaces(
      ids,
      fromPersonId: person.id,
    );
    if (!context.mounted) return;
    Navigator.pop(context);
    peopleUpdated(context);
  }

  Future<void> _rejectBody(
    BuildContext context,
    WidgetRef ref,
    List<MediaDetection> bodies,
  ) async {
    final repo = ref.read(peopleRepositoryProvider);
    for (final b in bodies) {
      await repo.rejectBody(b.refId, personId: person.id);
    }
    if (!context.mounted) return;
    Navigator.pop(context);
    peopleUpdated(context);
  }

  Future<void> _reassignAndNavigate(
    BuildContext context,
    WidgetRef ref, {
    required List<MediaDetection> personFaces,
    required List<MediaDetection> personBodies,
  }) async {
    final l10n = AppLocalizations.of(context);
    final hasFace = personFaces.isNotEmpty;
    final choice = await pickPerson(
      context,
      excludePersonId: person.id,
      allowNew: hasFace,
      title: l10n.assignFacesTitle(1),
      kind: person.kind,
    );
    if (choice == null || !context.mounted) return;

    final repo = peopleRepositoryFor(ref, person.kind);
    int targetId;
    if (choice.isNew) {
      targetId = await repo.createPerson(
        name: choice.newName,
        faceIds: personFaces.map((f) => f.refId),
      );
    } else {
      targetId = choice.personId!;
      if (hasFace) {
        await repo.assignFaces(
          personFaces.map((f) => f.refId).toList(),
          targetId,
        );
      }
      for (final b in personBodies) {
        await repo.linkBody(b.refId, targetId);
      }
    }

    if (!context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          choice.isNew
              ? l10n.reassignedToPerson(choice.newName ?? '')
              : l10n.reassignedToPerson('Person $targetId'),
        ),
      ),
    );
    context.push('${Routes.people}/$targetId');
  }

  Future<void> _moveToTargetPerson(
    BuildContext context,
    WidgetRef ref, {
    required int targetId,
    required List<MediaDetection> personFaces,
    required List<MediaDetection> personBodies,
  }) async {
    final l10n = AppLocalizations.of(context);
    final repo = peopleRepositoryFor(ref, person.kind);
    if (personFaces.isNotEmpty) {
      await repo.assignFaces(
        personFaces.map((f) => f.refId).toList(),
        targetId,
      );
    }
    for (final b in personBodies) {
      await repo.linkBody(b.refId, targetId);
    }
    if (!context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.reassignedToPerson('Person $targetId'))),
    );
    context.push('${Routes.people}/$targetId');
  }

  Future<void> _changeKind(
    BuildContext context,
    WidgetRef ref,
    List<MediaDetection> personFaces,
    List<MediaDetection> personBodies,
  ) async {
    Navigator.pop(context);
    await moveToOtherKind(
      context,
      ref,
      fromKind: person.kind,
      faceIds: personFaces.map((f) => f.refId).toList(),
      bodyIds: personBodies.map((b) => b.refId).toList(),
    );
  }

  Future<void> _setAsCover(
    BuildContext context,
    WidgetRef ref,
    MediaDetection face,
  ) async {
    final l10n = AppLocalizations.of(context);
    await ref.read(peopleRepositoryProvider).setAvatar(person.id, face.refId);
    if (!context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.coverChanged)),
    );
  }

  Future<void> _shareMedia(BuildContext context, WidgetRef ref) async {
    try {
      final asset = await AssetEntity.fromId(item.assetId);
      final file = await asset?.file;
      if (file != null) {
        await Share.shareXFiles([XFile(file.path)]);
      }
    } catch (e) {
      if (context.mounted) peopleError(context, e);
    }
  }
}

/// Hero card highlighting why the photo is grouped under this person:
/// Shows photo thumbnail alongside face and body detection previews and status chips.
class _HeroDetectionCard extends ConsumerWidget {
  const _HeroDetectionCard({
    required this.item,
    required this.person,
    required this.personFaces,
    required this.personBodies,
    required this.hasFace,
    required this.hasBody,
  });

  final MediaListItem item;
  final PersonSummary person;
  final List<MediaDetection> personFaces;
  final List<MediaDetection> personBodies;
  final bool hasFace;
  final bool hasBody;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final thumbs = ref.watch(thumbnailServiceProvider);
    final thumbData = thumbs.getSync(item.assetId);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: thumbData != null
                      ? Image.memory(
                          thumbData,
                          fit: BoxFit.cover,
                          cacheWidth: 160,
                          cacheHeight: 160,
                        )
                      : FutureBuilder(
                          future: thumbs.get(item.assetId, width: 160, height: 160),
                          builder: (context, snap) => snap.data != null
                              ? Image.memory(
                                  snap.data!,
                                  fit: BoxFit.cover,
                                )
                              : ColoredBox(
                                  color: scheme.surfaceContainerHighest,
                                  child: const Icon(Icons.photo_outlined),
                                ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Evidence in this photo',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.outline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _StatusBadge(
                      hasFace: hasFace,
                      hasBody: hasBody,
                      l10n: l10n,
                      scheme: scheme,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hasFace || hasBody) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (hasFace)
                  _DetectionChip(
                    icon: Icons.face,
                    label: 'Face detected',
                    cropPath: personFaces.first.cropPath,
                    scheme: scheme,
                  ),
                if (hasBody)
                  _DetectionChip(
                    icon: Icons.accessibility_new,
                    label: personBodies.first.linkMethod == 'manual'
                        ? 'Body (manual link)'
                        : 'Body (outfit match)',
                    cropPath: personBodies.first.cropPath,
                    scheme: scheme,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.hasFace,
    required this.hasBody,
    required this.l10n,
    required this.scheme,
  });

  final bool hasFace;
  final bool hasBody;
  final AppLocalizations l10n;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String text, Color bg, Color fg) = switch ((
      hasFace,
      hasBody,
    )) {
      (true, true) => (
          Icons.people_alt,
          l10n.linkedByFaceAndBody,
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      (true, false) => (
          Icons.face,
          l10n.linkedByFaceOnly,
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
        ),
      (false, true) => (
          Icons.accessibility_new,
          l10n.linkedByBodyOnly,
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      (false, false) => (
          Icons.help_outline,
          'No active detections',
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetectionChip extends StatelessWidget {
  const _DetectionChip({
    required this.icon,
    required this.label,
    required this.cropPath,
    required this.scheme,
  });

  final IconData icon;
  final String label;
  final String? cropPath;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cropPath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CropImage(path: cropPath, cacheWidth: 64),
              ),
            )
          else
            Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CoOccurringPeopleRow extends ConsumerWidget {
  const _CoOccurringPeopleRow({
    required this.personIds,
    required this.onPersonSelected,
  });

  final Set<int> personIds;
  final ValueChanged<int> onPersonSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final peopleRepo = ref.watch(peopleRepositoryProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Also in this photo:',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final pid in personIds)
                StreamBuilder<PersonSummary?>(
                  stream: peopleRepo.watchPerson(pid),
                  builder: (context, snap) {
                    final p = snap.data;
                    if (p == null) return const SizedBox.shrink();
                    return ActionChip(
                      avatar: PersonAvatar(cropPath: p.avatarCropPath, radius: 12),
                      label: Text(
                        personName(AppLocalizations.of(context), p),
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () => onPersonSelected(pid),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
