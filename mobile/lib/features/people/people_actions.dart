import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/router.dart';
import '../../data/repositories/people_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../shared/crop_image.dart';
import '../shared/person_picker.dart';
import '../shared/empty_state.dart';
import 'action_face_picker.dart';
import 'action_sheet.dart';

List<PeopleMenuAction> personMenuActions(List<PersonSummary> people) {
  final single = people.length == 1;
  return [
    const PeopleMenuAction('select', Icons.checklist),
    if (single) const PeopleMenuAction('open', Icons.person_outline),
    const PeopleMenuAction('merge', Icons.merge),
    if (single) const PeopleMenuAction('rename', Icons.edit_outlined),
    PeopleMenuAction(
      people.every((p) => p.hidden) ? 'show' : 'hide',
      Icons.visibility_outlined,
    ),
    PeopleMenuAction(
      people.every((p) => p.pinned) ? 'unpin' : 'pin',
      Icons.push_pin_outlined,
    ),
    PeopleMenuAction(
      people.every((p) => p.favorite) ? 'unfavorite' : 'favorite',
      Icons.star_outline,
    ),
    if (single) ...[
      const PeopleMenuAction('cover', Icons.account_circle_outlined),
      const PeopleMenuAction('media', Icons.perm_media_outlined),
      const PeopleMenuAction('add', Icons.person_add_alt_1),
      const PeopleMenuAction('split', Icons.call_split),
      const PeopleMenuAction('suggestions', Icons.fact_check_outlined),
      const PeopleMenuAction('distinct', Icons.people_outline),
    ],
    PeopleMenuAction(
      people.every((p) => p.groupingLocked) ? 'unlock' : 'lock',
      Icons.lock_outline,
    ),
    if (single) const PeopleMenuAction('studio', Icons.face_retouching_natural),
    const PeopleMenuAction('export', Icons.ios_share),
    if (single) const PeopleMenuAction('details', Icons.info_outline),
    const PeopleMenuAction(
      'deletePerson',
      Icons.delete_outline,
      destructive: true,
    ),
  ];
}

List<PeopleMenuAction> faceMenuActions(List<FaceItem> faces) {
  final single = faces.length == 1;
  return [
    const PeopleMenuAction('select', Icons.checklist),
    if (faces.any((f) => f.personId != null))
      const PeopleMenuAction('remove', Icons.person_remove_outlined),
    if (single && faces.single.mediaId != null)
      const PeopleMenuAction('original', Icons.perm_media_outlined),
    const PeopleMenuAction('assign', Icons.drive_file_move_outline),
    const PeopleMenuAction('create', Icons.person_add_alt_1),
    if (faces.any((f) => f.personId != null))
      const PeopleMenuAction('reject', Icons.person_off_outlined),
    PeopleMenuAction(
      faces.every((f) => f.hidden) ? 'show' : 'hide',
      Icons.visibility_outlined,
    ),
    if (faces.any((f) => f.personId != null))
      const PeopleMenuAction('unassign', Icons.link_off),
    if (single) ...[
      if (faces.single.personId != null) ...[
        const PeopleMenuAction('open', Icons.person_outline),
        const PeopleMenuAction('cover', Icons.account_circle_outlined),
      ],
      const PeopleMenuAction('similar', Icons.person_search_outlined),
      const PeopleMenuAction('studio', Icons.face_retouching_natural),
      const PeopleMenuAction('save', Icons.save_alt),
      const PeopleMenuAction('details', Icons.info_outline),
    ],
    const PeopleMenuAction('export', Icons.ios_share),
    const PeopleMenuAction(
      'ignore',
      Icons.face_retouching_off,
      destructive: true,
    ),
    const PeopleMenuAction(
      'deleteFace',
      Icons.delete_outline,
      destructive: true,
    ),
  ];
}

Future<String?> askPeopleName(
  BuildContext context, {
  String? initial,
  String? title,
}) async {
  final l = AppLocalizations.of(context);
  var draft = initial ?? '';
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title ?? l.rename),
      content: TextFormField(
        key: const Key('action-name'),
        initialValue: draft,
        autofocus: true,
        maxLength: 120,
        onChanged: (v) => draft = v,
        decoration: InputDecoration(labelText: l.personNameLabel),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('action-name-save'),
          onPressed: () => Navigator.pop(context, draft.trim()),
          child: Text(l.peopleAction('done')),
        ),
      ],
    ),
  );
}

