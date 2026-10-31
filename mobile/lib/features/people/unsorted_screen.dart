import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../l10n/app_localizations.dart';
import 'face_grid.dart';

/// Faces that belong to nobody yet - pick some and assign them to a person (S09 on unsorted faces).
class UnsortedScreen extends StatelessWidget {
  const UnsortedScreen({super.key, this.kind = 'person'});

  /// 'person' or 'character'.
  final String kind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.unsortedCardTitle),
        actions: [
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
