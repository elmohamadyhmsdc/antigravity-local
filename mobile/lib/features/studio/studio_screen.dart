import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../studio_providers.dart';
import '../shared/screen_layout.dart';

class StudioScreen extends ConsumerWidget {
  const StudioScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(serverStatusProvider).value;
    final results = ref.watch(resultsProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.studioTitle),
        actions: [
          IconButton(
            key: const Key('studio-results'),
            tooltip: l10n.privateResults,
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () => context.push(Routes.results),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          ScreenIntro(title: l10n.studioIntro, body: l10n.studioHint),
          if (status is ServerBusy ||
              (status is! ServerReady && status is! ServerBusy))
            Card(
              child: ListTile(
                leading: Icon(
                  status is ServerBusy
                      ? Icons.schedule
                      : Icons.computer_outlined,
                ),
                title: Text(
                  status is ServerBusy
                      ? l10n.studioBusyHint
                      : l10n.studioNeedsPc,
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
            key: const Key('studio-lora'),
            icon: Icons.auto_awesome_outlined,
            title: l10n.loraTitle,
            subtitle: l10n.studioLoraDescription,
            onTap: () => context.push(Routes.lora),
          ),
          SectionHeading(title: l10n.studioSaved),
          ActionRow(
            key: const Key('studio-results-row'),
            icon: Icons.photo_library_outlined,
            title: '${l10n.privateResults} (${results.length})',
            subtitle: l10n.privateResultsHint,
            onTap: () => context.push(Routes.results),
          ),
        ],
      ),
    );
  }
}
