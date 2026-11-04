import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/db/app_database.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../library_providers.dart';
import '../../domain/pose/exposed_matching.dart';
import 'pose_visuals.dart';

class BodyComparisonSheet extends ConsumerStatefulWidget {
  const BodyComparisonSheet({
    super.key,
    required this.referenceId,
    required this.candidateId,
    required this.title,
    this.similarity,
    this.coverage,
    this.area,
    this.showPose = true,
  });
  final int referenceId, candidateId;
  final String title;
  final double? similarity, coverage;
  final String? area;
  final bool showPose;
  @override
  ConsumerState<BodyComparisonSheet> createState() =>
      _BodyComparisonSheetState();
}

class _BodyComparisonSheetState extends ConsumerState<BodyComparisonSheet> {
  late final _content = _load();
  bool _overlay = true;
  double? _areaSimilarity;

  Future<List<({BodyRow body, MediaRow? media})>> _load() async {
    final db = ref.read(databaseProvider);
    final rows = <({BodyRow body, MediaRow? media})>[];
    if (widget.area != null) {
      _areaSimilarity = await ref
          .read(exposedMatcherProvider)
          .similarityBetween(
            widget.referenceId,
            widget.candidateId,
            ExposedKind.values.byName(widget.area!),
          );
    }
    for (final id in [widget.referenceId, widget.candidateId]) {
      final body = await (db.select(
        db.bodies,
      )..where((b) => b.id.equals(id))).getSingleOrNull();
      if (body == null) throw StateError('Body no longer exists');
      final media = await (db.select(
        db.media,
      )..where((m) => m.id.equals(body.mediaId ?? -1))).getSingleOrNull();
      rows.add((body: body, media: media));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .88,
        child: FutureBuilder(
          future: _content,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text(l.bodiesLoadFailed));
            }
            final rows = snapshot.data;
            if (rows == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Text(l.discoveryCompareHint),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                i == 0
                                    ? l.groupPoseReference
                                    : l.discoveryCandidate,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: SizedBox(
                                  height: 260,
                                  child: InteractiveViewer(
                                    maxScale: 4,
                                    child: BodyCropAnnotatedView(
                                      cropPath: rows[i].body.cropPath,
                                      kpts: rows[i].body.kpts,
                                      bbox: (
                                        x: rows[i].body.bboxX,
                                        y: rows[i].body.bboxY,
                                        w: rows[i].body.bboxW,
                                        h: rows[i].body.bboxH,
                                      ),
                                      imageSize:
                                          rows[i].media?.width == null ||
                                              rows[i].media?.height == null
                                          ? null
                                          : Size(
                                              rows[i].media!.width!.toDouble(),
                                              rows[i].media!.height!.toDouble(),
                                            ),
                                      showSkeleton:
                                          _overlay &&
                                          widget.area == null &&
                                          widget.showPose,
                                      showArea: _overlay && widget.area != null,
                                      area: widget.area,
                                    ),
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: rows[i].body.mediaId == null
                                    ? null
                                    : () => context.push(
                                        '${Routes.media}/${rows[i].body.mediaId}',
                                      ),
                                child: Text(l.bodyActionOpenPhoto),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (widget.showPose || widget.area != null)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilterChip(
                        key: const Key('compare-overlay'),
                        selected: _overlay,
                        avatar: Icon(
                          widget.area == null
                              ? Icons.accessibility_new
                              : Icons.highlight_alt,
                        ),
                        label: Text(
                          widget.area == null
                              ? l.discoverySkeleton
                              : l.discoveryAreaGuide,
                        ),
                        onSelected: (value) => setState(() => _overlay = value),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (widget.similarity != null || _areaSimilarity != null)
                    Text(
                      l.discoverySimilarity(
                        ((widget.similarity ?? _areaSimilarity)! * 100).round(),
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  if (widget.coverage != null)
                    Text(l.discoveryCoverage((widget.coverage! * 100).round())),
                  const SizedBox(height: 8),
                  Text(
                    widget.area != null
                        ? l.discoveryAreaPrecision
                        : widget.showPose
                        ? l.discoveryPosePrecision
                        : l.discoveryOutfitIntro,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.tonalIcon(
                    key: const Key('compare-inspect'),
                    onPressed: () => Navigator.pop(context, 'inspect'),
                    icon: const Icon(Icons.tune),
                    label: Text(l.discoveryInspect),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
