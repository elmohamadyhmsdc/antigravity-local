import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../l10n/app_localizations.dart';
import '../review/review_screen.dart';
import 'face_grid.dart';

/// Faces that belong to nobody yet - pick some and assign them to a person (S09 on unsorted faces).
class UnsortedScreen extends ConsumerWidget {
  const UnsortedScreen({super.key, this.kind = 'person'});

  /// 'person' or 'character'.
  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sorting = ref.watch(manualSortRunningProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.unsortedCardTitle),
        actions: [
          TextButton(
            key: const Key('unsorted-auto-sort'),
            onPressed: sorting ? null : () => sortNow(context, ref),
            child: Text(sorting ? l10n.sorting : l10n.quickAutoSort),
          ),
          IconButton(
            tooltip: l10n.reviewTitle,
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: () => context.push(
              kind == 'character'
                  ? '${Routes.review}?kind=character'
                  : Routes.review,
            ),
          ),
        ],
      ),
      body: FaceGrid(personId: null, kind: kind),
    );
  }
}
