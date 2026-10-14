import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../studio_providers.dart';

class StudioScreen extends ConsumerWidget {
  const StudioScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(serverStatusProvider).value;
    final results = ref.watch(resultsProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.studioTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.studioHint,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          if (status is ServerBusy)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.studioBusyHint),
              ),
            ),
          if (status is! ServerReady && status is! ServerBusy)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.studioNeedsPc),
              ),
            ),
          Card(
            child: ListTile(
              key: const Key('studio-reface'),
              leading: const Icon(Icons.face_retouching_natural),
              title: Text(l10n.refaceTitle),
              subtitle: Text(l10n.refaceHint),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.reface),
            ),
          ),
          Card(
            child: ListTile(
              key: const Key('studio-restyle'),
              leading: const Icon(Icons.checkroom_outlined),
              title: Text(l10n.restyleTitle),
              subtitle: Text(l10n.restyleHint),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.restyle),
            ),
          ),
          Card(
            child: ListTile(
              key: const Key('studio-lora'),
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(l10n.loraTitle),
              subtitle: Text(l10n.loraHint),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.lora),
            ),
          ),
          Card(
            child: ListTile(
              key: const Key('studio-results'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('${l10n.privateResults} (${results.length})'),
              subtitle: Text(l10n.privateResultsHint),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.results),
            ),
          ),
        ],
      ),
    );
  }
}
