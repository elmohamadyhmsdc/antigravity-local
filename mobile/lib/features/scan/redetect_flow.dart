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
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
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
    ),
  );
  if (part == null || !context.mounted) return;

  final redetector = ref.read(redetectorProvider);
  final engine = ref.read(scanEngineProvider);
  final grouping = ref.read(groupingRunnerProvider);
  final waiting = ValueNotifier(engine.isRunning);
  final progress = ValueNotifier<(int, int)>((0, personId == null ? 1 : 0));
  var cancelled = false;
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          scrollable: true,
          title: Text(l.redetectTitle),
          content: ValueListenableBuilder<bool>(
            valueListenable: waiting,
            builder: (context, queued, _) => ValueListenableBuilder<(int, int)>(
              valueListenable: progress,
              builder: (context, value, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: queued || mediaId != null || value.$2 == 0
                        ? null
                        : value.$1 / value.$2,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    queued
                        ? l.scanPhotoActionWaiting
                        : l.redetectProgress(value.$1, value.$2),
                  ),
                ],
              ),
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
    ),
  );
  String message;
  try {
    final out = await engine.runLibraryAction(() async {
      waiting.value = false;
      if (cancelled) return null;
      final RedetectOutcome? result;
      if (mediaId != null) {
        result = await redetector.photo(mediaId, part);
      } else {
        result = await redetector.person(
          personId!,
          part,
          progress: (done, total) => progress.value = (done, total),
          cancelled: () => cancelled,
        );
      }
      // Keep follow-up grouping inside the same boundary, so it cannot collide
      // with the next scan item. Grouping failure does not undo detection.
      if (result != null) {
        try {
          await grouping.run(incremental: true);
        } catch (_) {}
      }
      return result;
    });
    message = cancelled && out == null
        ? l.redetectCancelled
        : out == null
        ? l.redetectVideosSkipped(1)
        : [
            l.redetectDone(out.faces, out.bodies),
            if (out.skippedVideos > 0)
              l.redetectVideosSkipped(out.skippedVideos),
          ].join(' ');
  } catch (e) {
    message = l.peopleActionError('$e');
  } finally {
    navigator.pop();
    progress.dispose();
    waiting.dispose();
  }
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
