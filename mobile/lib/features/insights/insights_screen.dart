import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/repositories/insights_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../shared/empty_state.dart';
import '../shared/screen_layout.dart';

final insightsProvider = StreamProvider.autoDispose<LibraryInsights>(
  (ref) => InsightsRepository(ref.watch(databaseProvider)).watch(),
);

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.insightsTitle)),
      body: ref
          .watch(insightsProvider)
          .when(
            loading: () => const LoadingBox(),
            error: (_, _) =>
                RetryState(onRetry: () => ref.invalidate(insightsProvider)),
            data: (data) {
              if (data.stats.isEmpty) {
                return EmptyState(
                  icon: Icons.insights_outlined,
                  title: l10n.insightsEmpty,
                  actionLabel: l10n.scanLibrary,
                  onAction: () => context.push(Routes.sources),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ScreenIntro(
                    title: l10n.homeOrganize,
                    body: l10n.insightsHint,
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.insightsCoverage,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: data.mediaCount == 0
                                ? 0
                                : data.scanned / data.mediaCount,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.insightsScanned(data.scanned, data.mediaCount),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${l10n.statPhotos}: ${data.stats.photos} · ${l10n.statVideos}: ${data.stats.videos}',
                          ),
                          if (data.scanned < data.mediaCount)
                            TextButton.icon(
                              key: const Key('insights-scan'),
                              onPressed: () => context.push(Routes.sources),
                              icon: const Icon(Icons.document_scanner_outlined),
                              label: Text(l10n.scanLibrary),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.face_outlined),
                          title: Text(l10n.insightsFaces),
                          subtitle: Text(
                            l10n.insightsAssigned(
                              data.identifiedFaces,
                              data.stats.faces,
                            ),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.accessibility_new),
                          title: Text(l10n.insightsBodies),
                          subtitle: Text(
                            l10n.insightsAssigned(
                              data.identifiedBodies,
                              data.bodies,
                            ),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.person_search_outlined),
                          title: Text(l10n.insightsUnsorted),
                          trailing: Text('${data.stats.unsorted}'),
                          onTap: () => context.push(Routes.unsorted),
                        ),
                        if (data.failed > 0)
                          ListTile(
                            leading: const Icon(Icons.error_outline),
                            title: Text(l10n.insightsFailed),
                            trailing: Text('${data.failed}'),
                            onTap: () => context.push(Routes.sources),
                          ),
                      ],
                    ),
                  ),
                  if (data.topPeople.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      l10n.insightsTopPeople,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Column(
                        children: [
                          for (final person in data.topPeople)
                            ListTile(
                              leading: const Icon(Icons.person_outline),
                              title: Text(
                                person.name?.trim().isNotEmpty == true
                                    ? person.name!
                                    : l10n.personFallbackName(person.id),
                              ),
                              subtitle: Text(
                                l10n.insightsPersonMedia(person.mediaCount),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () =>
                                  context.push('${Routes.people}/${person.id}'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
    );
  }
}
