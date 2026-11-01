import 'package:drift/drift.dart'
    show Variable, OrderingTerm, BooleanExpressionOperators;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/db/app_database.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../shared/crop_image.dart';
import '../shared/empty_state.dart';
import 'pose_visuals.dart';

class EquipmentTab extends ConsumerStatefulWidget {
  const EquipmentTab({super.key, this.personId});
  final int? personId;
  @override
  ConsumerState<EquipmentTab> createState() => _EquipmentTabState();
}

class _EquipmentTabState extends ConsumerState<EquipmentTab> {
  List<EquipmentObjectRow> objects = [];
  Map<int, MediaRow> photos = {};
  String? label;
  bool loaded = false, busy = false, failed = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final all = await ref.read(equipmentLibraryProvider).objects();
      final db = ref.read(databaseProvider);
      final photoRows = await (db.select(
        db.media,
      )..where((m) => m.id.isIn(all.map((o) => o.mediaId)))).get();
      final peopleBodies = widget.personId == null
          ? <int>{}
          : {
              for (final r
                  in await db
                      .customSelect(
                        '''SELECT b.id FROM bodies b LEFT JOIN faces f ON f.id = b.face_id
          WHERE COALESCE(f.person_id, b.person_id) = ?''',
                        variables: [Variable.withInt(widget.personId!)],
                      )
                      .get())
                r.read<int>('id'),
            };
      if (mounted) {
        setState(() {
          objects = [
            for (final o in all)
              if (widget.personId == null || peopleBodies.contains(o.bodyId)) o,
          ];
          photos = {for (final p in photoRows) p.id: p};
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

  Future<void> detectPending() async {
    setState(() => busy = true);
    try {
      await ref
          .read(equipmentLibraryProvider)
          .run(
            shouldContinue: () =>
                mounted &&
                !ref.read(scanEngineProvider).isRunning &&
                ref.read(serverStatusProvider).value is ServerReady,
          );
      await load();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ready = ref.watch(serverStatusProvider).value;
    final canDetect =
        ready is ServerReady &&
        ready.capabilities.engines.equipment &&
        !ref.watch(scanEngineProvider).isRunning;
    if (!loaded) return const Center(child: CircularProgressIndicator());
    if (failed) {
      return EmptyState(
        icon: Icons.refresh,
        title: l.bodiesLoadFailed,
        actionLabel: l.bodiesRetry,
        onAction: load,
      );
    }
    final shown = objects
        .where((o) => label == null || o.label == label)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l.equipmentIntro),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            key: const Key('equipment-detect-pending'),
            onPressed: busy || !canDetect ? null : detectPending,
            icon: const Icon(Icons.image_search_outlined),
            label: Text(l.equipmentDetectPending),
          ),
        ),
        if (!canDetect)
          Text(
            l.equipmentConnect,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (busy) const LinearProgressIndicator(),
        Wrap(
          spacing: 8,
          children: [
            for (final name in {
              for (final o in objects) o.label,
            }.toList()..sort())
              FilterChip(
                key: Key('equipment-filter-$name'),
                label: Text(name),
                selected: label == name,
                onSelected: (on) => setState(() => label = on ? name : null),
              ),
          ],
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(l.equipmentEmpty),
          ),
        for (final mediaId in {for (final o in shown) o.mediaId})
          Card(
            key: Key('equipment-photo-$mediaId'),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (photos[mediaId] case final photo?)
                  SizedBox(
                    height: 160,
                    child: GroupPhotoPreview(assetId: photo.assetId),
                  ),
                ListTile(
                  key: Key('equipment-review-$mediaId'),
                  title: Text(
                    {
                      for (final o in shown)
                        if (o.mediaId == mediaId) o.label,
                    }.join(' · '),
                  ),
                  subtitle: Text(l.equipmentReviewHint),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => EquipmentPhotoScreen(mediaId: mediaId),
                      ),
                    );
                    await load();
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class EquipmentPhotoScreen extends ConsumerStatefulWidget {
  const EquipmentPhotoScreen({super.key, required this.mediaId});
  final int mediaId;
  @override
  ConsumerState<EquipmentPhotoScreen> createState() => _EquipmentPhotoState();
}

class _EquipmentPhotoState extends ConsumerState<EquipmentPhotoScreen> {
  MediaRow? photo;
  List<BodyRow> bodies = [];
  List<EquipmentObjectRow> objects = [];
  bool loaded = false, busy = false;
  String? message;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final db = ref.read(databaseProvider);
    final p = await (db.select(
      db.media,
    )..where((m) => m.id.equals(widget.mediaId))).getSingleOrNull();
    final b =
        await (db.select(db.bodies)
              ..where(
                (b) =>
                    b.mediaId.equals(widget.mediaId) &
                    b.kind.equals('person') &
                    b.frameNumber.isNull(),
              )
              ..orderBy([(b) => OrderingTerm.asc(b.id)]))
            .get();
    final o = await ref
        .read(equipmentLibraryProvider)
        .objects(mediaId: widget.mediaId);
    if (mounted) {
      setState(() {
        photo = p;
        bodies = b;
        objects = o;
        loaded = true;
      });
    }
  }

  Future<void> detect() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await ref.read(equipmentLibraryProvider).detectPhoto(widget.mediaId);
      await load();
    } catch (_) {
      if (mounted) {
        setState(() => message = AppLocalizations.of(context).equipmentFailed);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(EquipmentObjectRow object) async {
    final result = await showDialog<(String, int?)>(
      context: context,
      builder: (_) => _EquipmentEdit(object: object, bodies: bodies),
    );
    if (result == null || !mounted) return;
    await ref
        .read(equipmentLibraryProvider)
        .correct(object, result.$1, result.$2);
    await load();
  }

  Future<void> add() async {
    final blank = EquipmentObjectRow(
      id: 0,
      mediaId: widget.mediaId,
      objectKey: '',
      label: '',
      x: 0,
      y: 0,
      w: 0,
      h: 0,
      state: 'confirmed',
    );
    final result = await showDialog<(String, int?)>(
      context: context,
      builder: (_) => _EquipmentEdit(object: blank, bodies: bodies),
    );
    if (result == null || !mounted) return;
    await ref
        .read(equipmentLibraryProvider)
        .add(widget.mediaId, result.$1, result.$2);
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final status = ref.watch(serverStatusProvider).value;
    final canDetect =
        status is ServerReady &&
        status.capabilities.engines.equipment &&
        !ref.watch(scanEngineProvider).isRunning;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.bodiesTabEquipment),
        actions: [
          IconButton(
            tooltip: l.bodyActionOpenPhoto,
            icon: const Icon(Icons.open_in_new),
            onPressed: () => context.push('${Routes.media}/${widget.mediaId}'),
          ),
        ],
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (photo case final p?)
                  SizedBox(
                    height: 240,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: (p.width ?? 1) / (p.height ?? 1),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            GroupPhotoPreview(assetId: p.assetId),
                            IgnorePointer(
                              child: CustomPaint(
                                painter: _EquipmentBoxes(
                                  objects,
                                  Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(l.equipmentIntro),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  key: const Key('equipment-detect-photo'),
                  onPressed: busy || !canDetect ? null : detect,
                  icon: const Icon(Icons.image_search),
                  label: Text(l.equipmentDetectPhoto),
                ),
                TextButton.icon(
                  key: const Key('equipment-add'),
                  onPressed: busy ? null : add,
                  icon: const Icon(Icons.add),
                  label: Text(l.equipmentAdd),
                ),
                if (!canDetect) Text(l.equipmentConnect),
                if (busy) ...[
                  const LinearProgressIndicator(),
                  Text(l.equipmentDetecting),
                ],
                if (message != null)
                  Text(
                    message!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (!busy && objects.isEmpty) Text(l.equipmentEmpty),
                for (final object in objects)
                  ListTile(
                    key: Key('equipment-object-${object.id}'),
                    contentPadding: EdgeInsets.zero,
                    leading: object.bodyId == null
                        ? const Icon(Icons.groups_outlined)
                        : SizedBox(
                            width: 48,
                            height: 64,
                            child: CropImage(
                              path: bodies
                                  .where((b) => b.id == object.bodyId)
                                  .firstOrNull
                                  ?.cropPath,
                              placeholderIcon: Icons.accessibility_new,
                            ),
                          ),
                    title: Text(object.label),
                    subtitle: Text(
                      '${object.state == 'confirmed' ? l.equipmentConfirmed : l.equipmentSuggested} · ${object.bodyId == null ? l.equipmentShared : l.equipmentPerson(bodies.indexWhere((b) => b.id == object.bodyId) + 1)}',
                    ),
                    onTap: () => edit(object),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          key: Key('equipment-edit-${object.id}'),
                          tooltip: l.equipmentEdit,
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => edit(object),
                        ),
                        IconButton(
                          key: Key('equipment-reject-${object.id}'),
                          tooltip: l.equipmentReject,
                          icon: const Icon(Icons.close),
                          onPressed: () async {
                            await ref
                                .read(equipmentLibraryProvider)
                                .reject(object);
                            await load();
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _EquipmentBoxes extends CustomPainter {
  _EquipmentBoxes(this.objects, this.color);
  final List<EquipmentObjectRow> objects;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    for (final o in objects) {
      if (o.w <= 0 || o.h <= 0) continue;
      final rect = Rect.fromLTWH(
        o.x * size.width,
        o.y * size.height,
        o.w * size.width,
        o.h * size.height,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EquipmentBoxes old) =>
      old.objects != objects || old.color != color;
}

class _EquipmentEdit extends StatefulWidget {
  const _EquipmentEdit({required this.object, required this.bodies});
  final EquipmentObjectRow object;
  final List<BodyRow> bodies;
  @override
  State<_EquipmentEdit> createState() => _EquipmentEditState();
}

class _EquipmentEditState extends State<_EquipmentEdit> {
  late final name = TextEditingController(text: widget.object.label);
  late int owner = widget.object.bodyId ?? -1;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.equipmentEdit),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('equipment-label'),
              controller: name,
              maxLength: 80,
              decoration: InputDecoration(labelText: l.categoryNameHint),
              onChanged: (_) => setState(() {}),
            ),
            DropdownButtonFormField<int>(
              key: const Key('equipment-owner'),
              initialValue: owner,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.equipmentOwner),
              items: [
                DropdownMenuItem(value: -1, child: Text(l.equipmentShared)),
                for (var i = 0; i < widget.bodies.length; i++)
                  DropdownMenuItem(
                    value: widget.bodies[i].id,
                    child: Text(l.equipmentPerson(i + 1)),
                  ),
              ],
              onChanged: (v) => setState(() => owner = v ?? -1),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < widget.bodies.length; i++)
                  SizedBox(
                    width: 64,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 80,
                          child: CropImage(
                            path: widget.bodies[i].cropPath,
                            placeholderIcon: Icons.accessibility_new,
                          ),
                        ),
                        Text(l.equipmentPerson(i + 1)),
                      ],
                    ),
                  ),
              ],
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
          key: const Key('equipment-save'),
          onPressed: name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, (
                  name.text.trim(),
                  owner == -1 ? null : owner,
                )),
          child: Text(l.categorySave),
        ),
      ],
    );
  }
}
