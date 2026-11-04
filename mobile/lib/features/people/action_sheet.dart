import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../shared/crop_image.dart';
import '../../ui/actions/action_section.dart';
import '../../ui/scaffolds/sheet_scaffold.dart';

class PeopleMenuAction {
  const PeopleMenuAction(
    this.id,
    this.icon, {
    this.destructive = false,
    this.label,
  });
  final String id;
  final IconData icon;
  final bool destructive;
  final String? label;
}

Future<String?> showPeopleActionSheet(
  BuildContext context, {
  required String title,
  String? cropPath,
  String? subtitle,
  required List<PeopleMenuAction> actions,
}) => showModalBottomSheet<String>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  showDragHandle: false,
  builder: (context) {
    final l = AppLocalizations.of(context);
    Widget tile(PeopleMenuAction a) => ListTile(
      key: Key('people-action-${a.id}'),
      leading: Icon(
        a.icon,
        color: a.destructive ? Theme.of(context).colorScheme.error : null,
      ),
      title: Text(
        a.label ??
            (a.id == 'setGroup'
                ? l.identityGroupAssign
                : a.id == 'organizeMedia'
                ? l.organizeTitle
                : l.peopleAction(a.id == 'select' ? 'selection' : a.id)),
        style: TextStyle(
          color: a.destructive ? Theme.of(context).colorScheme.error : null,
        ),
      ),
      onTap: () => Navigator.pop(context, a.id),
    );
    final regular = actions.where((a) => !a.destructive).toList();
    const quickOrder = [
      'open',
      'select',
      'rename',
      'suggestions',
      'assign',
      'similar',
    ];
    final quick = <PeopleMenuAction>[];
    if (actions.length <= 5) quick.addAll(regular);
    for (final id in actions.length <= 5 ? const <String>[] : quickOrder) {
      final action = regular.where((a) => a.id == id).firstOrNull;
      if (action != null && quick.length < 3) quick.add(action);
    }
    final secondary = regular.where((a) => !quick.contains(a)).toList();
    const organize = {
      'setGroup',
      'organizeMedia',
      'hide',
      'show',
      'pin',
      'unpin',
      'favorite',
      'unfavorite',
      'cover',
    };
    const matching = {
      'add',
      'split',
      'suggestions',
      'distinct',
      'lock',
      'unlock',
      'redetect',
      'toCharacters',
      'toPeople',
      'reject',
      'unassign',
      'similar',
      'merge',
      'dissolve',
    };
    const create = {'studio', 'curateLora', 'exportTraining'};
    final groups = [
      (
        'organize',
        l.peopleOrganize,
        Icons.folder_outlined,
        secondary.where((a) => organize.contains(a.id)).toList(),
      ),
      (
        'matching',
        l.peopleMatching,
        Icons.person_search_outlined,
        secondary.where((a) => matching.contains(a.id)).toList(),
      ),
      (
        'create',
        'Create & training',
        Icons.auto_awesome_outlined,
        secondary.where((a) => create.contains(a.id)).toList(),
      ),
      (
        'tools',
        l.peopleTools,
        Icons.tune,
        secondary
            .where(
              (a) =>
                  !organize.contains(a.id) &&
                  !matching.contains(a.id) &&
                  !create.contains(a.id),
            )
            .toList(),
      ),
    ];
    return SheetScaffold(
      title: title,
      subtitle: subtitle,
      leading: PersonAvatar(cropPath: cropPath, radius: 24),
      trailing: IconButton(
        key: const Key('people-actions-close'),
        tooltip: l.cancel,
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...quick.map(tile),
          for (final group in groups)
            if (group.$4.isNotEmpty)
              ActionSection(
                key: Key('people-actions-${group.$1}'),
                title: group.$2,
                icon: group.$3,
                children: group.$4.map(tile).toList(),
              ),
          if (actions.any((a) => a.destructive))
            ActionSection(
              key: const Key('people-actions-remove'),
              title: 'Remove',
              icon: Icons.delete_outline,
              danger: true,
              children: actions.where((a) => a.destructive).map(tile).toList(),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  },
);
