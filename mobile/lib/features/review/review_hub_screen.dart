import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../domain/corrections/corrections_queries.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../ui/collection/segmented_bar.dart';
import '../people/unsorted_screen.dart';
import 'quick_review_screen.dart';
import 'review_screen.dart';

/// P4 / P6b — ReviewHubScreen: Unified destination for all review queues
/// (unsorted, suggestions, duplicates, body links, similar, excluded).
final _excludedCountsProvider = FutureProvider.autoDispose<ExcludedCounts>(
  (ref) => ref.watch(correctionsQueriesProvider).excludedCounts(),
);

class ReviewHubScreen extends ConsumerStatefulWidget {
  const ReviewHubScreen({
    super.key,
    this.queue,
    this.kind = 'person',
    this.view,
  });

  final String? queue;
  final String kind;
  final String? view;

  @override
  ConsumerState<ReviewHubScreen> createState() => _ReviewHubScreenState();
}

class _ReviewHubScreenState extends ConsumerState<ReviewHubScreen> {
  late String _kind = widget.kind;
  late final String? _activeQueue = widget.queue;
  bool? _all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // If a specific view or queue is selected, render it directly
    if (widget.view == 'quick') {
      return QuickReviewScreen(kind: _kind);
    }
    if (widget.view == 'all') {
      return ReviewScreen(kind: _kind);
    }
    if (_activeQueue == 'unsorted') {
      return UnsortedScreen(kind: _kind);
    }
    if (_activeQueue == 'suggestions') return ReviewScreen(kind: _kind);
    if (_activeQueue == 'groups') {
      return ReviewScreen(kind: _kind, initialTab: 1);
    }
    if (_activeQueue == 'duplicates') {
      return ReviewScreen(kind: _kind, initialTab: 2);
    }
    if (_activeQueue == 'bodyLinks') {
      return ReviewScreen(kind: _kind, initialTab: 3);
    }
    if (_activeQueue == 'excluded') {
      return _ExcludedQueueScreen(kind: _kind);
    }

    if (widget.view != 'hub') {
      _all ??= switch (ref.watch(settingsProvider)) {
        AsyncData(:final value) => value.reviewAdvanced,
        AsyncError() => false,
        _ => null,
      };
      if (_all == true) return ReviewScreen(kind: _kind);
      if (_all == false) return QuickReviewScreen(kind: _kind);
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Default: The Hub overview with 6 queue cards
    final unsortedCount =
        ref
            .watch(
              _kind == 'character'
                  ? characterUnsortedCountProvider
                  : unsortedCountProvider,
            )
            .value ??
        0;

    final counts = ref.watch(reviewCountsByKindProvider(_kind)).value;
    final suggestionsCount = counts?.matches ?? 0;
    final duplicatesCount = counts?.duplicates ?? 0;
    final bodyLinksCount = counts?.bodyLinks ?? 0;

    final excludedAsync = ref.watch(_excludedCountsProvider);
    final excludedCount = excludedAsync.value?.total ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.reviewTitle),
        actions: [
          IconButton(
            key: const Key('review-quick-mode'),
            tooltip: 'Quick Review',
            icon: const Icon(Icons.bolt_outlined),
            onPressed: () =>
                context.push('${Routes.review}?view=quick&kind=$_kind'),
          ),
          IconButton(
            key: const Key('review-tabs-mode'),
            tooltip: 'Detailed Tabs',
            icon: const Icon(Icons.tab_outlined),
            onPressed: () =>
                context.push('${Routes.review}?view=all&kind=$_kind'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // Kind switcher
          SegmentedBar<String>(
            segments: const [
              SegmentItem(value: 'person', label: 'People'),
              SegmentItem(value: 'character', label: 'Characters'),
            ],
            selected: _kind,
            onSelected: (val) => setState(() => _kind = val),
          ),
          const SizedBox(height: 16),

          // Queue cards grid
          _QueueCard(
            key: const Key('queue-unsorted'),
            icon: Icons.help_outline,
            title: 'Unsorted Faces',
            count: unsortedCount,
            subtitle: 'Faces waiting to be assigned to an identity',
            color: theme.colorScheme.primary,
            onTap: () =>
                context.push('${Routes.review}?queue=unsorted&kind=$_kind'),
          ),
          const SizedBox(height: 12),

          _QueueCard(
            key: const Key('queue-suggestions'),
            icon: Icons.auto_awesome_outlined,
            title: 'Suggestions',
            count: suggestionsCount,
            subtitle: 'Compare suggested face matches',
            color: theme.colorScheme.primary,
            badge: suggestionsCount > 0 ? 'Ready' : null,
            onTap: () =>
                context.push('${Routes.review}?queue=suggestions&kind=$_kind'),
          ),
          const SizedBox(height: 12),

          _QueueCard(
            key: const Key('queue-groups'),
            icon: Icons.groups_outlined,
            title: 'New people',
            count: counts?.groups ?? 0,
            subtitle: 'Review groups of unassigned faces',
            color: theme.colorScheme.primary,
            onTap: () =>
                context.push('${Routes.review}?queue=groups&kind=$_kind'),
          ),
          const SizedBox(height: 12),
          _QueueCard(
            key: const Key('queue-duplicates'),
            icon: Icons.people_outline,
            title: 'Possible Duplicates',
            count: duplicatesCount,
            subtitle: 'Identities that may be the same person',
            color: theme.colorScheme.primary,
            onTap: () =>
                context.push('${Routes.review}?queue=duplicates&kind=$_kind'),
          ),
          const SizedBox(height: 12),

          _QueueCard(
            key: const Key('queue-body-links'),
            icon: Icons.accessibility_new,
            title: 'Body identity',
            count: bodyLinksCount,
            subtitle: 'Review identity evidence for body detections',
            color: theme.colorScheme.primary,
            onTap: () =>
                context.push('${Routes.review}?queue=bodyLinks&kind=$_kind'),
          ),
          const SizedBox(height: 12),

          _QueueCard(
            key: const Key('queue-excluded'),
            icon: Icons.visibility_off_outlined,
            title: 'Excluded & Corrected',
            count: excludedCount,
            subtitle: 'Elements marked as no owner, false, or dismissed',
            color: theme.colorScheme.onSurfaceVariant,
            onTap: () =>
                context.push('${Routes.review}?queue=excluded&kind=$_kind'),
          ),
        ],
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({
    super.key,
    required this.icon,
    required this.title,
    required this.count,
    required this.subtitle,
    required this.color,
    this.badge,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final int count;
  final String subtitle;
  final Color color;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              badge!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: count > 0
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: count > 0
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExcludedQueueScreen extends ConsumerWidget {
  const _ExcludedQueueScreen({required this.kind});
  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countsAsync = ref.watch(_excludedCountsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Excluded & Corrected')),
      body: countsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (counts) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              title: const Text('Faces with no owner'),
              subtitle: Text('${counts.facesNone} faces'),
              leading: const Icon(Icons.face_retouching_off),
            ),
            ListTile(
              title: const Text('Dismissed review suggestions'),
              subtitle: Text('${counts.facesDismissed} faces'),
              leading: const Icon(Icons.cancel_outlined),
            ),
            ListTile(
              title: const Text('Bodies with no owner'),
              subtitle: Text('${counts.bodiesNone} bodies'),
              leading: const Icon(Icons.person_off_outlined),
            ),
            ListTile(
              title: const Text('Hidden / False positive bodies'),
              subtitle: Text('${counts.bodiesHidden} bodies'),
              leading: const Icon(Icons.visibility_off),
            ),
          ],
        ),
      ),
    );
  }
}
