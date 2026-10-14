import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/repositories/media_queries.dart';
import '../../data/repositories/people_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../library/media_grid.dart';
import '../shared/crop_image.dart';
import '../shared/empty_state.dart';
import '../shared/person_picker.dart';
import 'face_grid.dart';

final personProvider = StreamProvider.autoDispose.family<PersonSummary?, int>(
  (ref, id) => ref.watch(peopleRepositoryProvider).watchPerson(id),
);

final personBodiesProvider = StreamProvider.autoDispose
    .family<List<BodyItem>, int>(
      (ref, id) => ref.watch(peopleRepositoryProvider).watchBodies(id),
    );

final personMatchesProvider = StreamProvider.autoDispose
    .family<List<ReviewMatchFace>, int>(
      (ref, id) => ref.watch(reviewRepositoryProvider).watchMatchesFor(id),
    );

final reviewDuplicatesProvider =
    StreamProvider.autoDispose<List<ReviewDuplicateItem>>(
      (ref) => ref.watch(reviewRepositoryProvider).watchDuplicates(),
    );

final reviewBodyLinksProvider =
    StreamProvider.autoDispose<List<ReviewBodyLinkItem>>(
      (ref) => ref.watch(reviewRepositoryProvider).watchBodyLinks(),
    );

/// S08 - one person: faces, photos, bodies and what the PC suggests about them.
class PersonDetailScreen extends ConsumerWidget {
  const PersonDetailScreen({super.key, required this.personId});

  final int personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final person = ref.watch(personProvider(personId));
    return person.when(
      loading: () => Scaffold(appBar: AppBar(), body: const LoadingBox()),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('$e')),
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
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: InkWell(
                key: const Key('person-title'),
                onTap: () => _rename(context, ref, p),
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
                PopupMenuButton<String>(
                  key: const Key('person-menu'),
                  onSelected: (v) {
                    switch (v) {
                      case 'studio':
                        context.push('${Routes.reface}?person=$personId');
                      case 'rename':
                        _rename(context, ref, p);
                      case 'merge':
                        _merge(context, ref, p);
                      case 'delete':
                        _delete(context, ref, p);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'studio',
                      child: Text(l10n.useInStudio),
                    ),
                    PopupMenuItem(value: 'rename', child: Text(l10n.rename)),
                    PopupMenuItem(value: 'merge', child: Text(l10n.mergeWith)),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(l10n.deletePerson),
                    ),
                  ],
                ),
              ],
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(
                    key: const Key('tab-faces'),
                    text: l10n.tabFaces(p.faceCount),
                  ),
                  Tab(key: const Key('tab-photos'), text: l10n.tabMedia),
                  Tab(key: const Key('tab-bodies'), text: l10n.tabBodies),
                  Tab(
                    key: const Key('tab-suggestions'),
                    text: l10n.tabSuggestions,
                  ),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                FaceGrid(personId: personId),
                MediaGrid(
                  filter: MediaFilter(personId: personId),
                  empty: EmptyState(
                    icon: Icons.photo_outlined,
                    title: l10n.noPhotosOfPerson,
                  ),
                ),
                _BodiesTab(personId: personId),
                _SuggestionsTab(person: p),
              ],
            ),
          ),
        );
      },
    );
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
    if (context.mounted) leave(context, Routes.people);
  }
}

class _BodiesTab extends ConsumerWidget {
  const _BodiesTab({required this.personId});

  final int personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final bodies = ref.watch(personBodiesProvider(personId));
    return bodies.when(
      loading: () => const LoadingBox(),
      error: (e, _) => Center(child: Text('$e')),
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
                  context.push('${Routes.media}/${b.mediaId}');
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
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: ListTile(
          key: const Key('body-not-this-person'),
          leading: const Icon(Icons.person_off_outlined),
          title: Text(l10n.notThisPerson),
          onTap: () => Navigator.pop(context, true),
        ),
      ),
    );
    if (ok == true) {
      await ref
          .read(peopleRepositoryProvider)
          .rejectBody(b.id, personId: personId);
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
          in ref.watch(reviewDuplicatesProvider).value ??
              const <ReviewDuplicateItem>[])
        if (d.a.id == p.id || d.b.id == p.id) d,
    ];
    final links = [
      for (final l
          in ref.watch(reviewBodyLinksProvider).value ??
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
    final repo = ref.read(reviewRepositoryProvider);

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
              subtitle: Text(l10n.similarityPercent((d.score * 100).round())),
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
    final repo = ref.read(reviewRepositoryProvider);
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
        l10n.bodyLinkDetail(
          link.method == 'appearance' ? l10n.linkOutfit : l10n.linkWeakFace,
          (link.confidence * 100).round(),
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
