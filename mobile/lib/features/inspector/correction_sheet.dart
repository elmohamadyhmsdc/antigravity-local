import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/corrections/correction_scope.dart';
import '../../domain/corrections/correction_target.dart';
import '../../domain/corrections/correction_verb.dart';
import '../../library_providers.dart';
import '../../ui/scaffolds/sheet_scaffold.dart';
import '../../ui/sheets/undo_snackbar.dart';
import '../shared/crop_image.dart';
import '../shared/person_picker.dart';

/// L3a / P5c — CorrectionSheet: Unified bottom sheet for correcting links across all entity types.
class CorrectionSheet extends ConsumerStatefulWidget {
  const CorrectionSheet({
    super.key,
    required this.target,
    this.cropPath,
    this.title,
    this.subtitle,
    this.isVideo = false,
    this.onApplied,
  });

  final CorrectionTarget target;
  final String? cropPath;
  final String? title;
  final String? subtitle;
  final bool isVideo;
  final VoidCallback? onApplied;

  static Future<bool?> show({
    required BuildContext context,
    required CorrectionTarget target,
    String? cropPath,
    String? title,
    String? subtitle,
    bool isVideo = false,
    VoidCallback? onApplied,
  }) {
    return SheetScaffold.show<bool>(
      context: context,
      builder: (_) => CorrectionSheet(
        target: target,
        cropPath: cropPath,
        title: title,
        subtitle: subtitle,
        isVideo: isVideo,
        onApplied: onApplied,
      ),
    );
  }

  @override
  ConsumerState<CorrectionSheet> createState() => _CorrectionSheetState();
}

class _CorrectionSheetState extends ConsumerState<CorrectionSheet> {
  CorrectionScope _scope = CorrectionScope.track;
  bool _busy = false;

  String _verbTitle(CorrectionVerb verb) => switch (verb) {
    CorrectionVerb.reassign => 'Assign to another person',
    CorrectionVerb.notThisPerson => 'Not this person',
    CorrectionVerb.belongsToNoOne => 'Belongs to no one',
    CorrectionVerb.notARealThing => 'Not a real detection',
    CorrectionVerb.notSamePerson => 'Not the same person',
    CorrectionVerb.unlink => 'Unlink',
    CorrectionVerb.confirm => 'Confirm link',
  };

  String _verbSubtitle(CorrectionVerb verb) => switch (verb) {
    CorrectionVerb.reassign =>
      'Select an existing person or create a new profile',
    CorrectionVerb.notThisPerson =>
      'Exclude from linking to this person in future',
    CorrectionVerb.belongsToNoOne =>
      'Has no owner; stays in gallery with badge, excluded from auto-links',
    CorrectionVerb.notARealThing =>
      'False detection; hides and excludes from results',
    CorrectionVerb.notSamePerson =>
      'Separate distinct appearances and prevent grouping',
    CorrectionVerb.unlink => 'Remove link and allow automatic reassessment',
    CorrectionVerb.confirm => 'Lock link as manually verified',
  };

  IconData _verbIcon(CorrectionVerb verb) => switch (verb) {
    CorrectionVerb.reassign => Icons.person_add_outlined,
    CorrectionVerb.notThisPerson => Icons.person_off_outlined,
    CorrectionVerb.belongsToNoOne => Icons.do_not_disturb_on_outlined,
    CorrectionVerb.notARealThing => Icons.visibility_off_outlined,
    CorrectionVerb.notSamePerson => Icons.call_split_outlined,
    CorrectionVerb.unlink => Icons.link_off_outlined,
    CorrectionVerb.confirm => Icons.check_circle_outline,
  };

  Future<void> _handleVerb(CorrectionVerb verb) async {
    if (_busy) return;
    final service = ref.read(correctionServiceProvider);
    final effectiveScope = widget.isVideo ? _scope : CorrectionScope.single;

    int? targetPersonId;
    if (verb == CorrectionVerb.reassign) {
      final choice = await pickPerson(context, allowNew: true);
      if (choice == null || !mounted) return;
      targetPersonId = choice.personId;
    }

    setState(() => _busy = true);
    try {
      final result = await service.apply(
        widget.target,
        verb,
        scope: effectiveScope,
        targetPersonId: targetPersonId,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      widget.onApplied?.call();

      UndoSnackbar.show(
        context: context,
        message: 'Applied: ${_verbTitle(verb)} (${result.affectedCount})',
        onUndo: () async {
          await service.undo(result.undoToken);
          widget.onApplied?.call();
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(correctionServiceProvider);
    final allowed = service.allowedVerbs(widget.target);

    return SafeArea(
      key: const Key('correction-sheet'),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with preview thumbnail and description
              Row(
                children: [
                  if (widget.cropPath != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: CropImage(
                          path: widget.cropPath,
                          placeholderIcon: Icons.crop_original,
                        ),
                      ),
                    ),
                  if (widget.cropPath != null) const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title ?? 'Correct link',
                          key: const Key('correction-title'),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (widget.subtitle != null)
                          Text(
                            widget.subtitle!,
                            key: const Key('correction-subtitle'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Scope picker for video
              if (widget.isVideo) ...[
                Text(
                  'Correction scope',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<CorrectionScope>(
                  key: const Key('correction-scope-picker'),
                  segments: const [
                    ButtonSegment<CorrectionScope>(
                      value: CorrectionScope.track,
                      label: Text('This appearance'),
                      icon: Icon(Icons.timelapse_outlined),
                    ),
                    ButtonSegment<CorrectionScope>(
                      value: CorrectionScope.wholeVideo,
                      label: Text('Whole video'),
                      icon: Icon(Icons.video_library_outlined),
                    ),
                  ],
                  selected: {_scope},
                  onSelectionChanged: (selected) {
                    setState(() => _scope = selected.first);
                  },
                ),
                const SizedBox(height: 16),
              ],

              const Divider(),

              // Verbs list
              for (final verb in allowed)
                ListTile(
                  key: Key('correction-verb-${verb.name}'),
                  leading: Icon(_verbIcon(verb)),
                  title: Text(_verbTitle(verb)),
                  subtitle: Text(_verbSubtitle(verb)),
                  enabled: !_busy,
                  onTap: () => _handleVerb(verb),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