void peopleUpdated(BuildContext context, {Future<void> Function()? undo}) {
  if (!context.mounted) return;
  final l = AppLocalizations.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(l.peopleAction('updated')),
      action: undo == null
          ? null
          : SnackBarAction(
              label: l.peopleAction('undo'),
              onPressed: () async {
                try {
                  await undo();
                } catch (e) {
                  if (context.mounted) peopleError(context, e);
                }
              },
            ),
    ),
  );
}

void peopleError(BuildContext context, Object error) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).peopleActionError('$error')),
      ),
    );
  }
}

Future<void> showPeopleDetails(
  BuildContext context,
  String title,
  Map<String, Object?> values,
) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .8,
    ),
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final e in values.entries)
              if (e.value != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: SelectableText(
                    '${e.key}: ${e.key.endsWith('_seen') && e.value is int ? DateTime.fromMillisecondsSinceEpoch(e.value as int).toLocal() : e.value}',
                  ),
                ),
          ],
        ),
      ),
    ),
  ),
);

Future<void> runPersonAction(
  BuildContext context,
  WidgetRef ref,
  List<PersonSummary> people,
  String action,
) async {
  if (people.isEmpty || action == 'select') return;
  final repo = ref.read(peopleRepositoryProvider);
  final l = AppLocalizations.of(context);
  final ids = people.map((p) => p.id).toList();
  final p = people.first;
  try {
    switch (action) {
      case 'open':
      case 'media':
      case 'suggestions':
        context.push(
          '${Routes.people}/${p.id}?tab=${action == 'media'
              ? 1
              : action == 'suggestions'
              ? 3
              : 0}',
        );
        return;
      case 'rename':
        final name = await askPeopleName(context, initial: p.name);
        if (name == null) return;
        await repo.renamePerson(p.id, name);
        if (context.mounted) {
          peopleUpdated(context, undo: () => repo.renamePerson(p.id, p.name));
        }
        return;
      case 'hide':
      case 'show':
      case 'pin':
      case 'unpin':
      case 'favorite':
      case 'unfavorite':
      case 'lock':
      case 'unlock':
        if (action == 'lock') {
          final yes = await confirm(
            context,
            title: l.peopleAction(action),
            body: l.peopleAction('lockedNote'),
            confirmLabel: l.peopleAction('lock'),
            cancelLabel: l.cancel,
          );
          if (!yes) return;
        }
        final undo = await repo.setPersonFlags(
          ids,
          hidden: action == 'hide'
              ? true
              : action == 'show'
              ? false
              : null,
          pinned: action == 'pin'
              ? true
              : action == 'unpin'
              ? false
              : null,
          favorite: action == 'favorite'
              ? true
              : action == 'unfavorite'
              ? false
              : null,
          groupingLocked: action == 'lock'
              ? true
              : action == 'unlock'
              ? false
              : null,
        );
        if (context.mounted) peopleUpdated(context, undo: undo);
        return;
      case 'merge':
        await _merge(context, ref, people);
        return;
      case 'cover':
        final option = await showPeopleActionSheet(
          context,
          title: l.peopleAction('cover'),
          actions: const [
            PeopleMenuAction('bestCover', Icons.auto_awesome),
            PeopleMenuAction('chooseCover', Icons.face_outlined),
          ],
        );
        if (!context.mounted || option == null) return;
        if (option == 'bestCover') {
          await repo.bestCover(p.id);
        } else {
          final faces = await pickActionFaces(
            context,
            title: l.peopleAction('chooseCover'),
            faces: repo.personFaces(p.id),
            single: true,
          );
          if (faces == null) return;
          await repo.setAvatar(p.id, faces.single);
        }
      case 'add':
      case 'split':
        final faces = await pickActionFaces(
          context,
          title: l.peopleAction(action),
          faces: action == 'add'
              ? repo.availableFaces(excludePersonId: p.id)
              : repo.personFaces(p.id),
        );
        if (faces == null || faces.isEmpty || !context.mounted) return;
        if (action == 'add') {
          await repo.assignFaces(faces, p.id);
        } else {
          final name = await askPeopleName(
            context,
            title: l.peopleAction('create'),
          );
          if (name == null) return;
          await repo.splitFaces(p.id, faces, name);
        }
      case 'distinct':
        final choice = await pickPerson(
          context,
          excludePersonId: p.id,
          allowNew: false,
          title: l.peopleAction('distinct'),
        );
        if (choice?.personId == null) return;
        await repo.markDistinct(p.id, choice!.personId!);
      case 'studio':
        context.push('${Routes.reface}?person=${p.id}');
        return;
      case 'export':
        final faces = <FaceItem>[];
        for (final id in ids) {
          faces.addAll(await repo.personFaces(id));
        }
        if (!context.mounted) return;
        final selected = await pickActionFaces(
          context,
          title: l.peopleAction('export'),
          faces: Future.value(faces.where((f) => !f.hidden).toList()),
        );
        if (selected != null && context.mounted) {
          await exportPeopleFaces(
            context,
            ref,
            faces.where((f) => selected.contains(f.id)).toList(),
          );
        }
        return;
      case 'details':
        final details = await repo.personDetails(p.id);
        if (context.mounted) {
          await showPeopleDetails(context, personName(l, p), details);
        }
        return;
      case 'deletePerson':
        final yes = await confirm(
          context,
          title: l.peopleAction('deletePerson'),
          body: l.peopleAction('deletePersonNote'),
          confirmLabel: l.delete,
          cancelLabel: l.cancel,
          destructive: true,
        );
        if (!yes) return;
        await repo.deletePeople(ids);
      default:
        return;
    }
    if (context.mounted) peopleUpdated(context);
  } catch (e) {
    if (context.mounted) peopleError(context, e);
  }
}

