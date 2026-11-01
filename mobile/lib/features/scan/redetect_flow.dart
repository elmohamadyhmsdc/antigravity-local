import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/scan/redetect.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';

/// "Detect again" for one photo (`mediaId`) or every photo of a person (`personId`): asks
/// faces / bodies / both, shows progress, reports the result and groups what is new.
Future<void> redetectFlow(
  BuildContext context,
  WidgetRef ref, {
  int? mediaId,
  int? personId,
}) async {
  assert((mediaId == null) != (personId == null));
  final l = AppLocalizations.of(context);
  final part = await showModalBottomSheet<RedetectPart>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              l.redetectTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: Text(l.redetectNote),
          ),
          const Divider(height: 1),
          for (final (value, label, icon) in [
            (RedetectPart.both, l.redetectBoth, Icons.center_focus_strong),
            (RedetectPart.faces, l.redetectFaces, Icons.face_outlined),
            (RedetectPart.bodies, l.redetectBodies, Icons.accessibility_new),
          ])
            ListTile(
              key: Key('redetect-${value.name}'),
              leading: Icon(icon),
              title: Text(label),
              onTap: () => Navigator.pop(context, value),
            ),
        ],
      ),
    ),
  );
  if (part == null || !context.mounted) return;

  final redetector = ref.read(redetectorProvider);
  final progress = ValueNotifier<(int, int)>((0, personId == null ? 1 : 0));
  var cancelled = false;
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l.redetectTitle),
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: progress,
          builder: (context, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: value.$2 == 0 ? null : value.$1 / value.$2,
              ),
              const SizedBox(height: 12),
              Text(l.redetectProgress(value.$1, value.$2)),
            ],
          ),
        ),
        actions: [
          if (personId != null)
            TextButton(
              onPressed: () => cancelled = true,
              child: Text(l.cancel),
            ),
        ],
      ),
    ),
  );
  String message;
  try {
    final RedetectOutcome? out;
    if (mediaId != null) {
      out = await redetector.photo(mediaId, part);
    } else {
      out = await redetector.person(
        personId!,
        part,
        progress: (done, total) => progress.value = (done, total),
        cancelled: () => cancelled,
      );
    }
    message = out == null
        ? l.redetectVideosSkipped(1)
        : [
            l.redetectDone(out.faces, out.bodies),
            if (out.skippedVideos > 0)
              l.redetectVideosSkipped(out.skippedVideos),
          ].join(' ');
    // New faces join their people the same way a scan's do.
    ref.read(groupingRunnerProvider).run(incremental: true).ignore();
  } catch (e) {
    message = l.peopleActionError('$e');
  } finally {
    navigator.pop();
    progress.dispose();
  }
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
