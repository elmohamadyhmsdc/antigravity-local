import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/db/app_database.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../studio_providers.dart';
import '../../ui/collection/segmented_bar.dart';
import '../../ui/scaffolds/tab_root_scaffold.dart';
import '../results/results_screen.dart';
import '../shared/empty_state.dart';
import '../shared/screen_layout.dart';

class StudioScreen extends ConsumerStatefulWidget {
  const StudioScreen({super.key});
  @override
  ConsumerState<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends ConsumerState<StudioScreen> {
  int _activeTab = 0;
  String _category = 'results';

  void _showResults() => setState(() {
    _activeTab = 1;
    _category = 'results';
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return TabRootScaffold(
      title: Text(l.studioTitle),
      body: Column(
        children: [
          SegmentedBar<int>(
            segments: const [
              SegmentItem(value: 0, label: 'Create', icon: Icons.add),
              SegmentItem(
                value: 1,
                label: 'My Library',
                icon: Icons.folder_outlined,
              ),
            ],
            selected: _activeTab,
            onSelected: (v) => setState(() => _activeTab = v),
          ),
          Expanded(
            child: IndexedStack(
              index: _activeTab,
              children: [
                _create(context, l),
                Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(
                        children: [
                          for (final item in const [
                            ('results', 'Results'),
                            ('models', 'Models'),
                            ('datasets', 'Datasets'),
                          ])
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 8),
                              child: ChoiceChip(
                                key: Key('studio-library-${item.$1}'),
                                label: Text(item.$2),
                                selected: _category == item.$1,
                                onSelected: (_) =>
                                    setState(() => _category = item.$1),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: switch (_category) {
                        'models' => _models(context, l),
                        'datasets' => _datasets(context, l),
                        _ => ResultsCollection(
                          onCreate: () => setState(() => _activeTab = 0),
                        ),
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _create(BuildContext context, AppLocalizations l) {
    final status = ref.watch(serverStatusProvider).value;
    return ListView(
      key: const PageStorageKey('studio-create'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        if (status is! ServerReady)
          Card(
            child: ListTile(
              leading: Icon(
                status is ServerBusy ? Icons.schedule : Icons.computer_outlined,
              ),
              title: Text(
                status is ServerBusy ? l.studioBusyHint : l.studioNeedsPc,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(
                status is ServerBusy
                    ? Routes.activity
                    : Routes.settingsComputer,
              ),
            ),
          ),
        ActionRow(
          key: const Key('studio-reface'),
          emphasized: true,
          icon: Icons.face_retouching_natural,
          title: l.refaceTitle,
          subtitle: l.studioRefaceDescription,
          onTap: () => context.push(Routes.reface),
        ),
        const Divider(),
        ActionRow(
          key: const Key('studio-restyle'),
          icon: Icons.checkroom_outlined,
          title: l.restyleTitle,
          subtitle: l.studioRestyleDescription,
          onTap: () => context.push(Routes.restyle),
        ),
        const Divider(),
        ActionRow(
          key: const Key('studio-generate'),
          icon: Icons.auto_awesome_outlined,
          title: 'Generate',
          subtitle: 'Create images with a trained model',
          onTap: () => context.push(Routes.studioGenerate),
        ),
        const Divider(),
        ActionRow(
          key: const Key('studio-lora'),
          icon: Icons.model_training_outlined,
          title: l.loraTrain,
          subtitle: 'Prepare examples and train a model',
          onTap: () => context.push(Routes.lora),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          key: const Key('studio-results'),
          onPressed: _showResults,
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(l.privateResults),
        ),
      ],
    );
  }

  Widget _models(BuildContext context, AppLocalizations l) => ref
      .watch(lorasProvider)
      .when(
        loading: () => const LoadingBox(),
        error: (_, _) =>
            RetryState(onRetry: () => ref.invalidate(lorasProvider)),
        data: (models) => models.isEmpty
            ? EmptyState(
                icon: Icons.model_training_outlined,
                title: l.loraNoModels,
                actionLabel: l.loraTrain,
                onAction: () => context.push(Routes.lora),
              )
            : ListView(
                key: const PageStorageKey('studio-models'),
                padding: const EdgeInsets.all(16),
                children: [
                  for (final model in models)
                    Card(
                      child: ListTile(
                        key: Key('studio-model-${model.id}'),
                        leading: const Icon(Icons.model_training_outlined),
                        title: Text(model.triggerWord),
                        subtitle: const Text(
                          'Open model details and generate images',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            context.push('${Routes.studioModels}/${model.id}'),
                      ),
                    ),
                ],
              ),
      );

  Widget _datasets(BuildContext context, AppLocalizations l) => ref
      .watch(datasetsProvider)
      .when(
        loading: () => const LoadingBox(),
        error: (_, _) =>
            RetryState(onRetry: () => ref.invalidate(datasetsProvider)),
        data: (datasets) => ListView(
          key: const PageStorageKey('studio-datasets'),
          padding: const EdgeInsets.all(16),
          children: [
            FilledButton.tonalIcon(
              key: const Key('studio-new-dataset'),
              onPressed: () => context.push(Routes.studioDatasetsNew),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(l.loraDatasetBuild),
            ),
            if (datasets.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(l.loraNoDatasets),
              ),
            for (final dataset in datasets) _DatasetTile(dataset: dataset),
          ],
        ),
      );
}

class _DatasetTile extends StatelessWidget {
  const _DatasetTile({required this.dataset});
  final DatasetRow dataset;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      key: Key('studio-dataset-${dataset.id}'),
      leading: const Icon(Icons.folder_outlined),
      title: Text(dataset.triggerWord),
      subtitle: const Text('Review examples and prepare training'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('${Routes.studioDatasets}/${dataset.id}'),
    ),
  );
}
