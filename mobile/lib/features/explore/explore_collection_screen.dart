import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../l10n/app_localizations.dart';
import '../bodies/bodies_screen.dart';
import '../marks/person_marks_screen.dart';
import '../shared/person_picker.dart';
import '../video_actions/video_actions_screen.dart';

/// E2 / P7 — ExploreCollectionScreen & ExploreCollectionView:
/// Unified collection view for any visual kind:
/// `all, poses, outfits, groupPoses, equipment, areas, marks, actions`.
class ExploreCollectionScreen extends StatelessWidget {
  const ExploreCollectionScreen({
    super.key,
    required this.kind,
    this.id,
    this.personId,
    this.similar,
    this.colours,
    this.tab,
  });

  final String kind;
  final String? id;
  final int? personId;
  final int? similar;
  final int? colours;
  final int? tab;

  @override
  Widget build(BuildContext context) {
    return ExploreCollectionView(
      kind: kind,
      clusterId: id,
      personId: personId,
      similar: similar,
      colours: colours,
      initialTab: tab,
    );
  }
}

class ExploreCollectionView extends ConsumerStatefulWidget {
  const ExploreCollectionView({
    super.key,
    required this.kind,
    this.clusterId,
    this.personId,
    this.similar,
    this.colours,
    this.initialTab,
  });

  final String kind;
  final String? clusterId;
  final int? personId;
  final int? similar;
  final int? colours;
  final int? initialTab;

  @override
  ConsumerState<ExploreCollectionView> createState() =>
      _ExploreCollectionViewState();
}

class _ExploreCollectionViewState extends ConsumerState<ExploreCollectionView> {
  bool _noOwnerOnly = false;

  int _kindToTab(String kind) {
    return switch (kind) {
      'poses' => 1,
      'outfits' => 2,
      'groupPoses' => 3,
      'equipment' => 4,
      'areas' => 5,
      _ => 0,
    };
  }

  String _titleForKind(String kind, AppLocalizations l10n) {
    return switch (kind) {
      'all' => 'All Bodies',
      'poses' => l10n.bodiesTabPoses,
      'outfits' => l10n.bodiesTabOutfits,
      'groupPoses' => 'Group Poses',
      'equipment' => l10n.bodiesTabEquipment,
      'areas' => l10n.bodiesTabAreas,
      'marks' => 'Marks & Tattoos',
      'actions' => 'Actions',
      _ => kind,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = _titleForKind(widget.kind, l10n);

    // Kinds that have specialized screens:
    if (widget.kind == 'actions') {
      return const VideoActionsScreen();
    }
    if (widget.kind == 'marks') {
      if (widget.personId != null) {
        return PersonMarksScreen(personId: widget.personId!);
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Marks & Tattoos')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.draw_outlined, size: 48),
              const SizedBox(height: 12),
              const Text('Select a person to view marks'),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () async {
                  final person = await pickPerson(
                    context,
                    allowNew: false,
                    kind: 'all',
                  );
                  if (person?.personId != null && context.mounted) {
                    context.push(
                      '${Routes.marks}?personId=${person!.personId}',
                    );
                  }
                },
                child: const Text('Pick Person'),
              ),
            ],
          ),
        ),
      );
    }

    final tabIndex = widget.initialTab ?? _kindToTab(widget.kind);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            key: const Key('explore-filter-action'),
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              setState(() => _noOwnerOnly = !_noOwnerOnly);
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                FilterChip(
                  key: const Key('filter-no-owner'),
                  label: const Text('No owner'),
                  selected: _noOwnerOnly,
                  onSelected: (val) {
                    setState(() => _noOwnerOnly = val);
                  },
                ),
                if (widget.similar != null) ...[
                  const SizedBox(width: 8),
                  InputChip(
                    key: const Key('filter-similar'),
                    label: Text('Similar to #${widget.similar}'),
                    selected: true,
                    onDeleted: () {
                      context.pushReplacement('/explore/${widget.kind}');
                    },
                  ),
                ],
                if (widget.colours != null) ...[
                  const SizedBox(width: 8),
                  InputChip(
                    key: const Key('filter-colours'),
                    label: Text('Colours of #${widget.colours}'),
                    selected: true,
                    onDeleted: () {
                      context.pushReplacement('/explore/${widget.kind}');
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      body: BodiesScreen(
        personId: widget.personId,
        initialTab: tabIndex,
        initialSimilar: widget.similar,
        initialSimilarColours: widget.colours,
      ),
    );
  }
}
