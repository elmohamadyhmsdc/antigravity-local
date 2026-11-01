import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/db/app_database.dart';
import '../../domain/pose/group_pose_matcher.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../shared/empty_state.dart';
import 'pose_visuals.dart';

Future<bool> nameGroupPose(
  BuildContext context,
  WidgetRef ref,
  int mediaId,
) async {
  final photo = await ref.read(groupPoseMatcherProvider).photo(mediaId);
  if (!context.mounted) return false;
  final l = AppLocalizations.of(context);
  if (photo?.feature == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.groupPoseCannotMeasure)));
    return false;
  }
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _GroupNameDialog(photo: photo!),
  );
  if (name == null || !context.mounted) return false;
  final id = await ref.read(groupPoseMatcherProvider).save(name, photo!);
  if (!context.mounted) return true;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => GroupPoseResultsScreen(
        feature: photo.feature!,
        source: photo,
        name: name,
        categoryId: id,
      ),
    ),
  );
  return true;
}

class _GroupNameDialog extends StatefulWidget {
  const _GroupNameDialog({required this.photo});
  final GroupPosePhoto photo;
  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
  final name = TextEditingController();
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.groupPoseName),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 280,
              height: 150,
              child: GroupPhotoPreview(
                assetId: widget.photo.assetId,
                feature: widget.photo.feature,
              ),
            ),
            Text(l.groupPosePeople(widget.photo.bodies.length)),
            TextField(
              key: const Key('group-pose-name'),
              controller: name,
              maxLength: 80,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l.categoryNameHint,
                hintText: l.groupPoseNameHint,
              ),
              onChanged: (_) => setState(() {}),
            ),
            Text(
              l.groupPoseNamingNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const Key('group-pose-save'),
          onPressed: name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, name.text.trim()),
          child: Text(l.categorySave),
        ),
      ],
    );
  }
}

class GroupPosesTab extends ConsumerStatefulWidget {
  const GroupPosesTab({super.key, this.personId});
  final int? personId;
  @override
  ConsumerState<GroupPosesTab> createState() => _GroupPosesTabState();
}

