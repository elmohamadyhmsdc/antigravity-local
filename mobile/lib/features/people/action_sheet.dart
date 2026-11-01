import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../shared/crop_image.dart';

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
  showDragHandle: true,
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
    final secondary = regular.skip(5).toList();
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
    };
    final groups = <String, List<PeopleMenuAction>>{
      l.peopleOrganize: secondary
          .where((a) => organize.contains(a.id))
          .toList(),
      l.peopleMatching: secondary
          .where((a) => matching.contains(a.id))
          .toList(),
      l.peopleTools: secondary
          .where((a) => !organize.contains(a.id) && !matching.contains(a.id))
          .toList(),
    };
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: PersonAvatar(cropPath: cropPath, radius: 24),
              title: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: subtitle == null ? null : Text(subtitle),
              trailing: IconButton(
                key: const Key('people-actions-close'),
                tooltip: l.cancel,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            const Divider(),
            ...regular.take(5).map(tile),
            if (regular.length > 5)
              ExpansionTile(
                key: const Key('people-more-actions'),
                title: Text(l.peopleAction('more')),
                children: [
                  for (final group in groups.entries)
                    if (group.value.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          16,
                          16,
                          16,
                          4,
                        ),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            group.key,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                        ),
                      ),
                      ...group.value.map(tile),
                    ],
                ],
              ),
            if (actions.any((a) => a.destructive)) ...[
              const Divider(),
              ...actions.where((a) => a.destructive).map(tile),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  },
);
