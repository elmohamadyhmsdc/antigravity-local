import 'package:flutter/material.dart';

import '../../data/api/dtos/analyze.dart';
import '../../data/files/file_store.dart';
import '../../domain/reface/pose_review.dart';
import '../../l10n/app_localizations.dart';
import '../shared/image_preview.dart';
import '../shared/screen_layout.dart';
import 'reface_video_trimmer.dart';

enum RefacePoseReviewAction { start, retry }

class RefacePoseReviewScreen extends StatelessWidget {
  const RefacePoseReviewScreen({
    super.key,
    required this.prepared,
    required this.files,
    required this.preview,
  });

  final PreparedRefaceReferences prepared;
  final FileStore files;
  final bool preview;

  String _angles(AppLocalizations l, Pose pose) => l.refacePoseAngles(
    pose.yaw.toStringAsFixed(1),
    pose.pitch.toStringAsFixed(1),
    pose.roll?.toStringAsFixed(1) ?? '—',
  );

  String _time(int milliseconds) =>
      '${trimTime(Duration(milliseconds: milliseconds))}.'
      '${(milliseconds % 1000).toString().padLeft(3, '0')}';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final report = prepared.report;
    final covered = report.poses.map(prepared.covers).toList();
    final count = covered.where((value) => value).length;
    final missing = count < covered.length;
    final incomplete =
        missing ||
        report.unreadableFrames > 0 ||
        report.framesWithoutPose > 0 ||
        report.facesWithoutPose > 0;
    return Scaffold(
      appBar: AppBar(title: Text(l.refacePoseReviewTitle)),
      bottomNavigationBar: StickyActionBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (missing)
              TextButton.icon(
                key: const Key('reface-retry-poses'),
                onPressed: () =>
                    Navigator.pop(context, RefacePoseReviewAction.retry),
                icon: const Icon(Icons.refresh),
                label: Text(l.refacePoseRetry),
              ),
            FilledButton(
              key: const Key('reface-approve-poses'),
              onPressed: prepared.portraits.isEmpty
                  ? null
                  : () => Navigator.pop(context, RefacePoseReviewAction.start),
              child: Text(
                preview
                    ? l.refacePreview
                    : incomplete
                    ? l.refacePoseStartPartial
                    : l.submitReface,
              ),
            ),
          ],
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.refacePoseFrames(
                      report.decodedFrames,
                      report.totalFrames,
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(l.refacePoseCoverage(count, covered.length)),
                  if (report.unreadableFrames > 0)
                    Text(l.refacePoseUnreadable(report.unreadableFrames)),
                  if (report.framesWithoutPose > 0)
                    Text(l.refacePoseNoFrame(report.framesWithoutPose)),
                  if (report.facesWithoutPose > 0)
                    Text(l.refacePoseNoFace(report.facesWithoutPose)),
                  if (prepared.portraits.isEmpty)
                    Text(
                      report.poses.isEmpty
                          ? l.refacePoseNoMeasurements
                          : l.refacePoseNoPortraits,
                    ),
                ],
              ),
            ),
          ),
          if (prepared.portraits.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  l.refacePosePortraits,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190,
                  mainAxisExtent: 182,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: prepared.portraits.length,
                itemBuilder: (context, index) {
                  final portrait = prepared.portraits[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: PreviewImage.file(
                          files.resolve(portrait.path),
                          cacheWidth: 360,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        switch (portrait.pose) {
                          final pose? => _angles(l, pose),
                          null => l.refacePoseUnknown,
                        },
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
          if (report.poses.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.refacePoseMeasured,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(l.refacePoseGrouping),
                  ],
                ),
              ),
            ),
            SliverList.builder(
              itemCount: report.poses.length,
              itemBuilder: (context, index) {
                final row = report.poses[index];
                return ListTile(
                  title: Text(_angles(l, row.pose)),
                  subtitle: Text(
                    l.refacePoseObservations(
                      row.count,
                      _time(row.timestampMs),
                      covered[index]
                          ? l.refacePoseMatched
                          : l.refacePoseMissing,
                    ),
                  ),
                  leading: Icon(
                    covered[index]
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_outlined,
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
