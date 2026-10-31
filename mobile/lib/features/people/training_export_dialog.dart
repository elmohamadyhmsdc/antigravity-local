import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/repositories/people_repository.dart';
import '../../domain/export/export_selection.dart';
import '../../domain/export/training_export.dart';
import '../../l10n/app_localizations.dart';
import 'training_export_controller.dart';

Future<void> showTrainingExportDialog(
  BuildContext context, {
  required PersonSummary person,
  required String personName,
}) => showDialog<void>(
  context: context,
  builder: (_) => TrainingExportDialog(person: person, personName: personName),
);

/// Export-for-training: options, then progress / cancel / share. The work belongs to
/// [trainingExportProvider], so closing this dialog does not stop a running export.
class TrainingExportDialog extends ConsumerStatefulWidget {
  const TrainingExportDialog({
    super.key,
    required this.person,
    required this.personName,
  });

  final PersonSummary person;
  final String personName;

  @override
  ConsumerState<TrainingExportDialog> createState() => _State();
}

class _State extends ConsumerState<TrainingExportDialog> {
  var _faces = true;
  var _bodies = false;
  var _faceSize = 512;
  var _bodySize = 1024;
  var _perVideo = 40;

  TrainingExportOptions get _options => TrainingExportOptions(
    personId: widget.person.id,
    faces: _faces,
    bodies: _bodies,
    faceSize: _faceSize,
    bodyLongSide: _bodySize,
    selection: ExportSelectionOptions(maxPerVideo: _perVideo),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(trainingExportProvider);
    final mine = state.personId == widget.person.id;
    final controller = ref.read(trainingExportProvider.notifier);
    final busyElsewhere = state.running && !mine;
    final showOptions =
        !(mine && state.phase != TrainingExportPhase.idle) && !busyElsewhere;
    return AlertDialog(
      title: Text(l10n.exportTrainingTitle),
      content: SingleChildScrollView(
        child: showOptions
            ? _optionsForm(l10n)
            : _status(l10n, state, mine: mine),
      ),
      actions: showOptions
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  MaterialLocalizations.of(context).cancelButtonLabel,
                ),
              ),
              FilledButton(
                key: const Key('export-training-start'),
                onPressed: _faces || _bodies
                    ? () => controller.start(
                        _options,
                        personName: widget.personName,
                        notificationTitle: l10n.exportTrainingNotification,
                      )
                    : null,
                child: Text(l10n.exportTrainingStart),
              ),
            ]
          : _statusActions(l10n, state, controller, mine: mine),
    );
  }

  Widget _optionsForm(AppLocalizations l10n) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(l10n.exportTrainingHelp(widget.personName)),
      const SizedBox(height: 8),
      CheckboxListTile(
        key: const Key('export-training-faces'),
        contentPadding: EdgeInsets.zero,
        value: _faces,
        onChanged: (v) => setState(() => _faces = v ?? false),
        title: Text(l10n.exportTrainingFaces),
      ),
      CheckboxListTile(
        key: const Key('export-training-bodies'),
        contentPadding: EdgeInsets.zero,
        value: _bodies,
        onChanged: (v) => setState(() => _bodies = v ?? false),
        title: Text(l10n.exportTrainingBodies),
      ),
      if (!_faces && !_bodies)
        Text(
          l10n.exportTrainingNeedKind,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (_faces)
        _choice(
          l10n.exportTrainingFaceSize,
          const [512, 768, 1024],
          _faceSize,
          (v) => setState(() => _faceSize = v),
        ),
      if (_bodies)
        _choice(
          l10n.exportTrainingBodySize,
          const [1024, 1536, 2048],
          _bodySize,
          (v) => setState(() => _bodySize = v),
        ),
      _choice(
        l10n.exportTrainingPerVideo,
        const [20, 40, 80],
        _perVideo,
        (v) => setState(() => _perVideo = v),
      ),
    ],
  );

  Widget _choice(
    String label,
    List<int> values,
    int selected,
    ValueChanged<int> onSelected,
  ) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final v in values)
              ChoiceChip(
                label: Text('$v'),
                selected: v == selected,
                onSelected: (_) => onSelected(v),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _status(
    AppLocalizations l10n,
    TrainingExportState state, {
    required bool mine,
  }) {
    if (!mine) return Text(l10n.exportTrainingPlanning);
    final progress = state.progress;
    switch (state.phase) {
      case TrainingExportPhase.running:
        final total = progress?.total ?? 0;
        final text = switch (progress?.phase) {
          'packing' => l10n.exportTrainingPacking,
          'exporting' => l10n.exportTrainingRunning(progress!.done, total),
          _ => l10n.exportTrainingPlanning,
        };
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress?.phase == 'exporting' && total > 0
                  ? progress!.done / total
                  : null,
            ),
          ],
        );
      case TrainingExportPhase.failed:
        return Text(l10n.exportTrainingFailed(state.error ?? ''));
      case TrainingExportPhase.cancelled:
        return Text(l10n.exportTrainingStopped);
      case TrainingExportPhase.done:
        final r = state.result!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              r.zip == null
                  ? l10n.exportTrainingNothing
                  : l10n.exportTrainingDone(r.exported),
            ),
            if (r.tooSmall + r.missing + r.failed > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.exportTrainingSkipped(r.tooSmall, r.missing, r.failed),
                ),
              ),
          ],
        );
      case TrainingExportPhase.idle:
        return const SizedBox.shrink();
    }
  }

  List<Widget> _statusActions(
    AppLocalizations l10n,
    TrainingExportState state,
    TrainingExportController controller, {
    required bool mine,
  }) {
    final navigator = Navigator.of(context);
    final close = TextButton(
      onPressed: () => Navigator.pop(context),
      child: Text(MaterialLocalizations.of(context).closeButtonLabel),
    );
    if (!mine) return [close];
    switch (state.phase) {
      case TrainingExportPhase.running:
        return [
          close,
          TextButton(
            key: const Key('export-training-stop'),
            onPressed: controller.cancel,
            child: Text(l10n.exportTrainingStop),
          ),
        ];
      case TrainingExportPhase.done:
        final zip = state.result?.zip;
        return [
          TextButton(
            onPressed: () async {
              await controller.dismiss(deleteZip: true);
              navigator.pop();
            },
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
          if (zip != null)
            FilledButton(
              key: const Key('export-training-share'),
              onPressed: () => SharePlus.instance.share(
                ShareParams(files: [XFile(zip.path)]),
              ),
              child: Text(l10n.exportTrainingShare),
            ),
        ];
      case TrainingExportPhase.cancelled:
      case TrainingExportPhase.failed:
        return [
          close,
          FilledButton(
            onPressed: () => controller.dismiss(),
            child: Text(l10n.exportTrainingStart),
          ),
        ];
      case TrainingExportPhase.idle:
        return [close];
    }
  }
}
