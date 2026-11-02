import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library_providers.dart';
import '../scaffolds/sheet_scaffold.dart';
import 'name_sheet.dart';

class GroupPicker {
  GroupPicker._();

  static Future<int?> show(
    BuildContext context, {
    int? currentGroupId,
    bool allowNone = true,
  }) {
    return SheetScaffold.show<int>(
      context: context,
      builder: (_) => _GroupPickerSheet(
        currentGroupId: currentGroupId,
        allowNone: allowNone,
      ),
    );
  }
}

class _GroupPickerSheet extends ConsumerWidget {
  const _GroupPickerSheet({
    required this.currentGroupId,
    required this.allowNone,
  });

  final int? currentGroupId;
  final bool allowNone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(identityGroupsProvider);

    return SheetScaffold(
      title: 'Choose Group',
      actions: [
        FilledButton.tonalIcon(
          onPressed: () async {
            final name = await NameSheet.show(
              context: context,
              title: 'New Group',
              hintText: 'Group name',
            );
            if (name != null && name.trim().isNotEmpty && context.mounted) {
              final id = await ref
                  .read(identityGroupsRepositoryProvider)
                  .create(name.trim());
              if (context.mounted) {
                Navigator.of(context).pop(id);
              }
            }
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New group'),
        ),
      ],
      child: groupsAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error loading groups: $err'),
          ),
        ),
        data: (groups) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (allowNone)
                ListTile(
                  leading: const Icon(Icons.folder_off_outlined),
                  title: const Text('No group'),
                  trailing: currentGroupId == null
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () =>
                      Navigator.of(context).pop(-1), // -1 means clear group
                ),
              if (groups.isEmpty && !allowNone)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No groups yet. Tap "New group" above to create one.',
                  ),
                ),
              for (final g in groups) ...[
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(g.name),
                  subtitle: Text('${g.people + g.characters} members'),
                  trailing: currentGroupId == g.id
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(context).pop(g.id),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
