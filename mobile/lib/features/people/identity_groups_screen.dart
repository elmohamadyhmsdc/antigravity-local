import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/media_queries.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../library/media_grid.dart';
import '../shared/empty_state.dart';
import 'people_screen.dart';
import 'organize_media_screen.dart';

Future<String?> _askGroupName(BuildContext context, {String? initial}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _GroupNameDialog(initial: initial),
    );

class _GroupNameDialog extends StatefulWidget {
  const _GroupNameDialog({this.initial});
  final String? initial;
  @override
  State<_GroupNameDialog> createState() => _GroupNameState();
}

class _GroupNameState extends State<_GroupNameDialog> {
  late final name = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.initial == null ? l.identityGroupCreate : l.rename),
      content: TextField(
        key: const Key('identity-group-name'),
        controller: name,
        autofocus: true,
        maxLength: 80,
        decoration: InputDecoration(
          labelText: l.categoryNameHint,
          hintText: l.identityGroupNameHint,
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('identity-group-save'),
          onPressed: name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, name.text.trim()),
          child: Text(l.categorySave),
        ),
      ],
    );
  }
}

/// Assigning a group changes organization only; it never merges identities.
Future<void> assignIdentityGroup(
  BuildContext context,
  WidgetRef ref,
  List<int> people,
) async {
  final choice = await showModalBottomSheet<(bool, int?)>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _GroupPicker(),
  );
  if (choice == null || !context.mounted) return;
  int? id = choice.$2;
  if (choice.$1) {
    final name = await _askGroupName(context);
    if (name == null || !context.mounted) return;
    id = await ref.read(identityGroupsRepositoryProvider).create(name);
  }
  await ref.read(identityGroupsRepositoryProvider).assign(people, id);
}

class _GroupPicker extends ConsumerWidget {
  const _GroupPicker();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final groups = ref.watch(identityGroupsProvider);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .75,
      ),
      child: groups.when(
        loading: () => const LoadingBox(),
        error: (_, _) =>
            RetryState(onRetry: () => ref.invalidate(identityGroupsProvider)),
        data: (rows) => ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l.identityGroupAssign,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              key: const Key('identity-group-create'),
              leading: const Icon(Icons.create_new_folder_outlined),
              title: Text(l.identityGroupCreate),
              onTap: () => Navigator.pop(context, (true, null)),
            ),
            ListTile(
              key: const Key('identity-group-none'),
              leading: const Icon(Icons.folder_off_outlined),
              title: Text(l.identityGroupUngrouped),
              onTap: () => Navigator.pop(context, (false, null)),
            ),
            for (final group in rows)
              ListTile(
                key: Key('identity-group-pick-${group.id}'),
                leading: const Icon(Icons.folder_outlined),
                title: Text(group.name),
                subtitle: Text(
                  l.identityGroupMembers(group.people + group.characters),
                ),
                onTap: () => Navigator.pop(context, (false, group.id)),
              ),
          ],
        ),
      ),
    );
  }
}