Future<void> _merge(
  BuildContext context,
  WidgetRef ref,
  List<PersonSummary> source,
) async {
  final repo = ref.read(peopleRepositoryProvider);
  final l = AppLocalizations.of(context);
  final choice = await pickPerson(
    context,
    excludePersonId: source.length == 1 ? source.single.id : null,
    title: l.mergeWith,
    allowNew: false,
  );
  if (choice?.personId == null || !context.mounted) return;
  final target = await repo.person(choice!.personId!);
  if (target == null || !context.mounted) return;
  final members = {
    for (final p in [...source, target]) p.id: p,
  }.values.toList();
  final allFaces = <FaceItem>[];
  for (final p in members) {
    allFaces.addAll(await repo.personFaces(p.id));
  }
  if (!context.mounted) return;
  var name = target.name ?? '';
  int? cover;
  final yes = await showDialog<bool>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, update) => AlertDialog(
        title: Text(l.mergeWith),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.peopleAction('mergeNote')),
              ListTile(
                leading: PersonAvatar(
                  cropPath: target.avatarCropPath,
                  radius: 24,
                ),
                title: Text(personName(l, target)),
                subtitle: Text(
                  l.facesCount(members.fold(0, (n, p) => n + p.faceCount)),
                ),
              ),
              TextFormField(
                key: const Key('merge-result-name'),
                initialValue: name,
                onChanged: (v) => name = v,
                maxLength: 120,
                decoration: InputDecoration(labelText: l.personNameLabel),
              ),
              TextButton.icon(
                onPressed: allFaces.isEmpty
                    ? null
                    : () async {
                        final chosen = await pickActionFaces(
                          dialog,
                          title: l.peopleAction('chooseCover'),
                          faces: Future.value(allFaces),
                          single: true,
                        );
                        if (chosen != null && dialog.mounted) {
                          update(() => cover = chosen.single);
                        }
                      },
                icon: const Icon(Icons.account_circle_outlined),
                label: Text(l.peopleAction('chooseCover')),
              ),
              if (cover != null)
                PersonAvatar(
                  cropPath: allFaces.firstWhere((f) => f.id == cover).cropPath,
                  radius: 24,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const Key('people-merge-confirm'),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(l.peopleAction('merge')),
          ),
        ],
      ),
    ),
  );
  if (yes != true) return;
  await repo.mergeMany(
    members.map((p) => p.id),
    target.id,
    name: name.trim(),
    coverFaceId: cover,
  );
  if (context.mounted) peopleUpdated(context);
}