class _GroupPosesTabState extends ConsumerState<GroupPosesTab> {
  List<GroupPosePhoto> photos = [];
  List<PoseCategoryRow> saved = [];
  bool loaded = false, failed = false;
  int? count;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final service = ref.read(groupPoseMatcherProvider);
      final all = await service.photos(personId: widget.personId);
      final categories = await service.categories();
      if (mounted) {
        setState(() {
          photos = all;
          saved = categories;
          loaded = true;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loaded = true;
          failed = true;
        });
      }
    }
  }

  Future<void> openSaved(PoseCategoryRow category) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupPoseResultsScreen(
          feature: GroupPoseFeature.decode(category.exemplarFeature),
          name: category.name,
          categoryId: category.id,
          personId: widget.personId,
        ),
      ),
    );
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (!loaded) return const Center(child: CircularProgressIndicator());
    if (failed) {
      return EmptyState(
        icon: Icons.refresh,
        title: l.bodiesLoadFailed,
        actionLabel: l.bodiesRetry,
        onAction: load,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l.groupPoseIntro, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        if (saved.isNotEmpty) ...[
          Text(
            l.groupPoseSaved,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final category in saved)
            ListTile(
              key: Key('group-category-${category.id}'),
              contentPadding: EdgeInsets.zero,
              leading: SizedBox(
                width: 72,
                height: 64,
                child: PoseDiagram(
                  group: GroupPoseFeature.decode(category.exemplarFeature),
                ),
              ),
              title: Text(category.name),
              subtitle: Text(l.groupPosePeople(category.exemplarMask)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openSaved(category),
            ),
          const SizedBox(height: 16),
        ],
        Text(
          l.groupPoseChooseExample,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(l.bodiesTabAll),
                  selected: count == null,
                  onSelected: (_) => setState(() => count = null),
                ),
              ),
              for (final n in {
                for (final p in photos) p.bodies.length,
              }.toList()..sort())
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    key: Key('group-count-$n'),
                    label: Text(l.groupPosePeople(n)),
                    selected: count == n,
                    onSelected: (on) => setState(() => count = on ? n : null),
                  ),
                ),
            ],
          ),
        ),
        if (photos.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(l.groupPoseEmpty),
          ),
        for (final photo
            in photos
                .where((p) => count == null || p.bodies.length == count)
                .take(200))
          Card(
            key: Key('group-photo-${photo.mediaId}'),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 180,
                  child: GroupPhotoPreview(
                    assetId: photo.assetId,
                    feature: photo.feature,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.groupPosePeople(photo.bodies.length),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (photo.feature == null) Text(l.groupPoseCannotMeasure),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            key: Key('group-similar-${photo.mediaId}'),
                            onPressed: photo.feature == null
                                ? null
                                : () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => GroupPoseResultsScreen(
                                          feature: photo.feature!,
                                          source: photo,
                                          personId: widget.personId,
                                        ),
                                      ),
                                    );
                                    await load();
                                  },
                            icon: const Icon(Icons.manage_search),
                            label: Text(l.groupPoseSimilar),
                          ),
                          TextButton.icon(
                            key: Key('group-name-${photo.mediaId}'),
                            onPressed: photo.feature == null
                                ? null
                                : () async {
                                    await nameGroupPose(
                                      context,
                                      ref,
                                      photo.mediaId,
                                    );
                                    await load();
                                  },
                            icon: const Icon(Icons.bookmark_add_outlined),
                            label: Text(l.groupPoseName),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class GroupPoseResultsScreen extends ConsumerStatefulWidget {
  const GroupPoseResultsScreen({
    super.key,
    required this.feature,
    this.source,
    this.name,
    this.categoryId,
    this.personId,
  });
  final GroupPoseFeature feature;
  final GroupPosePhoto? source;
  final String? name;
  final int? categoryId, personId;
  @override
  ConsumerState<GroupPoseResultsScreen> createState() =>
      _GroupPoseResultsState();
}

class _GroupPoseResultsState extends ConsumerState<GroupPoseResultsScreen> {
  List<GroupPoseResult> matches = [];
  Map<int, Set<String>> equipment = {};
  String? tool;
  bool loaded = false, failed = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final rows = await ref
          .read(groupPoseMatcherProvider)
          .similar(
            widget.feature,
            excludingMedia: widget.categoryId == null
                ? widget.source?.mediaId
                : null,
            personId: widget.personId,
            categoryId: widget.categoryId,
          );
      final objects = await ref.read(equipmentLibraryProvider).objects();
      if (mounted) {
        setState(() {
          matches = rows;
          equipment = {};
          for (final o in objects) {
            equipment.putIfAbsent(o.mediaId, () => <String>{}).add(o.label);
          }
          loaded = true;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loaded = true;
          failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final shown = matches
        .where(
          (m) =>
              tool == null ||
              (equipment[m.photo.mediaId]?.contains(tool) ?? false),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name ?? l.groupPoseSimilar),
        actions: [
          if (widget.categoryId != null)
            IconButton(
              key: const Key('group-category-delete'),
              tooltip: l.categoryDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await ref
                    .read(bodyCategoriesProvider)
                    .deletePose(widget.categoryId!);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : failed
          ? EmptyState(
              icon: Icons.refresh,
              title: l.bodiesLoadFailed,
              actionLabel: l.bodiesRetry,
              onAction: load,
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  l.groupPoseReference,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                SizedBox(
                  height: 160,
                  child: widget.source == null
                      ? PoseDiagram(group: widget.feature)
                      : GroupPhotoPreview(
                          assetId: widget.source!.assetId,
                          feature: widget.feature,
                        ),
                ),
                Text(l.groupPosePeople(widget.feature.members.length)),
                Text(
                  l.groupPoseResultsNote,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (widget.source != null && widget.categoryId == null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () =>
                          nameGroupPose(context, ref, widget.source!.mediaId),
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: Text(l.groupPoseName),
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final label in {
                      for (final m in matches)
                        ...equipment[m.photo.mediaId] ?? <String>{},
                    }.toList()..sort())
                      FilterChip(
                        key: Key('group-equipment-$label'),
                        label: Text(label),
                        selected: tool == label,
                        onSelected: (on) =>
                            setState(() => tool = on ? label : null),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (shown.isEmpty) Text(l.bodiesNothingMatches),
                for (final match in shown)
                  Card(
                    key: Key('group-match-${match.photo.mediaId}'),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 180,
                          child: GroupPhotoPreview(
                            assetId: match.photo.assetId,
                            feature: match.photo.feature,
                          ),
                        ),
                        ListTile(
                          title: Text(
                            l.groupPosePeople(match.photo.bodies.length),
                          ),
                          subtitle: Text(
                            (equipment[match.photo.mediaId] ?? {}).join(' · '),
                          ),
                          trailing: IconButton(
                            tooltip: l.bodyActionOpenPhoto,
                            icon: const Icon(Icons.open_in_new),
                            onPressed: () => context.push(
                              '${Routes.media}/${match.photo.mediaId}',
                            ),
                          ),
                        ),
                        if (widget.categoryId != null)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              key: Key('group-reject-${match.photo.mediaId}'),
                              icon: const Icon(Icons.remove_circle_outline),
                              label: Text(l.categoryRemoveBody),
                              onPressed: () async {
                                await ref
                                    .read(groupPoseMatcherProvider)
                                    .reject(widget.categoryId!, match.photo);
                                await load();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
