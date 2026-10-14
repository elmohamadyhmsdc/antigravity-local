import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/people_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import 'crop_image.dart';

/// What the user chose in the picker: an existing person, or "make a new person" (optionally named).
class PersonChoice {
  const PersonChoice.existing(this.personId) : newName = null, isNew = false;
  const PersonChoice.newPerson([this.newName]) : personId = null, isNew = true;

  final int? personId;
  final String? newName;
  final bool isNew;
}

/// Bottom sheet: pick a person to assign faces to (with search and "New person").
Future<PersonChoice?> pickPerson(
  BuildContext context, {
  int? excludePersonId,
  String? title,
  bool allowNew = true,
}) {
  return showModalBottomSheet<PersonChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _PersonPickerSheet(
      excludePersonId: excludePersonId,
      title: title,
      allowNew: allowNew,
    ),
  );
}

class _PersonPickerSheet extends ConsumerStatefulWidget {
  const _PersonPickerSheet({
    required this.excludePersonId,
    required this.title,
    required this.allowNew,
  });

  final int? excludePersonId;
  final String? title;
  final bool allowNew;

  @override
  ConsumerState<_PersonPickerSheet> createState() => _PersonPickerSheetState();
}

class _PersonPickerSheetState extends ConsumerState<_PersonPickerSheet> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final people = ref.watch(peopleProvider).value ?? const <PersonSummary>[];
    final shown = [
      for (final p in people)
        if (p.id != widget.excludePersonId &&
            personName(
              l10n,
              p,
            ).toLowerCase().contains(_query.trim().toLowerCase()))
          p,
    ];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              children: [
                Text(
                  widget.title ?? l10n.pickPersonTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('person-picker-search'),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: l10n.searchPeopleHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              children: [
                if (widget.allowNew)
                  ListTile(
                    key: const Key('person-picker-new'),
                    leading: const CircleAvatar(
                      child: Icon(Icons.person_add_alt_1),
                    ),
                    title: Text(l10n.newPerson),
                    onTap: () => _askNewName(context),
                  ),
                for (final p in shown)
                  ListTile(
                    key: Key('person-picker-${p.id}'),
                    leading: PersonAvatar(
                      cropPath: p.avatarCropPath,
                      radius: 20,
                    ),
                    title: Text(personName(l10n, p)),
                    subtitle: Text(l10n.facesCount(p.faceCount)),
                    onTap: () =>
                        Navigator.pop(context, PersonChoice.existing(p.id)),
                  ),
                if (shown.isEmpty && !widget.allowNew)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(l10n.noPeopleYet)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _askNewName(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.newPerson),
        content: TextField(
          key: const Key('new-person-name'),
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: l10n.personNameLabel,
            hintText: l10n.personNameOptional,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l10n.create),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && context.mounted) {
      Navigator.pop(context, PersonChoice.newPerson(name));
    }
  }
}

/// Creates the person if the choice was "new", then returns the person's id.
Future<int> resolveChoice(
  WidgetRef ref,
  PersonChoice choice, {
  Iterable<int> faceIds = const [],
}) async {
  final people = ref.read(peopleRepositoryProvider);
  if (choice.isNew) {
    return people.createPerson(name: choice.newName, faceIds: faceIds);
  }
  return choice.personId!;
}
