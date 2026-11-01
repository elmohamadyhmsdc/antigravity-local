import '../shared/image_preview.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../core/router.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/artifact_context.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../studio_providers.dart';
import '../jobs/jobs_screen.dart';
import '../shared/empty_state.dart';
import '../shared/screen_layout.dart';
import '../privacy/app_lock.dart';

class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({super.key});
  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  bool _favourites = false;
  String? _kind;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.privateResults)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(l10n.resultsBrowseHint),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: Text(l10n.favouriteResults),
                  selected: _favourites,
                  onSelected: (v) => setState(() => _favourites = v),
                ),
                FilterChip(
                  label: Text(l10n.resultPhoto),
                  selected: _kind == 'image',
                  onSelected: (v) => setState(() => _kind = v ? 'image' : null),
                ),
                FilterChip(
                  label: Text(l10n.resultVideo),
                  selected: _kind == 'video',
                  onSelected: (v) => setState(() => _kind = v ? 'video' : null),
                ),
              ],
            ),
          ),
          Expanded(
            child: ref
                .watch(resultsProvider)
                .when(
                  loading: () => const LoadingBox(),
                  error: (_, _) => RetryState(
                    onRetry: () => ref.invalidate(resultsProvider),
                  ),
                  data: (results) {
                    final shown = results
                        .where(
                          (r) =>
                              (!_favourites || r.favourite) &&
                              (_kind == null || r.mime.startsWith('$_kind/')),
                        )
                        .toList();
                    if (shown.isEmpty) {
                      return EmptyState(
                        icon: Icons.photo_library_outlined,
                        title: results.isEmpty
                            ? l10n.resultEmpty
                            : l10n.resultsNoMatches,
                        body: results.isEmpty ? l10n.resultEmptyHint : null,
                        actionLabel: results.isEmpty
                            ? l10n.navStudio
                            : l10n.clearFilters,
                        onAction: results.isEmpty
                            ? () => context.go(Routes.studio)
                            : () => setState(() {
                                _kind = null;
                                _favourites = false;
                              }),
                      );
                    }
                    return GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 240,
                            childAspectRatio: .8,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                      itemCount: shown.length,
                      itemBuilder: (context, index) {
                        final r = shown[index];
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: Key('result-${r.id}'),
                            onTap: () =>
                                context.push('${Routes.results}/${r.id}'),
                            child: Column(
                              children: [
                                Expanded(
                                  child: r.mime == 'video/mp4'
                                      ? const Center(
                                          child: Icon(
                                            Icons.play_circle_outline,
                                            size: 48,
                                          ),
                                        )
                                      : !r.mime.startsWith('image/')
                                      ? const Center(
                                          child: Icon(
                                            Icons.inventory_2_outlined,
                                            size: 48,
                                          ),
                                        )
                                      : PreviewImage.file(
                                          ref
                                              .read(fileStoreProvider)
                                              .resolve(r.path),
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          cacheWidth: 480,
                                          errorBuilder: (_, _, _) => const Icon(
                                            Icons.broken_image_outlined,
                                          ),
                                        ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    '${jobTypeLabel(l10n, r.type)}${r.favourite ? ' ★' : ''}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}

class ResultDetailScreen extends ConsumerStatefulWidget {
  const ResultDetailScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<ResultDetailScreen> createState() => _ResultDetailScreenState();
}

class _ResultDetailScreenState extends ConsumerState<ResultDetailScreen> {
  double _comparison = .5;
  bool _before = false;
  Widget _exportActions(BuildContext context, WidgetRef ref, ResultRow result) {
    final l10n = AppLocalizations.of(context);
    final files = ref.read(fileStoreProvider);
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        if (result.mime.startsWith('image/') ||
            result.mime.startsWith('video/'))
          OutlinedButton.icon(
            onPressed: () async {
              try {
                final saved = await ref
                    .read(privacyServiceProvider)
                    .exportMedia(files.resolve(result.path), result.mime);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        saved
                            ? l10n.savedToGallery
                            : 'Could not save to gallery',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('$e')));
                }
              }
            },
            icon: const Icon(Icons.save_alt),
            label: Text(l10n.saveToGallery),
          ),
        FilledButton.icon(
          key: const Key('share-result'),
          onPressed: () async {
            try {
              await SharePlus.instance.share(
                ShareParams(
                  files: [
                    XFile(
                      files.resolve(result.path).path,
                      mimeType: result.mime,
                    ),
                  ],
                ),
              );
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('$e')));
              }
            }
          },
          icon: const Icon(Icons.share_outlined),
          label: Text(l10n.resultShare),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final resultState = ref.watch(resultProvider(widget.id));
    final currentResult = resultState.value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.privateResults)),
      bottomNavigationBar: currentResult == null
          ? null
          : StickyActionBar(child: _exportActions(context, ref, currentResult)),
      body: resultState.when(
        loading: () => const LoadingBox(),
        error: (_, _) => RetryState(
          onRetry: () => ref.invalidate(resultProvider(widget.id)),
        ),
        data: (result) {
          if (result == null) {
            return EmptyState(
              icon: Icons.photo_outlined,
              title: l10n.resultEmpty,
            );
          }
          final files = ref.read(fileStoreProvider);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                jobTypeLabel(l10n, result.type),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (result.mime == 'video/mp4') ...[
                FutureBuilder<bool>(
                  future: files.resolve(result.originalPath).exists(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const LoadingBox();
                    final available =
                        snapshot.data == true &&
                        result.originalPath != result.path;
                    return Column(
                      children: [
                        if (available)
                          SegmentedButton<bool>(
                            segments: [
                              ButtonSegment(
                                value: true,
                                label: Text(l10n.resultBefore),
                              ),
                              ButtonSegment(
                                value: false,
                                label: Text(l10n.resultAfter),
                              ),
                            ],
                            selected: {_before},
                            onSelectionChanged: (v) =>
                                setState(() => _before = v.single),
                          )
                        else if (result.originalPath != result.path)
                          const Text('Saved source copy unavailable'),
                        PrivateVideo(
                          key: ValueKey(
                            available && _before
                                ? result.originalPath
                                : result.path,
                          ),
                          file: files.resolve(
                            available && _before
                                ? result.originalPath
                                : result.path,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ] else if (!result.mime.startsWith('image/')) ...[
                const Icon(Icons.inventory_2_outlined, size: 64),
                Text(l10n.privateArtifact),
                if (result.type == 'build_lora_dataset')
                  FilledButton(
                    onPressed: () =>
                        context.push('${Routes.datasets}/${result.id}'),
                    child: Text(l10n.openDataset),
                  ),
                if (result.type == 'train_lora')
                  FilledButton(
                    onPressed: () =>
                        context.push('${Routes.lora}/model/${result.id}'),
                    child: Text(l10n.openLora),
                  ),
              ] else if (result.path == result.originalPath) ...[
                PreviewImage.file(
                  files.resolve(result.path),
                  height: 400,
                  fit: BoxFit.contain,
                ),
              ] else ...[
                FutureBuilder<bool>(
                  future: files.resolve(result.originalPath).exists(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const LoadingBox();
                    if (snapshot.data != true) {
                      return Column(
                        children: [
                          PreviewImage.file(
                            files.resolve(result.path),
                            height: 400,
                            fit: BoxFit.contain,
                          ),
                          const Text('Saved source copy unavailable'),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        SizedBox(
                          height: 400,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                files.resolve(result.path),
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.broken_image_outlined),
                              ),
                              ClipRect(
                                clipper: _ComparisonClip(_comparison),
                                child: Image.file(
                                  files.resolve(result.originalPath),
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                              Align(
                                alignment: Alignment.topLeft,
                                child: Chip(label: Text(l10n.resultBefore)),
                              ),
                              Align(
                                alignment: Alignment.topRight,
                                child: Chip(label: Text(l10n.resultAfter)),
                              ),
                            ],
                          ),
                        ),
                        Slider(
                          key: const Key('result-comparison'),
                          semanticFormatterCallback: (value) =>
                              '${(value * 100).round()}%',
                          label: l10n.resultCompare,
                          value: _comparison,
                          onChanged: (v) => setState(() => _comparison = v),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              key: const Key('result-expand-before'),
                              onPressed: () => openImagePreview(
                                context,
                                ImagePreviewSource.file(
                                  files.resolve(result.originalPath),
                                ),
                              ),
                              icon: const Icon(Icons.open_in_full),
                              label: Text(l10n.resultBefore),
                            ),
                            TextButton.icon(
                              key: const Key('result-expand-after'),
                              onPressed: () => openImagePreview(
                                context,
                                ImagePreviewSource.file(
                                  files.resolve(result.path),
                                ),
                              ),
                              icon: const Icon(Icons.open_in_full),
                              label: Text(l10n.resultAfter),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
              if ((ref.watch(jobsProvider).value ?? const []).any(
                (job) => job.id == result.id,
              ))
                ListTile(
                  leading: const Icon(Icons.pending_actions_outlined),
                  title: const Text('Related job'),
                  onTap: () => context.push('${Routes.jobs}/${result.id}'),
                ),
              StreamBuilder<ArtifactContext?>(
                stream: ref
                    .read(studioRepositoryProvider)
                    .watchContext(result.id),
                builder: (context, snapshot) {
                  final relation = snapshot.data;
                  if (relation == null) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (relation.mediaId != null)
                        ListTile(
                          leading: const Icon(Icons.photo_outlined),
                          title: const Text('Source media'),
                          onTap: () => context.push(
                            '${Routes.media}/${relation.mediaId}',
                          ),
                        ),
                      if (relation.referenceMediaId != null)
                        ListTile(
                          leading: const Icon(Icons.image_outlined),
                          title: const Text('Reference photo'),
                          onTap: () => context.push(
                            '${Routes.media}/${relation.referenceMediaId}',
                          ),
                        ),
                      if (relation.personId != null)
                        ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: const Text('Source identity'),
                          onTap: () => context.push(
                            '${Routes.people}/${relation.personId}',
                          ),
                        ),
                      if (relation.targetPersonId != null)
                        ListTile(
                          leading: const Icon(Icons.person_pin_outlined),
                          title: const Text('Target person'),
                          onTap: () => context.push(
                            '${Routes.people}/${relation.targetPersonId}',
                          ),
                        ),
                      if (relation.modelId != null)
                        ListTile(
                          leading: const Icon(Icons.model_training_outlined),
                          title: const Text('Model'),
                          onTap: () => context.push(
                            '${Routes.lora}/model/${relation.modelId}',
                          ),
                        ),
                      if (relation.datasetId != null)
                        ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: const Text('Dataset'),
                          onTap: () => context.push(
                            '${Routes.datasets}/${relation.datasetId}',
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(l10n.privateResultsHint),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilterChip(
                    selected: result.favourite,
                    label: Text(l10n.resultFavourite),
                    onSelected: (_) =>
                        ref.read(studioRepositoryProvider).favourite(result),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final items = await ref
                          .read(studioRepositoryProvider)
                          .deletionItems(result);
                      if (!context.mounted) return;
                      if (!await confirm(
                        context,
                        title: l10n.resultDelete,
                        body:
                            '${l10n.resultDeleteBody}\n\n${items.map((item) => '• $item').join('\n')}',
                        confirmLabel: l10n.resultDelete,
                        cancelLabel: l10n.cancel,
                        destructive: true,
                      )) {
                        return;
                      }
                      await ref
                          .read(studioRepositoryProvider)
                          .deleteResult(result);
                      if (context.mounted) leave(context, Routes.results);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.resultDelete),
                  ),
                  TextButton(
                    onPressed: () => context.push(Routes.reface),
                    child: Text(l10n.createAnother),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ComparisonClip extends CustomClipper<Rect> {
  const _ComparisonClip(this.fraction);
  final double fraction;
  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);
  @override
  bool shouldReclip(_ComparisonClip oldClipper) =>
      oldClipper.fraction != fraction;
}

class PrivateVideo extends StatefulWidget {
  const PrivateVideo({super.key, required this.file});
  final File file;
  @override
  State<PrivateVideo> createState() => _PrivateVideoState();
}

class _PrivateVideoState extends State<PrivateVideo> {
  late final VideoPlayerController _player;
  bool _ready = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _player = VideoPlayerController.file(widget.file);
    _load();
  }

  Future<void> _load() async {
    try {
      await _player.initialize();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_error != null) return Text(_error!);
    if (!_ready) return const LoadingBox();
    return Column(
      children: [
        AspectRatio(
          aspectRatio: _player.value.aspectRatio,
          child: VideoPlayer(_player),
        ),
        VideoProgressIndicator(_player, allowScrubbing: true),
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: _player,
          builder: (context, value, _) => IconButton(
            tooltip: value.isPlaying ? l10n.videoPause : l10n.videoPlay,
            onPressed: () => value.isPlaying ? _player.pause() : _player.play(),
            icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
          ),
        ),
      ],
    );
  }
}
