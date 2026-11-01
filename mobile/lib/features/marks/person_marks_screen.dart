import '../shared/image_preview.dart';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/db/app_database.dart';
import '../../domain/marks/body_marks.dart';
import '../../domain/marks/mark_geometry.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../shared/crop_image.dart';
import '../shared/empty_state.dart';
import 'mark_tattoo.dart';

/// Roadmap 7.4: one person's tattoo marks, and the search for the same tattoo on faceless bodies of other
/// photos. A match is only ever a suggestion the user confirms ("It is them") or refuses; the strong and
/// possible matches are also queued in Quick Review as "Matching tattoo".
class PersonMarksScreen extends ConsumerStatefulWidget {
  const PersonMarksScreen({super.key, required this.personId});

  final int personId;

  @override
  ConsumerState<PersonMarksScreen> createState() => _PersonMarksScreenState();
}

class _PersonMarksScreenState extends ConsumerState<PersonMarksScreen> {
  List<BodyMarkRow> _marks = const [];
  bool _loaded = false;
  int? _searching;
  int? _resultsFor;
  List<MarkHit> _hits = const [];
  Map<int, String?> _crops = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final marks = await ref
        .read(bodyMarkStoreProvider)
        .ofPerson(widget.personId);
    if (mounted) {
      setState(() {
        _marks = marks;
        _loaded = true;
      });
    }
  }

  Future<void> _search(BodyMarkRow mark) async {
    final l = AppLocalizations.of(context);
    if (ref.read(mobileApiProvider) == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.marksNoServer)));
      return;
    }
    setState(() {
      _searching = mark.id;
      _resultsFor = null;
    });
    final matcher = ref.read(markMatcherProvider);
    List<MarkHit>? hits;
    try {
      hits = await matcher.search(mark, ref.read(patchCutterProvider));
    } catch (_) {
      hits = null;
    }
    if (hits != null && hits.isNotEmpty) {
      await matcher.publishSuggestions(mark, hits);
    }
    final db = ref.read(databaseProvider);
    final ids = [for (final h in hits ?? const <MarkHit>[]) h.bodyId];
    final crops = <int, String?>{};
    if (ids.isNotEmpty) {
      final rows = await db
          .customSelect(
            'SELECT id, crop_path FROM bodies WHERE id IN (${ids.map((_) => '?').join(',')})',
            variables: [for (final id in ids) Variable.withInt(id)],
            readsFrom: {db.bodies},
          )
          .get();
      for (final r in rows) {
        crops[r.read<int>('id')] = r.readNullable<String>('crop_path');
      }
    }
    if (!mounted) return;
    setState(() {
      _searching = null;
      _resultsFor = mark.id;
      _hits = hits ?? const [];
      _crops = crops;
    });
    if (hits == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.marksNoServer)));
    }
  }

  Future<void> _decide(MarkHit hit, bool yes) async {
    final repo = ref.read(peopleRepositoryProvider);
    if (yes) {
      await repo.linkBody(hit.bodyId, widget.personId);
    } else {
      await repo.rejectBody(hit.bodyId, personId: widget.personId);
    }
    if (mounted) {
      setState(
        () => _hits = [
          for (final h in _hits)
            if (h.bodyId != hit.bodyId) h,
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.marksTitle),
        leading: BackButton(onPressed: () => leave(context, Routes.people)),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _marks.isEmpty
          ? EmptyState(icon: Icons.draw_outlined, title: l.marksNone)
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [for (final mark in _marks) _card(l, mark)],
            ),
    );
  }

  Widget _card(AppLocalizations l, BodyMarkRow mark) {
    final files = ref.read(fileStoreProvider);
    File? patch;
    try {
      patch = files.resolve(mark.patchPath);
    } on FormatException {
      patch = null;
    }
    final showing = _resultsFor == mark.id;
    return Card(
      key: Key('mark-${mark.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: patch != null && patch.existsSync()
                      ? PreviewImage.memory(
                          patch.readAsBytesSync(),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.broken_image_outlined),
                        )
                      : const Icon(Icons.broken_image_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mark.label ?? segmentLabel(l, mark.segment),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(segmentLabel(l, mark.segment)),
                    ],
                  ),
                ),
                IconButton(
                  key: Key('mark-delete-${mark.id}'),
                  tooltip: l.marksDelete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await ref.read(bodyMarkStoreProvider).delete(mark.id);
                    await _load();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              key: Key('mark-search-${mark.id}'),
              icon: const Icon(Icons.image_search_outlined),
              label: Text(
                _searching == mark.id ? l.marksSearching : l.marksSearch,
              ),
              onPressed: _searching != null ? null : () => _search(mark),
            ),
            if (showing && _hits.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(l.marksNoHits),
              ),
            if (showing)
              for (final hit in _hits)
                ListTile(
                  key: Key('hit-${hit.bodyId}'),
                  contentPadding: EdgeInsets.zero,
                  leading: SizedBox(
                    width: 56,
                    child: InkWell(
                      onTap: hit.mediaId == null
                          ? null
                          : () =>
                                context.push('${Routes.media}/${hit.mediaId}'),
                      child: CropImage(
                        path: _crops[hit.bodyId],
                        placeholderIcon: Icons.accessibility_new,
                      ),
                    ),
                  ),
                  title: Text(
                    hit.evidence == MarkEvidence.strong
                        ? l.marksStrong
                        : l.marksWeak,
                  ),
                  subtitle: Text(
                    '${hit.inliers} / ${(hit.inlierRatio * 100).round()}%',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: Key('hit-yes-${hit.bodyId}'),
                        tooltip: l.marksYes,
                        icon: const Icon(Icons.check_circle_outline),
                        onPressed: () => _decide(hit, true),
                      ),
                      IconButton(
                        key: Key('hit-no-${hit.bodyId}'),
                        tooltip: l.marksNo,
                        icon: const Icon(Icons.cancel_outlined),
                        onPressed: () => _decide(hit, false),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
