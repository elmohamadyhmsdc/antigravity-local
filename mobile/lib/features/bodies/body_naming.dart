import 'package:drift/drift.dart' show Variable, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../shared/crop_image.dart';

/// What a grid of bodies needs from a row.
typedef BodyTile = ({int id, String? cropPath, int? mediaId});

Future<Map<int, BodyTile>> fetchBodyTiles(WidgetRef ref, List<int> ids) async {
  if (ids.isEmpty) return const {};
  final db = ref.read(databaseProvider);
  final rows = await db
      .customSelect(
        'SELECT id, crop_path, media_id FROM bodies WHERE hidden = 0 AND id IN (${List.filled(ids.length, '?').join(',')})',
        variables: [for (final id in ids) Variable.withInt(id)],
        readsFrom: {db.bodies},
      )
      .get();
  return {
    for (final r in rows)
      r.read<int>('id'): (
        id: r.read<int>('id'),
        cropPath: r.readNullable<String>('crop_path'),
        mediaId: r.readNullable<int>('media_id'),
      ),
  };
}

/// Roadmap 6: "name this pose" from an example body: name -> preview with remove-before-save -> save.
/// Shows a note and returns false when the pose cannot be measured or the user cancels.
Future<bool> nameBodyPose(
  BuildContext context,
  WidgetRef ref,
  int bodyId,
) async {
  final l = AppLocalizations.of(context);
  final categories = ref.read(bodyCategoriesProvider);
  final draft = await categories.draftPose(bodyId);
  if (!context.mounted) return false;
  if (draft == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.categoryNoPose)));
    return false;
  }
  final example = (await fetchBodyTiles(ref, [bodyId]))[bodyId];
  if (!context.mounted) return false;
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(
      title: l.categoryNamePoseTitle,
      cropPath: example?.cropPath,
    ),
  );
  if (!context.mounted || name == null) return false;
  final ids = [for (final m in draft.matches) m.bodyId];
  final rows = await fetchBodyTiles(ref, ids.take(400).toList());
  if (!context.mounted) return false;
  final removed = await showDialog<Set<int>>(
    context: context,
    builder: (_) =>
        _PreviewDialog(ids: ids.where(rows.containsKey).toList(), rows: rows),
  );
  if (removed == null) return false;
  await categories.savePose(draft, name.trim(), removed: removed);
  return true;
}

/// Same for an outfit ([personId] scopes the preview to that person's bodies).
Future<bool> nameBodyOutfit(
  BuildContext context,
  WidgetRef ref,
  int bodyId, {
  int? personId,
}) async {
  final l = AppLocalizations.of(context);
  final categories = ref.read(bodyCategoriesProvider);
  final result = await showDialog<(String, bool)>(
    context: context,
    builder: (_) => _NameDialog(
      title: l.categoryNameOutfitTitle,
      withLowerOnly: true,
      returnBoth: true,
    ),
  );
  if (!context.mounted || result == null) return false;
  final (name, lowerOnly) = result;
  final draft = await categories.draftOutfit(
    bodyId,
    lowerOnly: lowerOnly,
    personId: personId,
  );
  if (!context.mounted) return false;
  if (draft == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.categoryNoOutfit)));
    return false;
  }
  final ids = [for (final m in draft.matches) m.bodyId];
  final rows = await fetchBodyTiles(ref, ids.take(400).toList());
  if (!context.mounted) return false;
  final removed = await showDialog<Set<int>>(
    context: context,
    builder: (_) =>
        _PreviewDialog(ids: ids.where(rows.containsKey).toList(), rows: rows),
  );
  if (removed == null) return false;
  await categories.saveOutfit(draft, name.trim(), removed: removed);
  return true;
}

Future<bool> renamePoseCategory(AppDatabase db, int id, String newName) async {
  final trimmed = newName.trim();
  if (trimmed.isEmpty) return false;
  final count =
      await (db.update(db.poseCategories)..where((c) => c.id.equals(id))).write(
        PoseCategoriesCompanion(name: Value(trimmed)),
      );
  return count > 0;
}

Future<bool> renameOutfitCategory(
  AppDatabase db,
  int id,
  String newName,
) async {
  final trimmed = newName.trim();
  if (trimmed.isEmpty) return false;
  final count =
      await (db.update(db.outfitCategories)..where((c) => c.id.equals(id)))
          .write(OutfitCategoriesCompanion(name: Value(trimmed)));
  return count > 0;
}

Future<String?> promptRenameDialog(
  BuildContext context, {
  required String title,
  required String initialName,
  String? labelText,
}) {
  final controller = TextEditingController(text: initialName);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: labelText ?? 'Name'),
        onSubmitted: (val) => Navigator.pop(context, val),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    this.cropPath,
    this.withLowerOnly = false,
    this.returnBoth = false,
  });

  final String title;
  final String? cropPath;
  final bool withLowerOnly;
  final bool returnBoth;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _name = TextEditingController();
  bool _lowerOnly = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.cropPath != null)
              SizedBox(
                height: 140,
                width: 200,
                child: CropImage(
                  path: widget.cropPath,
                  fit: BoxFit.contain,
                  placeholderIcon: Icons.accessibility_new,
                ),
              ),
            TextField(
              key: const Key('category-name'),
              controller: _name,
              autofocus: true,
              maxLength: 80,
              decoration: InputDecoration(labelText: l.categoryNameHint),
              onChanged: (_) => setState(() {}),
            ),
            if (widget.withLowerOnly)
              CheckboxListTile(
                key: const Key('category-lower-only'),
                value: _lowerOnly,
                onChanged: (v) => setState(() => _lowerOnly = v ?? false),
                title: Text(l.categoryLowerOnly),
                contentPadding: EdgeInsets.zero,
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
          key: const Key('category-name-ok'),
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop<Object?>(
                  context,
                  widget.returnBoth
                      ? (_name.text.trim(), _lowerOnly)
                      : _name.text.trim(),
                ),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

class _PreviewDialog extends ConsumerStatefulWidget {
  const _PreviewDialog({required this.ids, required this.rows});

  final List<int> ids;
  final Map<int, BodyTile> rows;

  @override
  ConsumerState<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends ConsumerState<_PreviewDialog> {
  late final Set<int> _removed = {};

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.categoryPreviewTitle(widget.ids.length - _removed.length)),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: Column(
          children: [
            Text(l.categoryPreviewHint),
            const SizedBox(height: 8),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 90,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  childAspectRatio: 0.62,
                ),
                itemCount: widget.ids.length,
                itemBuilder: (context, i) {
                  final id = widget.ids[i];
                  final out = _removed.contains(id);
                  return InkWell(
                    key: Key('preview-$id'),
                    onTap: () => setState(
                      () => out ? _removed.remove(id) : _removed.add(id),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Opacity(
                          opacity: out ? 0.3 : 1,
                          child: CropImage(
                            path: widget.rows[id]?.cropPath,
                            placeholderIcon: Icons.accessibility_new,
                          ),
                        ),
                        Positioned(
                          right: 2,
                          top: 2,
                          child: Icon(
                            out ? Icons.cancel : Icons.check_circle,
                            size: 20,
                            color: out ? Colors.red : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
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
          key: const Key('category-save'),
          onPressed: () => Navigator.pop(context, _removed),
          child: Text(l.categorySave),
        ),
      ],
    );
  }
}
