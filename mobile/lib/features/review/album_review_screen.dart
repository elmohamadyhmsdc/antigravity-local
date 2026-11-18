import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/people_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/review_visual_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../people/person_detail_screen.dart';
import '../shared/crop_image.dart';
import '../shared/empty_state.dart';
import '../shared/screen_layout.dart';
import 'highlighted_photo.dart';
import 'review_media_viewer.dart';

/// How many suggestions wait inside one person's album (faces by likeness, bodies by outfit).
int albumReviewCount(WidgetRef ref, int personId, [String kind = 'person']) {
  final faces = ref.watch(personMatchesProvider(personId)).value?.length ?? 0;
  final bodies =
      (ref.watch(personBodyLinksProvider(personId)).value ??
              const <ReviewBodyLinkItem>[])
          .where((l) => l.person.id == personId)
          .length;
  return faces + bodies;
}

Future<void> openAlbumReview(BuildContext context, PersonSummary person) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => AlbumReviewScreen(person: person)),
    );

/// Review suggested appearances against the person's cover.
class AlbumReviewScreen extends ConsumerStatefulWidget {
  const AlbumReviewScreen({super.key, required this.person});

  final PersonSummary person;

  @override
  ConsumerState<AlbumReviewScreen> createState() => _AlbumReviewScreenState();
}

class _AlbumReviewScreenState extends ConsumerState<AlbumReviewScreen> {
  final _selected = <(String, int)>{};
  var _saving = false;

  Future<void> _save({required bool reject}) async {
    if (_saving || _selected.isEmpty) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final review = reviewRepositoryFor(ref, widget.person.kind);
    final faces = [
      for (final (kind, id) in _selected)
        if (kind == 'f') id,
    ];
    final bodies = [
      for (final (kind, id) in _selected)
        if (kind == 'b') id,
    ];
    setState(() => _saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final result = await review.answerAlbum(
        personId: widget.person.id,
        faceIds: faces,
        excludedFaces: reject ? faces.toSet() : const {},
        bodyIds: bodies,
        excludedBodies: reject ? bodies.toSet() : const {},
      );
      if (!mounted) return;
      setState(_selected.clear);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.albumReviewSaved(result.added, result.rejected)),
        ),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l.peopleActionError('$e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final id = widget.person.id;
    final name = personName(l, widget.person);
    final faces = ref.watch(personMatchesProvider(id));
    final links = ref.watch(personBodyLinksProvider(id));
    if (faces.isLoading || links.isLoading) {
      return Scaffold(appBar: AppBar(), body: const LoadingBox());
    }
    if (faces.hasError || links.hasError) {
      return Scaffold(
        appBar: AppBar(title: Text(l.albumReviewTitle(name))),
        body: RetryState(
          onRetry: () {
            ref.invalidate(personMatchesProvider(id));
            ref.invalidate(personBodyLinksProvider(id));
          },
        ),
      );
    }
    final matches = {
      for (final face in faces.value ?? const <ReviewMatchFace>[])
        face.faceId: face,
    };
    final items = [
      for (final id in matches.keys) ReviewTarget('f', id),
      for (final b in links.value ?? const <ReviewBodyLinkItem>[])
        if (b.person.id == id) ReviewTarget('b', b.bodyId),
    ];
    final keys = {for (final t in items) (t.kind, t.id)};
    _selected.retainAll(keys);
    final count = _selected.length;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: Text(l.albumReviewTitle(name))),
        bottomNavigationBar: items.isEmpty
            ? null
            : StickyActionBar(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l.selectedCount(count),
                      key: const Key('album-review-summary'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      key: const Key('album-review-done'),
                      onPressed: _saving || count == 0
                          ? null
                          : () => _save(reject: false),
                      child: Text(_saving ? l.reviewSaving : l.albumReviewAdd),
                    ),
                    TextButton(
                      key: const Key('album-review-reject'),
                      onPressed: _saving || count == 0
                          ? null
                          : () => _save(reject: true),
                      child: Text(l.albumReviewReject),
                    ),
                  ],
                ),
              ),
        body: AbsorbPointer(
          absorbing: _saving,
          child: items.isEmpty
              ? EmptyState(
                  icon: Icons.task_alt,
                  title: l.noSuggestionsTitle,
                  body: l.noSuggestionsBody,
                )
              : CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          children: [
                            if (widget.person.avatarCropPath != null) ...[
                              PersonAvatar(
                                cropPath: widget.person.avatarCropPath,
                                radius: 24,
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(child: Text(l.albumReviewHelp(name))),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      sliver: SliverGrid.builder(
                        key: const Key('album-review-grid'),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 210,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                            ),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final t = items[i];
                          final key = (t.kind, t.id);
                          final face = t.kind == 'f' ? matches[t.id] : null;
                          return _Tile(
                            target: t,
                            portraitPath:
                                face != null &&
                                    face.facePx >= 96 &&
                                    face.quality >= .55
                                ? face.cropPath
                                : null,
                            ticked: _selected.contains(key),
                            onTap: () => setState(() {
                              if (!_selected.remove(key)) _selected.add(key);
                            }),
                            onOpen: () => openReviewMedia(
                              context,
                              items,
                              initialTarget: i,
                              title: name,
                              selectedFaceIds: {
                                for (final (kind, id) in _selected)
                                  if (kind == 'f') id,
                              },
                              onSelectionChanged: (selected) => setState(() {
                                _selected.removeWhere((key) => key.$1 == 'f');
                                _selected.addAll(
                                  selected.map((id) => ('f', id)),
                                );
                              }),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.target,
    required this.portraitPath,
    required this.ticked,
    required this.onTap,
    required this.onOpen,
  });

  final ReviewTarget target;
  final String? portraitPath;
  final bool ticked;
  final VoidCallback onTap, onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final original = HighlightedPhoto(
      kind: target.kind,
      id: target.id,
      maxSide: 512,
      inset: false,
      label: false,
      inlinePreview: true,
    );
    return Semantics(
      checked: ticked,
      child: InkWell(
        key: Key('album-review-${target.kind}-${target.id}'),
        onTap: onTap,
        onLongPress: onOpen,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: portraitPath != null
                    ? CropImage(
                        path: portraitPath,
                        fit: BoxFit.scaleDown,
                        cacheWidth: null,
                        expandable: false,
                        fallback: original,
                      )
                    : original,
              ),
              if (ticked)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.primary, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              PositionedDirectional(
                top: 6,
                end: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: ticked ? scheme.primary : Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      ticked ? Icons.check : Icons.circle_outlined,
                      size: 16,
                      color: ticked ? scheme.onPrimary : Colors.white,
                    ),
                  ),
                ),
              ),
              if (target.kind == 'b')
                PositionedDirectional(
                  start: 4,
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
                        l.linkOutfit,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              PositionedDirectional(
                start: 0,
                top: 0,
                child: IconButton(
                  key: Key('album-review-open-${target.kind}-${target.id}'),
                  tooltip: l.reviewFullPhoto,
                  onPressed: onOpen,
                  icon: const Icon(
                    Icons.zoom_in,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 4)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
