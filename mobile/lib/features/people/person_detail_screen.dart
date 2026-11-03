import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/repositories/media_queries.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/people_repository.dart';
import '../../data/repositories/review_questions.dart';
import '../../data/repositories/review_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../studio_providers.dart';
import '../library/media_grid.dart';
import '../jobs/jobs_screen.dart' show jobStatusLabel, jobTypeLabel;
import '../shared/crop_image.dart';
import '../shared/empty_state.dart';
import '../review/album_review_screen.dart';
import '../review/review_banner.dart';
import '../review/review_words.dart';
import '../shared/person_picker.dart';
import 'face_grid.dart';
import 'action_sheet.dart';
import 'people_actions.dart';
import 'training_export_dialog.dart';
import 'identity_groups_screen.dart';
import '../video_actions/video_actions_screen.dart';

final personProvider = StreamProvider.autoDispose.family<PersonSummary?, int>(
  (ref, id) => ref.watch(peopleRepositoryProvider).watchPerson(id),
);

final personBodiesProvider = StreamProvider.autoDispose
    .family<List<BodyItem>, int>(
      (ref, id) => ref.watch(peopleRepositoryProvider).watchBodies(id),
    );

final personMatchesProvider = StreamProvider.autoDispose
    .family<List<ReviewMatchFace>, int>((ref, id) {
      final kind = ref.watch(personProvider(id)).value?.kind ?? 'person';
      return ref
          .watch(reviewRepositoryByKindProvider(kind))
          .watchMatchesFor(id);
    });

/// Possible duplicate people / outfit links of one kind ('person' | 'character').
final reviewDuplicatesProvider = StreamProvider.autoDispose
    .family<List<ReviewDuplicateItem>, String>(
      (ref, kind) =>
          ref.watch(reviewRepositoryByKindProvider(kind)).watchDuplicates(),
    );

final reviewBodyLinksProvider = StreamProvider.autoDispose
    .family<List<ReviewBodyLinkItem>, String>(
      (ref, kind) =>
          ref.watch(reviewRepositoryByKindProvider(kind)).watchBodyLinks(),
    );

/// S08 - one person: faces, photos, bodies and what the PC suggests about them.
class PersonDetailScreen extends ConsumerWidget {
  const PersonDetailScreen({
    super.key,
    required this.personId,
    this.initialTab = 0,
  });

