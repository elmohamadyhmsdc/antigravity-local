import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/repositories/people_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../shared/crop_image.dart';
import '../shared/empty_state.dart';
import '../shared/person_picker.dart';

/// A person's faces (or the unsorted ones when `personId` is null) - S09, the face picker.
final facesProvider = StreamProvider.autoDispose.family<List<FaceItem>, int?>(
  (ref, personId) => ref.watch(peopleRepositoryProvider).watchFaces(personId),
);

/// Tap a face to open its photo; long-press (or tap once something is selected) to select faces and
/// assign, move, reject, delete them or make one the person's cover.
class FaceGrid extends ConsumerStatefulWidget {
  const FaceGrid({super.key, required this.personId});

  final int? personId;

  @override
  ConsumerState<FaceGrid> createState() => _FaceGridState();
}

class _FaceGridState extends ConsumerState<FaceGrid> {
  final _selected = <int>{};
  var _selectMode = false;

  bool get _selecting => _selectMode || _selected.isNotEmpty;

  void _clearSelection() => setState(() {
    _selected.clear();
    _selectMode = false;
  });

  void _toggle(int id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final faces = ref.watch(facesProvider(widget.personId));
    return faces.when(
      loading: () => const LoadingBox(),
      error: (_, _) => RetryState(
        onRetry: () => ref.invalidate(facesProvider(widget.personId)),
      ),
      data: (items) {
        // faces that left (assigned elsewhere, deleted) drop out of the selection
        final ids = {for (final f in items) f.id};
        _selected.removeWhere((id) => !ids.contains(id));
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.face_retouching_off,
            title: widget.personId == null
                ? l10n.noUnsortedFaces
                : l10n.noFacesYet,
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    key: const Key('face-selection-mode'),
                    onPressed: _selecting
                        ? _clearSelection
                        : () => setState(() => _selectMode = true),
                    icon: Icon(_selecting ? Icons.close : Icons.checklist),
                    label: Text(
                      _selecting ? l10n.clearSelection : l10n.selectFaces,
                    ),
                  ),
                  if (_selectMode && _selected.isEmpty)
                    TextButton(
                      onPressed: () => setState(() => _selected.addAll(ids)),
                      child: Text(l10n.selectAll),
                    ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                key: const Key('face-grid'),
                padding: const EdgeInsets.all(4),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 110,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) => _FaceTile(
                  face: items[i],
                  selected: _selected.contains(items[i].id),
                  selecting: _selecting,
                  onToggle: () => _toggle(items[i].id),
                  onOpen: () {
                    final media = items[i].mediaId;
                    if (media != null) context.push('${Routes.media}/$media');
                  },
                ),
              ),
            ),
            if (_selected.isNotEmpty)
              _SelectionBar(
                count: _selected.length,
                inPerson: widget.personId != null,
                canSetCover: widget.personId != null && _selected.length == 1,
                onSelectAll: () => setState(() => _selected.addAll(ids)),
                onClear: _clearSelection,
                onAssign: () => _assign(context),
                onReject: () => _reject(context),
                onDelete: () => _delete(context),
                onCover: () => _cover(context),
              ),
          ],
        );
      },
    );
  }

  Future<void> _assign(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(peopleRepositoryProvider);
    final choice = await pickPerson(
      context,
      excludePersonId: widget.personId,
      title: l10n.assignFacesTitle(_selected.length),
    );
    if (choice == null || !mounted) return;
    final ids = _selected.toList();
    final target = await resolveChoice(ref, choice, faceIds: ids);
    if (!choice.isNew) await repo.assignFaces(ids, target);
    if (!mounted) return;
    _clearSelection();
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.facesMoved(ids.length))),
    );
  }

  Future<void> _reject(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ids = _selected.toList();
    await ref
        .read(peopleRepositoryProvider)
        .rejectFaces(ids, fromPersonId: widget.personId);
    if (!mounted) return;
    _clearSelection();
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.facesRejected(ids.length))),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirm(
      context,
      title: l10n.deleteFacesTitle(_selected.length),
      body: l10n.deleteFacesBody,
      confirmLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await ref.read(peopleRepositoryProvider).deleteFaces(_selected.toList());
    if (mounted) _clearSelection();
  }

  Future<void> _cover(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(peopleRepositoryProvider)
        .setAvatar(widget.personId!, _selected.single);
    if (!mounted) return;
    _clearSelection();
    messenger.showSnackBar(SnackBar(content: Text(l10n.coverChanged)));
  }
}

class _FaceTile extends StatelessWidget {
  const _FaceTile({
    required this.face,
    required this.selected,
    required this.selecting,
    required this.onToggle,
    required this.onOpen,
  });

  final FaceItem face;
  final bool selected;
  final bool selecting;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      key: Key('face-${face.id}'),
      onTap: selecting ? onToggle : onOpen,
      onLongPress: onToggle,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CropImage(path: face.cropPath),
            if (selected)
              ColoredBox(color: scheme.primary.withValues(alpha: 0.35)),
            if (selecting)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? scheme.onPrimary : Colors.white70,
                  size: 22,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.inPerson,
    required this.canSetCover,
    required this.onSelectAll,
    required this.onClear,
    required this.onAssign,
    required this.onReject,
    required this.onDelete,
    required this.onCover,
  });

  final int count;
  final bool inPerson;
  final bool canSetCover;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onAssign;
  final VoidCallback onReject;
  final VoidCallback onDelete;
  final VoidCallback onCover;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                key: const Key('selection-clear'),
                tooltip: l10n.clearSelection,
                icon: const Icon(Icons.close),
                onPressed: onClear,
              ),
              Text(
                l10n.selectedCount(count),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              TextButton(onPressed: onSelectAll, child: Text(l10n.selectAll)),
              IconButton(
                key: const Key('selection-assign'),
                tooltip: l10n.assignTo,
                icon: const Icon(Icons.drive_file_move_outline),
                onPressed: onAssign,
              ),
              if (inPerson)
                IconButton(
                  key: const Key('selection-reject'),
                  tooltip: l10n.notThisPerson,
                  icon: const Icon(Icons.person_off_outlined),
                  onPressed: onReject,
                ),
              if (canSetCover)
                IconButton(
                  key: const Key('selection-cover'),
                  tooltip: l10n.setAsCover,
                  icon: const Icon(Icons.account_circle_outlined),
                  onPressed: onCover,
                ),
              IconButton(
                key: const Key('selection-delete'),
                tooltip: l10n.delete,
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