class IdentityGroupsScreen extends ConsumerWidget {
  const IdentityGroupsScreen({super.key, this.kind = 'person'});
  final String kind;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final groups = ref.watch(identityGroupsProvider);
    Future<void> create() async {
      final name = await _askGroupName(context);
      if (name == null || !context.mounted) return;
      await ref.read(identityGroupsRepositoryProvider).create(name);
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.identityGroupsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('identity-groups-add'),
        onPressed: create,
        icon: const Icon(Icons.add),
        label: Text(l.identityGroupCreate),
      ),
      body: groups.when(
        loading: () => const LoadingBox(),
        error: (_, _) =>
            RetryState(onRetry: () => ref.invalidate(identityGroupsProvider)),
        data: (rows) => rows.isEmpty
            ? EmptyState(
                icon: Icons.folder_outlined,
                title: l.identityGroupsEmpty,
                body: l.identityGroupsIntro,
                actionLabel: l.identityGroupCreate,
                onAction: create,
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  Text(l.identityGroupsIntro),
                  const SizedBox(height: 16),
                  for (final group in rows)
                    Card(
                      key: Key('identity-group-${group.id}'),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(group.name),
                            subtitle: Text(
                              l.identityGroupMembers(
                                group.people + group.characters,
                              ),
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => PeopleScreen(
                                  kind: kind,
                                  initialGroupId: group.id,
                                ),
                              ),
                            ),
                            trailing: PopupMenuButton<String>(
                              key: Key('identity-group-menu-${group.id}'),
                              onSelected: (action) async {
                                final repository = ref.read(
                                  identityGroupsRepositoryProvider,
                                );
                                if (action == 'rename') {
                                  final name = await _askGroupName(
                                    context,
                                    initial: group.name,
                                  );
                                  if (name == null || !context.mounted) return;
                                  try {
                                    await repository.rename(group.id, name);
                                  } catch (_) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            l.identityGroupNameExists,
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                } else {
                                  await repository.delete(group.id);
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text(l.rename),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(l.identityGroupDelete),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Wrap(
                              spacing: 8,
                              children: [
                                TextButton.icon(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => PeopleScreen(
                                        kind: 'person',
                                        initialGroupId: group.id,
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(Icons.people_outline),
                                  label: Text(l.navPeople),
                                ),
                                TextButton.icon(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => PeopleScreen(
                                        kind: 'character',
                                        initialGroupId: group.id,
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(Icons.auto_awesome_outlined),
                                  label: Text(l.peopleCharacters),
                                ),
                                TextButton.icon(
                                  key: Key('identity-group-media-${group.id}'),
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          _GroupMediaScreen(groupId: group.id),
                                    ),
                                  ),
                                  icon: const Icon(Icons.perm_media_outlined),
                                  label: Text(l.tabMedia),
                                ),
                                TextButton.icon(
                                  key: Key(
                                    'identity-group-organize-${group.id}',
                                  ),
                                  icon: const Icon(
                                    Icons.drive_file_move_outlined,
                                  ),
                                  label: Text(l.organizeTitle),
                                  onPressed: () async {
                                    final db = ref.read(databaseProvider);
                                    final members =
                                        await (db.select(db.persons)..where(
                                              (p) => p.groupId.equals(group.id),
                                            ))
                                            .get();
                                    if (!context.mounted) return;
                                    await Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            OrganizePersonMediaScreen(
                                              personIds: members
                                                  .map((p) => p.id)
                                                  .toSet(),
                                            ),
                                      ),
                                    );
                                  },
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
    );
  }
}

final _groupRowProvider = StreamProvider.autoDispose
    .family<IdentityGroupRow?, int>(
      (ref, id) =>
          (ref
                  .watch(databaseProvider)
                  .select(ref.watch(databaseProvider).identityGroups)
                ..where((g) => g.id.equals(id)))
              .watchSingleOrNull(),
    );

class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({
    super.key,
    required this.groupId,
    this.initialTab = 0,
  });
  final int groupId;
  final int initialTab;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final group = ref.watch(_groupRowProvider(widget.groupId)).value;
    final l = AppLocalizations.of(context);

    if (group == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.identityGroupsTitle)),
        body: const LoadingBox(),
      );
    }

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab.clamp(0, 1),
      child: Scaffold(
        appBar: AppBar(
          title: Text(group.name),
          actions: [
            IconButton(
              key: const Key('group-organize'),
              tooltip: l.organizeTitle,
              icon: const Icon(Icons.drive_file_move_outlined),
              onPressed: () async {
                final db = ref.read(databaseProvider);
                final members = await (db.select(
                  db.persons,
                )..where((p) => p.groupId.equals(group.id))).get();
                if (!context.mounted) return;
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => OrganizePersonMediaScreen(
                      personIds: members.map((p) => p.id).toSet(),
                    ),
                  ),
                );
              },
            ),
            IconButton(
              key: const Key('group-rename'),
              tooltip: l.rename,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final name = await _askGroupName(context, initial: group.name);
                if (name == null || !context.mounted) return;
                try {
                  await ref
                      .read(identityGroupsRepositoryProvider)
                      .rename(group.id, name);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.identityGroupNameExists)),
                    );
                  }
                }
              },
            ),
          ],
          bottom: TabBar(
            tabs: [
              const Tab(key: Key('tab-members'), text: 'Members'),
              Tab(key: const Key('tab-media'), text: l.tabMedia),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            PeopleScreen(initialGroupId: widget.groupId),
            MediaGrid(
              filter: MediaFilter(groupId: widget.groupId),
              empty: EmptyState(
                icon: Icons.perm_media_outlined,
                title: l.identityGroupNoMedia,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef GroupMediaScreen = GroupDetailScreen;
typedef _GroupMediaScreen = GroupDetailScreen;