Future<void> runFaceAction(
  BuildContext context,
  WidgetRef ref,
  List<FaceItem> faces,
  String action,
) async {
  if (faces.isEmpty || action == 'select') return;
  final repo = ref.read(peopleRepositoryProvider);
  final files = ref.read(fileStoreProvider);
  final l = AppLocalizations.of(context);
  final ids = faces.map((f) => f.id).toList();
  final f = faces.first;
  try {
    switch (action) {
      case 'original':
        final time = await repo.faceTimestamp(f.id);
        if (context.mounted && f.mediaId != null) {
          context.push('${Routes.media}/${f.mediaId}?at=${time ?? 0}');
        }
        return;
      case 'open':
        if (f.personId != null) context.push('${Routes.people}/${f.personId}');
        return;
      case 'assign':
        final choice = await pickPerson(
          context,
          title: l.assignFacesTitle(ids.length),
        );
        if (choice == null) return;
        if (choice.isNew) {
          await repo.createPerson(name: choice.newName, faceIds: ids);
        } else {
          await repo.assignFaces(ids, choice.personId!);
        }
      case 'create':
        final name = await askPeopleName(
          context,
          title: l.peopleAction('create'),
        );
        if (name == null) return;
        final sources = faces.map((f) => f.personId).whereType<int>().toSet();
        if (sources.length == 1) {
          await repo.splitFaces(sources.single, ids, name);
        } else {
          await repo.createPerson(name: name, faceIds: ids);
        }
      case 'remove':
        final how = await showPeopleActionSheet(
          context,
          title: l.peopleAction('remove'),
          cropPath: faces.length == 1 ? f.cropPath : null,
          subtitle: l.selectedCount(faces.length),
          actions: const [
            PeopleMenuAction('someoneElse', Icons.person_off_outlined),
            PeopleMenuAction('notAFace', Icons.face_retouching_off),
            PeopleMenuAction('moveTo', Icons.drive_file_move_outline),
          ],
        );
        if (how == null || !context.mounted) return;
        return runFaceAction(context, ref, faces, switch (how) {
          'someoneElse' =>
            'reject', // face_rejections: never suggested for them again
          'notAFace' => 'hide', // out of people, matching and grouping
          _ => 'assign',
        });
      case 'reject':
        await repo.rejectFaces(ids);
      case 'unassign':
        await repo.clearAssignments(ids);
      case 'hide':
      case 'show':
        final undo = await repo.setFacesHidden(ids, action == 'hide');
        if (context.mounted) peopleUpdated(context, undo: undo);
        return;
      case 'cover':
        if (f.personId != null) await repo.setAvatar(f.personId!, f.id);
      case 'studio':
        context.push('${Routes.reface}?face=${f.id}');
        return;
      case 'save':
        if (f.cropPath == null) throw StateError(l.peopleAction('emptyExport'));
        await PhotoManager.editor.saveImage(
          await files.resolve(f.cropPath!).readAsBytes(),
          filename: 'face-${f.id}.jpg',
        );
      case 'export':
        await exportPeopleFaces(context, ref, faces);
        return;
      case 'similar':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => SimilarFacesScreen(face: f)),
        );
        return;
      case 'details':
        final details = await repo.faceDetails(f.id);
        if (context.mounted) {
          await showPeopleDetails(context, l.peopleAction('details'), details);
        }
        return;
      case 'ignore':
      case 'deleteFace':
        final yes = await confirm(
          context,
          title: l.peopleAction(action),
          body: l.peopleAction('deleteFaceNote'),
          confirmLabel: l.delete,
          cancelLabel: l.cancel,
          destructive: true,
        );
        if (!yes) return;
        await repo.deleteFaces(ids);
      default:
        return;
    }
    if (context.mounted) peopleUpdated(context);
  } catch (e) {
    if (context.mounted) peopleError(context, e);
  }
}

