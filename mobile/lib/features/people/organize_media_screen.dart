import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/platform/media_organizer.dart';
import '../../domain/organization/person_media_organizer.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../shared/empty_state.dart';
import '../shared/image_preview.dart';

class OrganizePersonMediaScreen extends ConsumerStatefulWidget {
  const OrganizePersonMediaScreen({super.key, required this.personIds});
  final Set<int> personIds;
  @override
  ConsumerState<OrganizePersonMediaScreen> createState() =>
      _OrganizePersonMediaState();
}

class _OrganizePersonMediaState
    extends ConsumerState<OrganizePersonMediaScreen> {
  List<PersonOrganizeItem> items = [];
  final choices = <int, int?>{};
  final selected = <int>{};
  List<OriginalMoveResult> results = [];
  bool loading = true, busy = false;
  bool hasPending = false;
  String? error;
  int done = 0, total = 0, generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool resume = false, int? changedMedia}) async {
    final version = ++generation;
    final preserveSelection = items.isNotEmpty && !resume;
    final previousSelection = {...selected};
    setState(() => loading = true);
    try {
      final service = ref.read(personMediaOrganizerProvider);
      final pending = await service.pending();
      final plan = resume
          ? pending
          : await service.plan(widget.personIds, choices: choices);
      if (!mounted || version != generation) return;
      setState(() {
        items = plan;
        selected
          ..clear()
          ..addAll(
            plan
                .where(
                  (i) =>
                      i.canApply &&
                      i.status != 'already' &&
                      (!preserveSelection ||
                          previousSelection.contains(i.media.id) ||
                          i.media.id == changedMedia),
                )
                .map((i) => i.media.id),
          );
        if (resume) {
          selected.addAll(plan.where((i) => i.canApply).map((i) => i.media.id));
        }
        hasPending = pending.isNotEmpty;
        loading = false;
        error = null;
        results = [];
      });
    } catch (_) {
      if (mounted && version == generation) {
        setState(() {
          loading = false;
          error = AppLocalizations.of(context).organizeLoadFailed;
        });
      }
    }
  }

  Future<void> apply() async {
    final picked = items
        .where((i) => selected.contains(i.media.id) && i.canApply)
        .toList();
    if (picked.isEmpty) return;
    setState(() {
      busy = true;
      done = 0;
      total = picked.length;
      error = null;
      results = [];
    });
    try {
      final result = await ref
          .read(personMediaOrganizerProvider)
          .apply(
            picked,
            onProgress: (count, all) {
              if (mounted) {
                setState(() {
                  done = count;
                  total = all;
                });
              }
            },
          );
      if (mounted) {
        setState(() {
          results = result;
          selected.clear();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = AppLocalizations.of(context).organizeInterrupted,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  OriginalMediaInfo? movedInfo(PersonOrganizeItem item) => results
      .where((r) => r.assetId == item.media.assetId && r.moved)
      .firstOrNull
      ?.actual;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final picked = items
        .where((i) => selected.contains(i.media.id) && i.canApply)
        .toList();
    final images = picked.where((i) => i.media.kind == 'photo').length;
    final videos = picked.where((i) => i.media.kind == 'video').length;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.organizeTitle),
          actions: [
            IconButton(
              key: const Key('organize-refresh'),
              tooltip: l.retry,
              onPressed: busy ? null : () => load(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        bottomNavigationBar: loading && items.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (busy || loading)
                        LinearProgressIndicator(
                          value: loading || done == 0 || total == 0
                              ? null
                              : done / total,
                        ),
                      Text(l.organizeSelection(images, videos)),
                      FilledButton.icon(
                        key: const Key('organize-apply'),
                        onPressed: busy || loading || picked.isEmpty
                            ? null
                            : apply,
                        icon: const Icon(Icons.drive_file_move_outlined),
                        label: Text(busy ? l.organizeWorking : l.organizeApply),
                      ),
                    ],
                  ),
                ),
              ),
        body: loading && items.isEmpty
            ? const LoadingBox()
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(l.organizeIntro),
                  const SizedBox(height: 8),
                  SelectableText(
                    ref.watch(organizeRootProvider).value ??
                        PersonMediaOrganizer.dcimRoot,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(l.organizeNaming),
                  const SizedBox(height: 12),
                  if (hasPending)
                    OutlinedButton.icon(
                      key: const Key('organize-resume'),
                      onPressed: busy ? null : () => load(resume: true),
                      icon: const Icon(Icons.history),
                      label: Text(l.organizeResume),
                    ),
                  if (hasPending)
                    TextButton(
                      key: const Key('organize-cancel-pending'),
                      onPressed: busy
                          ? null
                          : () async {
                              await ref
                                  .read(personMediaOrganizerProvider)
                                  .cancelPending();
                              await load();
                            },
                      child: Text(l.organizeCancelPending),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (results.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        l.organizeResult(
                          results.where((r) => r.moved).length,
                          results.where((r) => !r.moved).length,
                        ),
                      ),
                    ),
                  if (items.isEmpty && error == null)
                    EmptyState(
                      icon: Icons.perm_media_outlined,
                      title: l.organizeNoFiles,
                    ),
                  if (items.any((i) => i.status == 'choose_owner'))
                    Text(
                      l.organizeSharedHint,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  if (items.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          key: const Key('organize-select-all'),
                          onPressed: busy
                              ? null
                              : () => setState(
                                  () => selected.addAll(
                                    items
                                        .where(
                                          (i) =>
                                              i.canApply &&
                                              i.status != 'already',
                                        )
                                        .map((i) => i.media.id),
                                  ),
                                ),
                          child: Text(l.selectAll),
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => setState(() => selected.clear()),
                          child: Text(l.organizeSelectNone),
                        ),
                      ],
                    ),
                  for (final item in items)
                    Card(
                      key: Key('organize-media-${item.media.id}'),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Checkbox(
                                  key: Key('organize-check-${item.media.id}'),
                                  value: selected.contains(item.media.id),
                                  onChanged: busy || loading || !item.canApply
                                      ? null
                                      : (on) => setState(() {
                                          if (on == true) {
                                            selected.add(item.media.id);
                                          } else {
                                            selected.remove(item.media.id);
                                          }
                                        }),
                                ),
                                SizedBox(
                                  width: 64,
                                  height: 72,
                                  child: FutureBuilder<Uint8List?>(
                                    future: ref
                                        .read(thumbnailServiceProvider)
                                        .get(
                                          item.media.assetId,
                                          width: item.media.width ?? 0,
                                          height: item.media.height ?? 0,
                                        ),
                                    builder: (context, snapshot) =>
                                        snapshot.data == null
                                        ? Icon(
                                            item.media.kind == 'video'
                                                ? Icons.video_library_outlined
                                                : Icons.image_outlined,
                                          )
                                        : PreviewImage.memory(
                                            snapshot.data!,
                                            fit: BoxFit.contain,
                                            fullSource:
                                                ImagePreviewSource.asset(
                                                  item.media.assetId,
                                                ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.source?.name ?? item.media.assetId,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      ),
                                      Text(
                                        item.source?.path ?? '',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (item.owners.length > 1)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: DropdownButtonFormField<int>(
                                  key: ValueKey(
                                    'organize-owner-${item.media.id}-${item.ownerId}',
                                  ),
                                  initialValue: item.ownerId,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: l.organizeChooseOwner,
                                  ),
                                  items: [
                                    for (final owner in item.owners)
                                      DropdownMenuItem(
                                        value: owner.id,
                                        child: Text(
                                          owner.name?.trim().isNotEmpty == true
                                              ? owner.name!
                                              : l.personFallbackName(owner.id),
                                        ),
                                      ),
                                  ],
                                  onChanged: busy || loading
                                      ? null
                                      : (id) {
                                          choices[item.media.id] = id;
                                          load(changedMedia: item.media.id);
                                        },
                                ),
                              ),
                            if (item.request != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                movedInfo(item)?.path ??
                                    item.request!.targetPath,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                movedInfo(item)?.name ??
                                    item.request!.targetName,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              l.organizeStatus(
                                results
                                        .where(
                                          (r) =>
                                              r.assetId == item.media.assetId,
                                        )
                                        .firstOrNull
                                        ?.status ??
                                    item.status,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