  final int personId;
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final person = ref.watch(personProvider(personId));
    final pending = albumReviewCount(
      ref,
      personId,
      person.value?.kind ?? 'person',
    );
    return person.when(
      loading: () => Scaffold(appBar: AppBar(), body: const LoadingBox()),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: RetryState(
          onRetry: () => ref.invalidate(personProvider(personId)),
        ),
      ),
      data: (p) {
        if (p == null) {
          return Scaffold(
            appBar: AppBar(),
            body: EmptyState(
              icon: Icons.person_off_outlined,
              title: l10n.personGone,
            ),
          );
        }
        return DefaultTabController(
          length: p.kind == 'character' ? 2 : 3,
          initialIndex: initialTab <= 1 ? 0 : 1,
          child: Scaffold(
            appBar: AppBar(
              leading: BackButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(Routes.people);
                  }
                },
              ),
              title: InkWell(
                key: const Key('person-title'),
                onTap: () => _rename(context, ref, p),
                onLongPress: () => _menu(context, ref, p),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PersonAvatar(cropPath: p.avatarCropPath, radius: 16),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        personName(l10n, p),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Actions in media',
                  icon: const Icon(Icons.motion_photos_on_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => VideoActionsScreen(personId: personId),
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  key: const Key('person-use-studio'),
                  tooltip: l10n.useInStudio,
                  onPressed: () =>
                      context.push('${Routes.reface}?person=$personId'),
                  icon: const Icon(Icons.face_retouching_natural),
                ),
                IconButton(
                  key: const Key('person-menu'),
                  tooltip: l10n.peopleAction('more'),
                  onPressed: () => _menu(context, ref, p),
                  icon: const Icon(Icons.more_horiz),
                ),
              ],
              bottom: TabBar(
                tabs: [
                  const Tab(key: Key('tab-photos'), text: 'Media'),
                  const Tab(text: 'Identity'),
                  if (p.kind == 'person') const Tab(text: 'Models'),
                ],
              ),
            ),
            body: Column(
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const Key('person-identity-group'),
                    icon: const Icon(Icons.folder_outlined),
                    label: Text(p.groupName ?? l10n.identityGroupAssign),
                    onPressed: () => assignIdentityGroup(context, ref, [p.id]),
                  ),
                ),
                if (pending > 0)
                  ReviewBanner(
                    key: const Key('album-review-banner'),
                    icon: Icons.photo_library_outlined,
                    title: l10n.albumReviewBanner(pending),
                    body: l10n.albumReviewBannerBody(personName(l10n, p)),
                    onTap: () => openAlbumReview(context, p),
                  ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _PersonMedia(personId: personId),
                      DefaultTabController(
                        length: 4,
                        initialIndex: initialTab == 2
                            ? 1
                            : (initialTab == 3 ? 2 : 0),
                        child: Column(
                          children: [
                            TabBar(
                              isScrollable: true,
                              tabAlignment: TabAlignment.start,
                              tabs: [
                                Tab(
                                  key: const Key('tab-faces'),
                                  text: l10n.tabFaces(p.faceCount),
                                ),
                                Tab(
                                  key: const Key('tab-bodies'),
                                  text: l10n.tabBodies,
                                ),
                                Tab(
                                  key: const Key('tab-suggestions'),
                                  text: l10n.tabSuggestions,
                                ),
                                const Tab(text: 'Saved identities'),
                              ],
                            ),
                            ListTile(
                              leading: const Icon(Icons.draw_outlined),
                              title: Text(l10n.marksTitle),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push(
                                '${Routes.marks}?personId=$personId',
                              ),
                            ),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  FaceGrid(personId: personId, kind: p.kind),
                                  _BodiesTab(personId: personId, kind: p.kind),
                                  _SuggestionsTab(person: p),
                                  _SavedIdentities(
                                    personId: personId,
                                    allowStudio: p.kind == 'person',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (p.kind == 'person')
                        _PersonModels(
                          personId: personId,
                          avatarPath: p.avatarCropPath,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _menu(
    BuildContext context,
    WidgetRef ref,
    PersonSummary p,
  ) async {
    final l = AppLocalizations.of(context);
    final actions = personMenuActions([p]);
    final action = await showPeopleActionSheet(
      context,
      title: personName(l, p),
      cropPath: p.avatarCropPath,
      subtitle: l.facesCount(p.faceCount),
      actions: [
        for (final id in ['rename', 'add', 'cover', 'merge', 'suggestions'])
          actions.firstWhere((a) => a.id == id),
        for (final a in actions)
          if (!{
            'select',
            'open',
            'rename',
            'add',
            'cover',
            'merge',
            'suggestions',
            'deletePerson',
          }.contains(a.id))
            a,
        PeopleMenuAction('marks', Icons.draw_outlined, label: l.marksTitle),
        PeopleMenuAction(
          'bodies',
          Icons.accessibility_new,
          label: l.bodiesTitle,
        ),
        if (p.kind == 'person')
          PeopleMenuAction(
            'curateLora',
            Icons.auto_awesome,
            label: 'تدريب Character LoRA (تحديد ذكي)',
          ),
        // the export reads the person's own faces and bodies: it works the same for a drawn character
        PeopleMenuAction(
          'exportTraining',
          Icons.model_training,
          label: l.exportTrainingTitle,
        ),
        PeopleMenuAction(
          'delete',
          Icons.delete_outline,
          label: l.deletePerson,
          destructive: true,
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'curateLora':
        context.push('${Routes.studioCuration}/$personId?name=${Uri.encodeComponent(personName(l, p))}');
      case 'rename':
        await _rename(context, ref, p);
      case 'merge':
        await _merge(context, ref, p);
      case 'delete':
        await _delete(context, ref, p);
      case 'marks':
        context.push('${Routes.marks}?personId=$personId');
      case 'bodies':
        context.push('${Routes.bodies}?personId=$personId');
      case 'exportTraining':
        await showTrainingExportDialog(
          context,
          person: p,
          personName: personName(l, p),
        );
      default:
        await runPersonAction(context, ref, [p], action);
    }
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    PersonSummary p,
  ) async {
    final l10n = AppLocalizations.of(context);
    var draft = p.isNamed ? (p.name ?? '') : '';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.rename),
        content: TextFormField(
          key: const Key('rename-field'),
          initialValue: draft,
          onChanged: (value) => draft = value,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: l10n.personNameLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('rename-save'),
            onPressed: () => Navigator.pop(context, draft),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (name != null) {
      await ref.read(peopleRepositoryProvider).renamePerson(p.id, name);
    }
  }

  Future<void> _merge(
    BuildContext context,
    WidgetRef ref,
    PersonSummary p,
  ) async {
    final l10n = AppLocalizations.of(context);
    final choice = await pickPerson(
      context,
      excludePersonId: p.id,
      allowNew: false,
      title: l10n.mergeWith,
      kind: p.kind,
    );
    if (choice?.personId != null && context.mounted) {
      context.push('${Routes.merge}/${p.id}/${choice!.personId}');
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PersonSummary p,
  ) async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirm(
      context,
      title: l10n.deletePersonTitle(personName(l10n, p)),
      body: l10n.deletePersonBody(p.faceCount),
      confirmLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!ok) return;
    await ref.read(peopleRepositoryProvider).deletePerson(p.id);
    if (context.mounted) {
      leave(context, p.kind == 'character' ? Routes.characters : Routes.people);
    }
  }
}

class _BodiesTab extends ConsumerWidget {
  const _BodiesTab({required this.personId, required this.kind});

  final int personId;
  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final bodies = ref.watch(personBodiesProvider(personId));
    return bodies.when(
      loading: () => const LoadingBox(),
      error: (_, _) => RetryState(
        onRetry: () => ref.invalidate(personBodiesProvider(personId)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.accessibility_new,
            title: l10n.noBodiesTitle,
            body: l10n.noBodiesBody,
          );
        }
        return GridView.builder(
          key: const Key('body-grid'),
          padding: const EdgeInsets.all(4),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 130,
            childAspectRatio: 0.62,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final b = items[i];
            return GestureDetector(
              key: Key('body-${b.id}'),
              onTap: () {
                if (b.mediaId != null) {
                  context.push(
                    '${Routes.media}/${b.mediaId}?personId=$personId',
                  );
                }
              },
              onLongPress: () => _bodyMenu(context, ref, b),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CropImage(
                      path: b.cropPath,
                      cacheWidth: 300,
                      placeholderIcon: Icons.accessibility_new,
                    ),
                    if (b.linkMethod != null)
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Text(
                              b.linkMethod == 'manual'
                                  ? l10n.linkManual
                                  : l10n.linkOutfit,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _bodyMenu(
    BuildContext context,
    WidgetRef ref,
    BodyItem b,
  ) async {
    final l10n = AppLocalizations.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('body-not-this-person'),
              leading: const Icon(Icons.person_off_outlined),
              title: Text(l10n.notThisPerson),
              onTap: () => Navigator.pop(context, 'reject'),
            ),
            ListTile(
              key: const Key('body-kind'),
              leading: const Icon(Icons.swap_horiz),
              title: Text(
                kind == 'person' ? l10n.boxIsCharacter : l10n.boxIsPerson,
              ),
              onTap: () => Navigator.pop(context, 'kind'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'reject') {
      await ref
          .read(peopleRepositoryProvider)
          .rejectBody(b.id, personId: personId);
    } else if (action == 'kind') {
      await moveToOtherKind(context, ref, fromKind: kind, bodyIds: [b.id]);
    }
  }
}

class _SuggestionsTab extends ConsumerStatefulWidget {
  const _SuggestionsTab({required this.person});

  final PersonSummary person;

  @override
  ConsumerState<_SuggestionsTab> createState() => _SuggestionsTabState();
}

class _SuggestionsTabState extends ConsumerState<_SuggestionsTab> {
  final _deselected =
      <int>{}; // faces the user unticked (everything starts ticked)

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = widget.person;
    final matches =
        ref.watch(personMatchesProvider(p.id)).value ??
        const <ReviewMatchFace>[];
    final duplicates = [
      for (final d
          in ref.watch(reviewDuplicatesProvider(p.kind)).value ??
              const <ReviewDuplicateItem>[])
        if (d.a.id == p.id || d.b.id == p.id) d,
    ];
    final links = [
      for (final l
          in ref.watch(reviewBodyLinksProvider(p.kind)).value ??
              const <ReviewBodyLinkItem>[])
        if (l.person.id == p.id) l,
    ];
    if (matches.isEmpty && duplicates.isEmpty && links.isEmpty) {
      return EmptyState(
        icon: Icons.task_alt,
        title: l10n.noSuggestionsTitle,
        body: l10n.noSuggestionsBody,
      );
    }
    final chosen = [
      for (final m in matches)
        if (!_deselected.contains(m.faceId)) m.faceId,
    ];
    final repo = reviewRepositoryFor(ref, p.kind);

    return ListView(
      key: const Key('suggestions-list'),
      padding: const EdgeInsets.all(12),
      children: [
        if (matches.isNotEmpty) ...[
          Text(
            l10n.suggestedFacesTitle(personName(l10n, p), matches.length),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in matches)
                GestureDetector(
                  key: Key('suggested-${m.faceId}'),
                  onTap: () => setState(() {
                    if (!_deselected.remove(m.faceId)) {
                      _deselected.add(m.faceId);
                    }
                  }),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CropImage(path: m.cropPath),
                          if (_deselected.contains(m.faceId))
                            const ColoredBox(color: Colors.black54),
                          Positioned(
                            right: 3,
                            top: 3,
                            child: Icon(
                              _deselected.contains(m.faceId)
                                  ? Icons.radio_button_unchecked
                                  : Icons.check_circle,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                key: const Key('accept-suggested'),
                onPressed: chosen.isEmpty
                    ? null
                    : () => repo.acceptMatches(chosen, p.id),
                child: Text(l10n.addFacesTo(chosen.length)),
              ),
              OutlinedButton(
                key: const Key('reject-suggested'),
                onPressed: chosen.isEmpty
                    ? null
                    : () => repo.rejectMatches(chosen, p.id),
                child: Text(l10n.notThem(chosen.length)),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (duplicates.isNotEmpty) ...[
          Text(
            l10n.possibleSamePerson,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          for (final d in duplicates)
            ListTile(
              key: Key('duplicate-${d.a.id}-${d.b.id}'),
              contentPadding: EdgeInsets.zero,
              leading: PersonAvatar(
                cropPath: (d.a.id == p.id ? d.b : d.a).avatarCropPath,
                radius: 22,
              ),
              title: Text(personName(l10n, d.a.id == p.id ? d.b : d.a)),
              subtitle: Text(
                scoreLabel(
                  l10n,
                  advanced: ref.watch(reviewAdvancedProvider),
                  kind: ReviewQuestionKind.duplicate,
                  score: d.score,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(
                '${Routes.merge}/${p.id}/${d.a.id == p.id ? d.b.id : d.a.id}',
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (links.isNotEmpty) ...[
          Text(
            l10n.outfitMatchesTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          for (final l in links) _BodyLinkTile(link: l),
        ],
      ],
    );
  }
}

class _BodyLinkTile extends ConsumerWidget {
  const _BodyLinkTile({required this.link});

  final ReviewBodyLinkItem link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final repo = reviewRepositoryFor(ref, link.person.kind);
    return ListTile(
      key: Key('body-link-${link.bodyId}'),
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 44,
        height: 64,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CropImage(
            path: link.cropPath,
            placeholderIcon: Icons.accessibility_new,
          ),
        ),
      ),
      title: Text(l10n.bodyLinkTitle(personName(l10n, link.person))),
      subtitle: Text(
        scoreLabel(
          l10n,
          advanced: ref.watch(reviewAdvancedProvider),
          kind: ReviewQuestionKind.outfit,
          score: link.confidence,
          method: link.method,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l10n.accept,
            icon: const Icon(Icons.check),
            onPressed: () => repo.acceptBodyLink(link.bodyId, link.person.id),
          ),
          IconButton(
            tooltip: l10n.reject,
            icon: const Icon(Icons.close),
            onPressed: () => repo.rejectBodyLink(link.bodyId, link.person.id),
          ),
        ],
      ),
    );
  }
}

class _PersonMedia extends StatefulWidget {
  const _PersonMedia({required this.personId});
  final int personId;
  @override
  State<_PersonMedia> createState() => _PersonMediaState();
}

class _PersonMediaState extends State<_PersonMedia> {
  String? _kind;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButton<String>(
            value: _kind ?? 'all',
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All media')),
              DropdownMenuItem(value: 'photo', child: Text('Photos')),
              DropdownMenuItem(value: 'video', child: Text('Videos')),
            ],
            onChanged: (value) =>
                setState(() => _kind = value == 'all' ? null : value),
          ),
        ),
      ),
      Expanded(
        child: MediaGrid(
          columns: 4,
          filter: MediaFilter(personId: widget.personId, kind: _kind),
          empty: EmptyState(
            icon: Icons.photo_outlined,
            title: AppLocalizations.of(context).noPhotosOfPerson,
          ),
        ),
      ),
    ],
  );
}

class _PersonModels extends ConsumerWidget {
  const _PersonModels({required this.personId, required this.avatarPath});
  final int personId;
  final String? avatarPath;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final models = ref.watch(lorasProvider);
    final datasets = ref.watch(datasetsProvider);
    final jobs = ref.watch(jobsProvider);
    final ownedModels = (models.value ?? const [])
        .where((m) => m.personId == personId)
        .toList();
    final ownedJobs = (jobs.value ?? const [])
        .where(
          (j) =>
              j.personId == personId &&
              j.type == 'train_lora' &&
              j.status != 'completed',
        )
        .toList();
    final ownedDatasets = (datasets.value ?? const [])
        .where((d) => d.personId == personId)
        .toList();
    final ownedResults = (ref.watch(resultsProvider).value ?? const [])
        .where((r) => r.personId == personId)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Trained models', style: Theme.of(context).textTheme.titleMedium),
        if (models.isLoading) const LoadingBox(),
        if (models.hasError)
          RetryState(onRetry: () => ref.invalidate(lorasProvider)),
        if (models.hasValue && ownedModels.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No trained models yet. Prepare training to create one.',
            ),
          ),
        for (final model in ownedModels)
          FutureBuilder<bool>(
            future: ref.read(fileStoreProvider).resolve(model.path).exists(),
            builder: (context, snapshot) {
              final ready = snapshot.data == true;
              return ListTile(
                leading: PersonAvatar(
                  cropPath: avatarPath,
                  radius: 20,
                  expandable: false,
                ),
                title: Text(model.triggerWord),
                subtitle: Text(
                  snapshot.connectionState == ConnectionState.done
                      ? (ready ? 'Ready on this phone' : 'File unavailable')
                      : 'Checking file',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('${Routes.lora}/model/${model.id}'),
              );
            },
          ),
        if (jobs.isLoading || jobs.hasError || ownedJobs.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Training tasks',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (jobs.isLoading) const LoadingBox(),
          if (jobs.hasError)
            RetryState(onRetry: () => ref.invalidate(jobsProvider)),
          for (final job in ownedJobs)
            ListTile(
              title: Text(
                jobStatusLabel(AppLocalizations.of(context), job.status),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('${Routes.jobs}/${job.id}'),
            ),
        ],
        if (datasets.isLoading ||
            datasets.hasError ||
            ownedDatasets.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Datasets', style: Theme.of(context).textTheme.titleMedium),
          if (datasets.isLoading) const LoadingBox(),
          if (datasets.hasError)
            RetryState(onRetry: () => ref.invalidate(datasetsProvider)),
          for (final dataset in ownedDatasets)
            ListTile(
              title: Text(dataset.triggerWord),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('${Routes.datasets}/${dataset.id}'),
            ),
        ],
        if (ownedResults.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Related results',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final result in ownedResults)
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: Text(
                jobTypeLabel(AppLocalizations.of(context), result.type),
              ),
              onTap: () => context.push('${Routes.results}/${result.id}'),
            ),
        ],
        FilledButton.tonalIcon(
          onPressed: () => context.push('${Routes.studioCuration}/$personId'),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Prepare training (Auto-Select ⚡)'),
        ),
      ],
    );
  }
}

class _SavedIdentities extends ConsumerWidget {
  const _SavedIdentities({required this.personId, required this.allowStudio});
  final int personId;
  final bool allowStudio;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sets = ref.watch(identitySetsProvider);
    return sets.when(
      loading: () => const LoadingBox(),
      error: (_, _) =>
          RetryState(onRetry: () => ref.invalidate(identitySetsProvider)),
      data: (items) {
        final owned = items.where((item) => item.personId == personId).toList();
        if (owned.isEmpty) {
          return const Center(child: Text('No saved identities'));
        }
        return ListView(
          children: [
            for (final item in owned)
              ListTile(
                leading: const Icon(Icons.bookmark_outline),
                title: Text(item.name),
                subtitle: const Text('Saved source identity'),
                trailing: IconButton(
                  tooltip: 'Edit identity',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _IdentitySetEditor(item: item),
                    ),
                  ),
                ),
                onTap: !allowStudio
                    ? null
                    : () => context.push(
                        '${Routes.reface}?person=$personId&identity=${item.id}',
                      ),
              ),
          ],
        );
      },
    );
  }
}

class _IdentitySetEditor extends ConsumerStatefulWidget {
  const _IdentitySetEditor({required this.item});
  final IdentitySetRow item;
  @override
  ConsumerState<_IdentitySetEditor> createState() => _IdentitySetEditorState();
}

class _IdentitySetEditorState extends ConsumerState<_IdentitySetEditor> {
  late final TextEditingController _name;
  final _selected = <int>{};
  List<FaceRow> _faces = const [];
  bool _loading = true, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item.name);
    _load();
  }

  Future<void> _load() async {
    try {
      final current = await ref
          .read(identityRepositoryProvider)
          .faces(widget.item.id);
      final candidates = await ref
          .read(studioRepositoryProvider)
          .sourceFaces(widget.item.personId);
      if (!mounted) return;
      setState(() {
        _selected.addAll(current.map((f) => f.id));
        _faces = {
          for (final f in [...candidates, ...current])
            if (f.modelId == widget.item.modelId) f.id: f,
        }.values.toList();
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(identityRepositoryProvider)
          .update(setId: widget.item.id, name: _name.text, faceIds: _selected);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Saved identity'),
      actions: [
        IconButton(
          tooltip: 'Delete identity',
          onPressed: _busy
              ? null
              : () async {
                  final yes = await confirm(
                    context,
                    title: 'Delete saved identity?',
                    body: 'The selected faces remain in the person.',
                    confirmLabel: 'Delete',
                    cancelLabel: 'Cancel',
                    destructive: true,
                  );
                  if (!yes || !context.mounted) return;
                  await ref
                      .read(identityRepositoryProvider)
                      .delete(widget.item.id);
                  if (context.mounted) Navigator.pop(context);
                },
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: _busy || _loading ? null : _save,
          child: const Text('Save identity'),
        ),
      ),
    ),
    body: _loading
        ? const LoadingBox()
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextField(
                controller: _name,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Identity name'),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Text('Selected faces: ${_selected.length}'),
              for (final face in _faces)
                CheckboxListTile(
                  value: _selected.contains(face.id),
                  onChanged: _busy
                      ? null
                      : (on) => setState(() {
                          if (on == true) {
                            _selected.add(face.id);
                          } else {
                            _selected.remove(face.id);
                          }
                        }),
                  secondary: SizedBox(
                    width: 48,
                    height: 48,
                    child: CropImage(path: face.cropPath),
                  ),
                  title: Text('Face ${face.id}'),
                  subtitle: Text(
                    'Quality ${(face.qualityScore * 100).round()}%',
                  ),
                ),
            ],
          ),
  );
}
