import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/repositories/media_queries.dart';
import '../../data/repositories/people_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../shared/crop_image.dart';
import '../shared/empty_state.dart';
import '../shared/person_picker.dart';
import 'media_grid.dart';

/// S04 - the photo library: a grid of every photo the app knows with filters (person, scanned or
/// not, has faces). Tap a photo for the viewer with its face boxes.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  var _filter = const MediaFilter();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final people = {
      for (final p
          in ref.watch(peopleProvider).value ?? const <PersonSummary>[])
        p.id: p,
    };
    final personId = _filter.personId;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navLibrary),
        actions: [
          IconButton(
            key: const Key('library-scan'),
            tooltip: l10n.scanLibrary,
            icon: const Icon(Icons.document_scanner_outlined),
            onPressed: () => context.push(Routes.sources),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'all',
                    label: Text(l10n.filterAll),
                    icon: const Icon(Icons.perm_media_outlined),
                  ),
                  ButtonSegment(
                    value: 'photo',
                    label: Text(l10n.statPhotos),
                    icon: const Icon(Icons.photo_outlined),
                  ),
                  ButtonSegment(
                    value: 'video',
                    label: Text(l10n.statVideos),
                    icon: const Icon(Icons.videocam_outlined),
                  ),
                ],
                selected: {_filter.kind ?? 'all'},
                onSelectionChanged: (value) => setState(() {
                  _filter = value.single == 'all'
                      ? _filter.copyWith(clearKind: true)
                      : _filter.copyWith(kind: value.single);
                }),
              ),
            ),
          ),
          SingleChildScrollView(
            key: const Key('library-filters'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final (scan, label) in [
                  (ScanFilter.all, l10n.filterAll),
                  (ScanFilter.scanned, l10n.filterScanned),
                  (ScanFilter.unscanned, l10n.filterNotScanned),
                  (ScanFilter.failed, l10n.filterFailed),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: Key('filter-${scan.name}'),
                      label: Text(label),
                      selected: _filter.scan == scan,
                      onSelected: (_) => setState(
                        () => _filter = _filter.copyWith(scan: scan),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    key: const Key('filter-has-faces'),
                    label: Text(l10n.filterHasFaces),
                    selected: _filter.hasFaces == true,
                    onSelected: (on) => setState(
                      () => _filter = on
                          ? _filter.copyWith(hasFaces: true)
                          : _filter.copyWith(clearHasFaces: true),
                    ),
                  ),
                ),
                if (personId != null)
                  InputChip(
                    key: const Key('filter-person'),
                    deleteIcon: const Icon(Icons.cancel),
                    avatar: PersonAvatar(
                      cropPath: people[personId]?.avatarCropPath,
                      radius: 12,
                    ),
                    label: Text(personNameOf(l10n, personId, people)),
                    onDeleted: () => setState(
                      () => _filter = _filter.copyWith(clearPerson: true),
                    ),
                  )
                else
                  ActionChip(
                    key: const Key('filter-pick-person'),
                    avatar: const Icon(Icons.person_search, size: 18),
                    label: Text(l10n.filterPerson),
                    onPressed: () async {
                      final choice = await pickPerson(
                        context,
                        allowNew: false,
                        title: l10n.filterPerson,
                      );
                      if (choice?.personId != null && mounted) {
                        setState(
                          () => _filter = _filter.copyWith(
                            personId: choice!.personId,
                          ),
                        );
                      }
                    },
                  ),
              ],
            ),
          ),
          if (!_filter.isDefault)
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
            child: MediaGrid(
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
          ),
        ],
      ),
    );
  }
}