Future<void> exportPeopleFaces(
  BuildContext context,
  WidgetRef ref,
  List<FaceItem> faces,
) async {
  final l = AppLocalizations.of(context);
  final repo = ref.read(peopleRepositoryProvider);
  final files = ref.read(fileStoreProvider);
  final library = ref.read(libraryRepositoryProvider);
  final mode = await showPeopleActionSheet(
    context,
    title: l.peopleAction('export'),
    actions: const [
      PeopleMenuAction('exportCrops', Icons.face_outlined),
      PeopleMenuAction('exportOriginals', Icons.perm_media_outlined),
    ],
  );
  if (mode == null || !context.mounted) return;
  final directory = await Directory(
    (await getTemporaryDirectory()).path,
  ).createTemp('people-export-');
  final output = File('${directory.path}/people.zip');
  final archive = ZipFileEncoder()..create(output.path);
  if (!context.mounted) {
    archive.close();
    return;
  }
  final progress = ValueNotifier<int>(0);
  final navigator = Navigator.of(context, rootNavigator: true);
  final progressRoute = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(l.peopleAction('export')),
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, done, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: faces.isEmpty ? null : done / faces.length,
              ),
              const SizedBox(height: 12),
              Text('$done / ${faces.length}'),
            ],
          ),
        ),
      ),
    ),
  );
  unawaited(navigator.push(progressRoute));
  var count = 0;
  final details = <Map<String, Object?>>[];
  final mediaIds = <int>{};
  try {
    for (final f in faces) {
      details.add(await repo.faceDetails(f.id));
      if (f.cropPath != null) {
        final crop = files.resolve(f.cropPath!);
        if (await crop.exists()) {
          await archive.addFile(crop, 'faces/${f.id}.jpg');
          count++;
        }
      }
      if (mode == 'exportOriginals' &&
          f.mediaId != null &&
          mediaIds.add(f.mediaId!)) {
        final row = await library.mediaById(f.mediaId!);
        final entity = row == null
            ? null
            : await AssetEntity.fromId(row.assetId);
        final original = await entity?.originFile;
        if (original == null || !await original.exists()) {
          throw StateError(
            'Original media ${f.mediaId} is no longer accessible.',
          );
        }
        final extension = original.uri.pathSegments.last.split('.').last;
        await archive.addFile(original, 'originals/${f.mediaId}.$extension');
        count++;
      }
      progress.value++;
    }
    final manifest = utf8.encode(jsonEncode({'faces': details}));
    archive.addArchiveFile(ArchiveFile.bytes('details.json', manifest));
  } finally {
    try {
      archive.close();
    } finally {
      if (progressRoute.isActive) navigator.removeRoute(progressRoute);
      progress.dispose();
    }
  }
  if (count == 0) throw StateError(l.peopleAction('emptyExport'));
  if (context.mounted) {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(output.path)],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }
}

class SimilarFacesScreen extends ConsumerStatefulWidget {
  const SimilarFacesScreen({super.key, required this.face});
  final FaceItem face;
  @override
  ConsumerState<SimilarFacesScreen> createState() => _SimilarFacesState();
}

class _SimilarFacesState extends ConsumerState<SimilarFacesScreen> {
  late Future<List<(FaceItem, double)>> results;
  final selected = <int>{};
  @override
  void initState() {
    super.initState();
    results = ref.read(peopleRepositoryProvider).similarFaces(widget.face.id);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.peopleAction('similar'))),
      body: FutureBuilder(
        future: results,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(l.peopleActionError('${snapshot.error}')),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final hits = snapshot.data!;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l.peopleAction('similarNote')),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final (f, score) in hits)
                      CheckboxListTile(
                        key: Key('similar-face-${f.id}'),
                        secondary: PersonAvatar(
                          cropPath: f.cropPath,
                          radius: 24,
                        ),
                        title: Text(
                          '${(score.clamp(0, 1) * 100).toStringAsFixed(1)}%',
                        ),
                        subtitle: Text('Face ${f.id}'),
                        value: selected.contains(f.id),
                        onChanged: (_) => setState(() {
                          if (!selected.remove(f.id)) selected.add(f.id);
                        }),
                      ),
                  ],
                ),
              ),
              if (selected.isNotEmpty)
                SafeArea(
                  top: false,
                  child: FilledButton(
                    onPressed: () async {
                      await runFaceAction(
                        context,
                        ref,
                        hits
                            .where((h) => selected.contains(h.$1.id))
                            .map((h) => h.$1)
                            .toList(),
                        'assign',
                      );
                      if (mounted) setState(selected.clear);
                    },
                    child: Text(l.peopleAction('assign')),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
