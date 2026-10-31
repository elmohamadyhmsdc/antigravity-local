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
int albumReviewCount(WidgetRef ref, int personId) {
  final faces = ref.watch(personMatchesProvider(personId)).value?.length ?? 0;
  final bodies =
      (ref.watch(reviewBodyLinksProvider).value ?? const <ReviewBodyLinkItem>[])
          .where((l) => l.person.id == personId)
          .length;
  return faces + bodies;
}

Future<void> openAlbumReview(BuildContext context, PersonSummary person) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => AlbumReviewScreen(person: person)),
    );

/// "Review 8 photos" inside a person: every suggested photo, all ticked. Untick the ones that are
/// someone else, then Done adds the ticked ones and records "not them" for the rest.
class AlbumReviewScreen extends ConsumerStatefulWidget {
  const AlbumReviewScreen({super.key, required this.person});

  final PersonSummary person;

  @override
  ConsumerState<AlbumReviewScreen> createState() => _AlbumReviewScreenState();
}

class _AlbumReviewScreenState extends ConsumerState<AlbumReviewScreen> {
  final _off = <String>{}; // 'f:12' / 'b:4' the user unticked
  var _saving = false;

  Future<void> _done(List<ReviewTarget> items) async {
    final l = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final review = ref.read(reviewRepositoryProvider);
    final id = widget.person.id;
    bool on(ReviewTarget t) => !_off.contains('${t.kind}:${t.id}');
    setState(() => _saving = true);
    try {
      final faces = items.where((t) => t.kind == 'f');
      final yes = [
        for (final t in faces)
          if (on(t)) t.id,
      ];
      final no = [
        for (final t in faces)
          if (!on(t)) t.id,
      ];
      if (yes.isNotEmpty) await review.acceptMatches(yes, id);
      if (no.isNotEmpty) await review.rejectMatches(no, id);
      for (final t in items.where((t) => t.kind == 'b')) {
        if (on(t)) {
          await review.acceptBodyLink(t.id, id);
        } else {
          await review.rejectBodyLink(t.id, id);
        }
      }
      final added = items.where(on).length;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.albumReviewSaved(added, items.length - added)),
        ),
      );
      navigator.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        messenger.showSnackBar(
          SnackBar(content: Text(l.peopleActionError('$e'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final id = widget.person.id;
    final name = personName(l, widget.person);
    final faces = ref.watch(personMatchesProvider(id));
    final links = ref.watch(reviewBodyLinksProvider);
    if (faces.isLoading || links.isLoading) {
      return Scaffold(appBar: AppBar(), body: const LoadingBox());
    }
    final items = [
      for (final f in faces.value ?? const <ReviewMatchFace>[])
        ReviewTarget('f', f.faceId),
      for (final b in links.value ?? const <ReviewBodyLinkItem>[])
        if (b.person.id == id) ReviewTarget('b', b.bodyId),
    ];
    final keys = {for (final t in items) '${t.kind}:${t.id}'};
    _off.removeWhere((k) => !keys.contains(k));
    final kept = items.length - _off.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.albumReviewTitle(name)),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              key: const Key('album-review-toggle-all'),
              onPressed: () => setState(() {
                if (_off.isEmpty) {
                  _off.addAll(keys);
                } else {
                  _off.clear();
                }
              }),
              child: Text(_off.isEmpty ? l.albumReviewNone : l.selectAll),
            ),
        ],
      ),
      bottomNavigationBar: items.isEmpty
          ? null
          : StickyActionBar(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.albumReviewSummary(kept, _off.length),
                    key: const Key('album-review-summary'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const Key('album-review-done'),
                    icon: const Icon(Icons.done),
                    onPressed: _saving ? null : () => _done(items),
                    label: Text(l.peopleAction('done')),
                  ),
                ],
              ),
            ),
      body: items.isEmpty
          ? EmptyState(
              icon: Icons.task_alt,
              title: l.noSuggestionsTitle,
              body: l.noSuggestionsBody,
            )
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Text(l.albumReviewHelp(name)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(4),
                  sliver: SliverGrid.builder(
                    key: const Key('album-review-grid'),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 170,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final t = items[i];
                      final key = '${t.kind}:${t.id}';
                      return _Tile(
                        target: t,
                        ticked: !_off.contains(key),
                        onTap: () => setState(() {
                          if (!_off.remove(key)) _off.add(key);
                        }),
                        onOpen: () => openReviewMedia(
                          context,
                          items,
                          initialTarget: i,
                          title: name,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.target,
    required this.ticked,
    required this.onTap,
    required this.onOpen,
  });

  final ReviewTarget target;
  final bool ticked;
  final VoidCallback onTap, onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      checked: ticked,
      child: GestureDetector(
        key: Key('album-review-${target.kind}-${target.id}'),
        onTap: onTap,
        onLongPress: onOpen,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: Colors.black,
                child: HighlightedPhoto(
                  kind: target.kind,
                  id: target.id,
                  maxSide: 512,
                  inset: false,
                  label: false,
                ),
              ),
              if (!ticked) const ColoredBox(color: Colors.black54),
              Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  ticked ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: ticked ? scheme.primary : Colors.white,
                  shadows: const [Shadow(blurRadius: 4)],
                ),
              ),
              if (target.kind == 'b')
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
                        l.linkOutfit,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
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
