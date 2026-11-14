import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/repositories/media_queries.dart';
import '../../data/repositories/people_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../ui/collection/filter_bar.dart';
import '../../ui/collection/segmented_bar.dart';
import '../../ui/scaffolds/tab_root_scaffold.dart';
import '../shared/crop_image.dart';
import '../shared/empty_state.dart';
import '../shared/person_picker.dart';
import 'media_grid.dart';
import 'native_gallery.dart';
import 'scan_invite_strip.dart';

/// L1 Gallery screen: Photo and Album browsing using TabRootScaffold,
/// SegmentedBar, FilterSheet/FilterBar, and ScanInviteStrip.
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: scheme.surfaceContainerLow,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, updateSheet) {
          void update(MediaFilter value) {
            setState(() => _filter = value);
            updateSheet(() {});
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tune, color: scheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Filter Media',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Media Kind
                  Text(
                    'Media Type',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 16),

                  // Scan Status
                  Text(
                    'Scan Status',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
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
                  const SizedBox(height: 16),

                  // Content & People
                  Text(
                    'Content & People',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        key: const Key('filter-has-faces'),
                        avatar: const Icon(Icons.face_outlined, size: 16),
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
                          avatar: const Icon(Icons.person_search, size: 16),
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
                          avatar: const Icon(Icons.person, size: 16),
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
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => update(const MediaFilter()),
                          child: Text(l.clearFilters),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('Show media'),
                        ),
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
    final density = ref.watch(galleryDensityProvider);

    return TabRootScaffold(
      title: const Text('Gallery'),
      primaryAction: IconButton(
        key: const Key('library-filters-toggle'),
        tooltip: 'Filters',
        icon: Badge(
          isLabelVisible: !_filter.isDefault,
          smallSize: 8,
          child: const Icon(Icons.tune),
        ),
        onPressed: _openFilters,
      ),
      onSettingsTap: () => context.push(Routes.settings),
      body: Column(
        children: [
          SegmentedBar<int>(
            key: const Key('library-tabs'),
            segments: const [
              SegmentItem(
                value: 0,
                label: 'Photos',
                icon: Icons.photo_outlined,
              ),
              SegmentItem(
                value: 1,
                label: 'Folders',
                icon: Icons.folder_outlined,
              ),
            ],
            selected: _tab,
            onSelected: (i) => setState(() => _tab = i),
          ),
          if (_tab == 0) const ScanInviteStrip(),
          if (_tab == 0 && !_filter.isDefault)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: FilterBar(
                      filters: [
                        if (_filter.kind != null)
                          FilterSpec(
                            key: 'kind',
                            label: _filter.kind!,
                            options: const [],
                            currentValue: _filter.kind,
                          ),
                        if (_filter.scan != ScanFilter.all)
                          FilterSpec(
                            key: 'scan',
                            label: _filter.scan.name,
                            options: const [],
                            currentValue: _filter.scan,
                          ),
                        if (_filter.hasFaces == true)
                          const FilterSpec(
                            key: 'faces',
                            label: 'Faces',
                            options: [],
                            currentValue: true,
                          ),
                        if (_filter.personId != null)
                          FilterSpec(
                            key: 'person',
                            label: 'Person',
                            options: const [],
                            currentValue: _filter.personId,
                          ),
                      ],
                      onFilterChanged: (_, _) {},
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('library-clear-filters'),
                    onPressed: () =>
                        setState(() => _filter = const MediaFilter()),
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                    label: Text(l10n.clearFilters),
                  ),
                ],
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
                      columns: density,
                      filter: _filter,
                      empty: _filter.isDefault
                          ? EmptyState(
                              icon: Icons.photo_library_outlined,
                              title: l10n.libraryEmptyTitle,
                              body: l10n.libraryEmptyBody,
                              actionLabel: l10n.chooseAlbums,
                              onAction: () =>
                                  context.push(Routes.settingsLibrary),
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
