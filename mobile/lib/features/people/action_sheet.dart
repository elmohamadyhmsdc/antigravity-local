import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../shared/crop_image.dart';

class PeopleMenuAction {
  const PeopleMenuAction(this.id, this.icon, {this.destructive = false});
  final String id;
  final IconData icon;
  final bool destructive;
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
        l.peopleAction(a.id == 'select' ? 'selection' : a.id),
        style: TextStyle(
          color: a.destructive ? Theme.of(context).colorScheme.error : null,
        ),
      ),
      onTap: () => Navigator.pop(context, a.id),
    );
    final regular = actions.where((a) => !a.destructive).toList();
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
            ),
            const Divider(),
            ...regular.take(5).map(tile),
            if (regular.length > 5)
              ExpansionTile(
                key: const Key('people-more-actions'),
                title: Text(l.peopleAction('more')),
                children: regular.skip(5).map(tile).toList(),
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
