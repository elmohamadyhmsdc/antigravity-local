import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/repositories/media_queries.dart';
import '../../data/repositories/people_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../studio_providers.dart';
import '../../domain/scan/scan_state.dart';
import '../shared/empty_state.dart';
import '../shared/crop_image.dart';
import '../shared/person_picker.dart';
import 'media_grid.dart';
import 'native_gallery.dart';

/// S04 - the photo library: a grid of every photo the app knows with filters (person, scanned or
/// not, has faces). Tap a photo for the viewer with its face boxes.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  var _filter = const MediaFilter();
  var _tab = 0;

  Future<void> _openFilters() async {
    final l = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, updateSheet) {
          void update(MediaFilter value) {
            setState(() => _filter = value);
            updateSheet(() {});
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Filter media',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (kind, label) in [
                        ('all', l.filterAll),
                        ('photo', l.statPhotos),
                        ('video', l.statVideos),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: (_filter.kind ?? 'all') == kind,
                          onSelected: (_) => update(
                            kind == 'all'
                                ? _filter.copyWith(clearKind: true)
                                : _filter.copyWith(kind: kind),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (scan, label) in [
                        (ScanFilter.all, l.filterAll),
                        (ScanFilter.scanned, l.filterScanned),
                        (ScanFilter.unscanned, l.filterNotScanned),
                        (ScanFilter.failed, l.filterFailed),
                      ])
                        ChoiceChip(
                          key: Key('filter-${scan.name}'),
                          label: Text(label),
                          selected: _filter.scan == scan,
                          onSelected: (_) =>
                              update(_filter.copyWith(scan: scan)),
                        ),
                    ],
                  ),
                  FilterChip(
                    key: const Key('filter-has-faces'),
                    label: Text(l.filterHasFaces),
                    selected: _filter.hasFaces == true,
                    onSelected: (on) => update(
                      on
                          ? _filter.copyWith(hasFaces: true)
                          : _filter.copyWith(clearHasFaces: true),
                    ),
                  ),
                  if (_filter.personId == null)
                    ActionChip(
                      key: const Key('filter-pick-person'),
                      avatar: const Icon(Icons.person_search),
                      label: Text(l.filterPerson),
                      onPressed: () async {
                        final choice = await pickPerson(
                          sheetContext,
                          allowNew: false,
                          title: l.filterPerson,
                        );
                        if (choice?.personId != null && mounted) {
                          update(_filter.copyWith(personId: choice!.personId));
                        }
                      },
                    )
                  else
                    InputChip(
                      key: const Key('filter-person'),
                      label: Text(
                        personNameOf(l, _filter.personId!, {
                          for (final p
                              in ref.read(peopleProvider).value ??
                                  const <PersonSummary>[])
                            p.id: p,
                        }),
                      ),
                      onDeleted: () =>
                          update(_filter.copyWith(clearPerson: true)),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => update(const MediaFilter()),
                        child: Text(l.clearFilters),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('Show media'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final activeScan = ref.watch(scanProgressProvider).value?.isActive ?? false;
    final pending = (ref.watch(jobsProvider).value ?? const [])
        .where(
          (job) => !const ['completed', 'failed', 'lost'].contains(job.status),
        )
        .length + (activeScan ? 1 : 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallery'),
        actions: [
          IconButton(
            key: const Key('library-filters-toggle'),
            tooltip: 'Filters',
            icon: const Icon(Icons.tune),
            onPressed: _openFilters,
          ),
          IconButton(
            tooltip: 'Activity',
            icon: Badge(
              isLabelVisible: pending > 0,
              label: Text(pending > 99 ? '99+' : pending.toString()),
              child: const Icon(Icons.pending_actions_outlined),
            ),
            onPressed: () => context.push(Routes.jobs),
          ),
          PopupMenuButton<String>(
            key: const Key('gallery-more'),
            onSelected: (value) {
              if (value == 'scan') context.push(Routes.sources);
              if (value == 'settings') context.push(Routes.settings);
              if (value == 'connection') context.push(Routes.connection);
              if (value == 'home') context.push(Routes.home);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'scan', child: Text(l10n.scanLibrary)),
              const PopupMenuItem(
                value: 'connection',
                child: Text('Connection'),
              ),
              PopupMenuItem(value: 'settings', child: Text(l10n.settings)),
              const PopupMenuItem(value: 'home', child: Text('Overview')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 2,
                        color: _tab == 0
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: TextButton(
                    onPressed: () => setState(() => _tab = 0),
                    child: Text(
                      'Photos',
                      style: TextStyle(
                        fontWeight: _tab == 0
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 2,
                        color: _tab == 1
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: TextButton(
                    onPressed: () => setState(() => _tab = 1),
                    child: Text(
                      'Folders',
                      style: TextStyle(
                        fontWeight: _tab == 1
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if ((ref.watch(scanProgressProvider).value?.phase ??
                  ScanPhase.idle) !=
              ScanPhase.idle)
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Library analysis'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.runningScan),
            ),
          if (_tab == 0 && !_filter.isDefault)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Filters include photos you have opened or analyzed.',
              ),
            ),
          if (_tab == 0 && !_filter.isDefault)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: const Key('library-clear-filters'),
                onPressed: () => setState(() => _filter = const MediaFilter()),
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: Text(l10n.clearFilters),
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                IndexedStack(
                  index: _filter.isDefault ? 0 : 1,
                  children: [
                    const NativeGallery(),
                    MediaGrid(
                      columns: 4,
                      filter: _filter,
                      empty: _filter.isDefault
                          ? EmptyState(
                              icon: Icons.photo_library_outlined,
                              title: l10n.libraryEmptyTitle,
                              body: l10n.libraryEmptyBody,
                              actionLabel: l10n.chooseAlbums,
                              onAction: () => context.push(Routes.sources),
                            )
                          : EmptyState(
                              icon: Icons.filter_alt_off_outlined,
                              title: l10n.noPhotosMatch,
                              actionLabel: l10n.clearFilters,
                              onAction: () =>
                                  setState(() => _filter = const MediaFilter()),
                            ),
                    ),
                  ],
                ),
                if (_tab == 1)
                  const GalleryFolders()
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
