import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../studio_providers.dart';
import '../../ui/collection/segmented_bar.dart';
import '../../ui/scaffolds/tab_root_scaffold.dart';
import '../shared/screen_layout.dart';

/// ST1 / P8a — StudioScreen: Hub for AI creation and personal library.
class StudioScreen extends ConsumerStatefulWidget {
  const StudioScreen({super.key});

  @override
  ConsumerState<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends ConsumerState<StudioScreen> {
  int _activeTab = 0; // 0: Create, 1: My Library
  String _activeLibraryCategory = 'results'; // 'results', 'models', 'datasets'

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(serverStatusProvider).value;
    final results = ref.watch(resultsProvider).value ?? const [];

    return TabRootScaffold(
      title: Text(l10n.studioTitle),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SegmentedBar<int>(
            segments: const [
              SegmentItem(value: 0, label: 'Create'),
              SegmentItem(value: 1, label: 'My Library'),
            ],
            selected: _activeTab,
            onSelected: (tab) => setState(() => _activeTab = tab),
          ),
        ),
      ),
      body: _activeTab == 0
          ? _buildCreateTab(context, l10n, status, results)
          : _buildLibraryTab(context, l10n, results),
    );
  }

  Widget _buildCreateTab(
    BuildContext context,
    AppLocalizations l10n,
    ServerStatus? status,
    List<dynamic> results,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        if (status is ServerBusy ||
            (status is! ServerReady && status is! ServerBusy))
          Card(
            child: ListTile(
              leading: Icon(
                status is ServerBusy ? Icons.schedule : Icons.computer_outlined,
              ),
              title: Text(
                status is ServerBusy ? l10n.studioBusyHint : l10n.studioNeedsPc,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(
                status is ServerBusy ? Routes.jobs : Routes.connection,
              ),
            ),
          ),
        SectionHeading(title: l10n.studioTools),
        ActionRow(
          key: const Key('studio-reface'),
          emphasized: true,
          icon: Icons.face_retouching_natural,
          title: l10n.refaceTitle,
          subtitle: l10n.studioRefaceDescription,
          onTap: () => context.push(Routes.reface),
        ),
        const Divider(),
        ActionRow(
          key: const Key('studio-restyle'),
          icon: Icons.checkroom_outlined,
          title: l10n.restyleTitle,
          subtitle: l10n.studioRestyleDescription,
          onTap: () => context.push(Routes.restyle),
        ),
        const Divider(),
        ActionRow(
          key: const Key('studio-generate'),
          icon: Icons.auto_awesome,
          title: 'Generate',
          subtitle: 'Generate photos using trained character or person models',
          onTap: () => context.push(Routes.studioGenerate),
        ),
        const Divider(),
        ActionRow(
          key: const Key('studio-lora'),
          icon: Icons.auto_awesome_outlined,
          title: l10n.loraTitle,
          subtitle: l10n.studioLoraDescription,
          onTap: () => context.push(Routes.lora),
        ),
        const SizedBox(height: 16),
        SectionHeading(
          title: l10n.privateResults,
          trailing: TextButton(
            key: const Key('studio-results'),
            onPressed: () => context.push(Routes.results),
            child: const Text('See all'),
          ),
        ),
        ActionRow(
          key: const Key('studio-results-row'),
          icon: Icons.photo_library_outlined,
          title: '${l10n.privateResults} (${results.length})',
          subtitle: l10n.privateResultsHint,
          onTap: () => context.push(Routes.results),
        ),
      ],
    );
  }

  Widget _buildLibraryTab(
    BuildContext context,
    AppLocalizations l10n,
    List<dynamic> results,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: Text('Results (${results.length})'),
                selected: _activeLibraryCategory == 'results',
                onSelected: (s) {
                  if (s) setState(() => _activeLibraryCategory = 'results');
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Models'),
                selected: _activeLibraryCategory == 'models',
                onSelected: (s) {
                  if (s) setState(() => _activeLibraryCategory = 'models');
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Datasets'),
                selected: _activeLibraryCategory == 'datasets',
                onSelected: (s) {
                  if (s) setState(() => _activeLibraryCategory = 'datasets');
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ActionRow(
          key: const Key('studio-models'),
          icon: Icons.model_training_outlined,
          title: 'Models',
          onTap: () => context.push(Routes.lora),
        ),
        ActionRow(
          key: const Key('studio-datasets'),
          icon: Icons.folder_outlined,
          title: 'Datasets',
          onTap: () => context.push(Routes.lora),
        ),
        ActionRow(
          key: const Key('studio-activity'),
          icon: Icons.pending_actions_outlined,
          title: 'Activity',
          onTap: () => context.push(Routes.jobs),
        ),
      ],
    );
  }
}
