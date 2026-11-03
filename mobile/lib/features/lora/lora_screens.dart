import '../shared/image_preview.dart';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/router.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/artifact_context.dart';
import '../../data/api/dtos/embedding.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../../studio_providers.dart';
import '../shared/empty_state.dart';
import '../shared/screen_layout.dart';
import '../shared/person_picker.dart';
import '../shared/crop_image.dart';
import '../studio/studio_helpers.dart';
import '../jobs/jobs_screen.dart' show jobStatusLabel;
import '../settings/background_screen.dart';

final loraPhotosPickerProvider = Provider<Future<List<File>> Function()>(
  (ref) => () async {
    final photos = await ImagePicker().pickMultiImage(
      maxWidth: 2560,
      maxHeight: 2560,
      imageQuality: 95,
      limit: 64,
    );
    return photos.map((photo) => File(photo.path)).toList();
  },
);
final loraVideoPickerProvider = Provider<Future<File?> Function()>(
  (ref) => () async {
    final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
    return file == null ? null : File(file.path);
  },
);

/// Mean only vectors from one explicitly selected embedding space.
String datasetIdentityAnchor(List<FaceRow> faces, String modelId) {
  final dimension = switch (modelId) {
    'buffalo_l@1' => embeddingDim,
    characterEmbeddingModelId => characterEmbeddingDim,
    _ => throw const FormatException(
      'This identity model is not supported for datasets.',
    ),
  };
  final selected = faces
      .where((face) => face.modelId == modelId)
      .take(40)
      .toList();
  if (selected.isEmpty) {
    throw const FormatException(
      'This identity has no compatible analyzed faces.',
    );
  }
  final mean = Float32List(dimension);
  for (final face in selected) {
    final vector = vectorFromBlob(face.embedding);
    if (vector.length != dimension ||
        vector.any((v) => !v.isFinite) ||
        !face.qualityScore.isFinite) {
      throw const FormatException(
        'A source face has an invalid identity embedding.',
      );
    }
    for (var index = 0; index < dimension; index++) {
      mean[index] += vector[index] * math.max(face.qualityScore, .001);
    }
  }
  final norm = math.sqrt(
    mean.fold<double>(0, (sum, value) => sum + value * value),
  );
  if (!norm.isFinite || norm < 1e-8) {
    throw const FormatException(
      'The source identity has no usable embeddings.',
    );
  }
  for (var index = 0; index < dimension; index++) {
    mean[index] /= norm;
  }
  return encodeVector(mean);
}

class LoraScreen extends ConsumerWidget {
  const LoraScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final datasetState = ref.watch(datasetsProvider);
    final modelState = ref.watch(lorasProvider);
    final trainingState = ref.watch(jobsProvider);
    final datasets = datasetState.value ?? const <DatasetRow>[];
    final models = modelState.value ?? const <LoraRow>[];
    final people = [
      ...ref.watch(peopleProvider).value ?? const [],
      ...ref.watch(charactersProvider).value ?? const [],
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l.loraTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ScreenIntro(title: l.studioLoraAction, body: l.studioLoraDescription),
          FilledButton.icon(
            key: const Key('lora-build'),
            onPressed: () async {
              final chosen = await pickPerson(
                context,
                allowNew: false,
                kind: 'all',
              );
              if (chosen?.personId != null && context.mounted) {
                final people = [
                  ...ref.read(peopleProvider).value ?? const [],
                  ...ref.read(charactersProvider).value ?? const [],
                ];
                final name = people
                    .where((p) => p.id == chosen!.personId)
                    .firstOrNull
                    ?.name;
                context.push(
                  '${Routes.studioCuration}/${chosen!.personId}?name=${Uri.encodeComponent(name ?? 'person')}',
                );
              } else if (context.mounted) {
                context.push(Routes.loraBuild);
              }
            },
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(l.loraDatasetBuild),
          ),
          const SizedBox(height: 24),
          Text(
            l.loraDatasetTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (datasetState.isLoading) const LoadingBox(),
          if (datasetState.hasError)
            RetryState(onRetry: () => ref.invalidate(datasetsProvider)),
          if (!datasetState.isLoading &&
              !datasetState.hasError &&
              datasets.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l.loraNoDatasets),
            ),
          for (final dataset in datasets)
            Card(
              child: ListTile(
                title: Text(dataset.triggerWord),
                subtitle: StreamBuilder<List<DatasetItemRow>>(
                  stream: ref
                      .read(loraRepositoryProvider)
                      .watchItems(dataset.id),
                  builder: (context, snapshot) {
                    final owner = people
                        .where((p) => p.id == dataset.personId)
                        .firstOrNull;
                    final count = snapshot.data?.length;
                    return Text(
                      '${owner == null ? 'No person assigned' : personName(l, owner)} · ${count == null ? 'Loading images' : '$count images'}',
                    );
                  },
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('${Routes.datasets}/${dataset.id}'),
              ),
            ),
          const SizedBox(height: 24),
          Text(l.loraModel, style: Theme.of(context).textTheme.titleLarge),
          if (modelState.isLoading) const LoadingBox(),
          if (modelState.hasError)
            RetryState(onRetry: () => ref.invalidate(lorasProvider)),
          if (!modelState.isLoading && !modelState.hasError && models.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l.loraNoModels),
            ),
          for (final model in models) _ModelRow(model: model),
          const SizedBox(height: 24),
          Text('Training tasks', style: Theme.of(context).textTheme.titleLarge),
          if (trainingState.isLoading) const LoadingBox(),
          if (trainingState.hasError)
            RetryState(onRetry: () => ref.invalidate(jobsProvider)),
          for (final job in trainingState.value ?? const [])
            if (job.type == 'train_lora' && job.status != 'completed')
              ListTile(
                leading: const Icon(Icons.pending_actions_outlined),
                title: Text(jobStatusLabel(l, job.status)),
                subtitle: Text(job.message ?? ''),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('${Routes.jobs}/${job.id}'),
              ),
        ],
      ),
    );
  }
}

class _ModelRow extends ConsumerWidget {
  const _ModelRow({required this.model});
  final LoraRow model;
  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<bool>(
    future: ref.read(fileStoreProvider).resolve(model.path).exists(),
    builder: (context, snapshot) => ListTile(
      leading: const Icon(Icons.model_training_outlined),
      title: Text(model.triggerWord),
      subtitle: Text(
        snapshot.connectionState == ConnectionState.done
            ? (snapshot.data == true
                  ? 'Ready on this phone'
                  : 'File unavailable')
            : 'Checking file',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('${Routes.lora}/model/${model.id}'),
    ),
  );
}

class ModelDetailScreen extends ConsumerWidget {
  const ModelDetailScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lorasProvider);
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Model details')),
      body: state.when(
        loading: () => const LoadingBox(),
        error: (_, _) =>
            RetryState(onRetry: () => ref.invalidate(lorasProvider)),
        data: (models) {
          final model = models.where((m) => m.id == id).firstOrNull;
          if (model == null) {
            return const Center(child: Text('Model unavailable'));
          }
          return FutureBuilder<bool>(
            future: ref.read(fileStoreProvider).resolve(model.path).exists(),
            builder: (context, snapshot) {
              final ready = snapshot.data == true;
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    model.triggerWord,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.connectionState == ConnectionState.done
                        ? (ready ? 'Ready on this phone' : 'File unavailable')
                        : 'Checking file',
                  ),
                  if (model.personId != null)
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: const Text('Person'),
                      onTap: () =>
                          context.push('${Routes.people}/${model.personId}'),
                    ),
                  StreamBuilder<ArtifactContext?>(
                    stream: ref
                        .read(studioRepositoryProvider)
                        .watchContext(model.id),
                    builder: (context, snapshot) {
                      final relation = snapshot.data;
                      if (relation?.datasetId == null) {
                        return const SizedBox.shrink();
                      }
                      return ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: const Text('Source dataset'),
                        onTap: () => context.push(
                          '${Routes.datasets}/${relation!.datasetId}',
                        ),
                      );
                    },
                  ),
                  if ((ref.watch(jobsProvider).value ?? const []).any(
                    (job) => job.id == model.id,
                  ))
                    ListTile(
                      leading: const Icon(Icons.pending_actions_outlined),
                      title: const Text('Training job'),
                      onTap: () => context.push('${Routes.jobs}/${model.id}'),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Generated results',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final result
                      in ref.watch(resultsProvider).value ?? const [])
                    FutureBuilder<ArtifactContext?>(
                      future: ref
                          .read(studioRepositoryProvider)
                          .contextFor(result.id),
                      builder: (context, snapshot) =>
                          snapshot.data?.modelId == model.id
                          ? ListTile(
                              leading: const Icon(Icons.photo_outlined),
                              title: const Text('Generated result'),
                              onTap: () => context.push(
                                '${Routes.results}/${result.id}',
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: ready
                        ? () => context.push(
                            '${Routes.loraGenerate}?id=${model.id}',
                          )
                        : null,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: Text(l.loraGenerate),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: ready
                        ? () async {
                            try {
                              await SharePlus.instance.share(
                                ShareParams(
                                  files: [
                                    XFile(
                                      ref
                                          .read(fileStoreProvider)
                                          .resolve(model.path)
                                          .path,
                                    ),
                                  ],
                                ),
                              );
                            } catch (error) {
                              if (context.mounted) studioError(context, error);
                            }
                          }
                        : null,
                    icon: const Icon(Icons.share_outlined),
                    label: Text(l.resultShare),
                  ),
                  TextButton(
                    onPressed: ready
                        ? () async {
                            try {
                              final api = ref.read(mobileApiProvider);
                              if (api == null) {
                                if (context.mounted) {
                                  context.push(Routes.connection);
                                }
                                return;
                              }
                              await ref
                                  .read(loraRepositoryProvider)
                                  .buildIdentity(model, api);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(l.loraIdentityReady)),
                                );
                              }
                            } catch (error) {
                              if (context.mounted) studioError(context, error);
                            }
                          }
                        : null,
                    child: Text(l.loraBuildIdentity),
                  ),
                  Text(l.loraIdentityHint),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class DatasetBuildScreen extends ConsumerStatefulWidget {
  const DatasetBuildScreen({super.key, this.personId, this.mediaId});
  final int? personId;
  final int? mediaId;
  @override
  ConsumerState<DatasetBuildScreen> createState() => _DatasetBuildScreenState();
}

class _DatasetBuildScreenState extends ConsumerState<DatasetBuildScreen> {
  final _trigger = TextEditingController(text: 'skscharacter');
  int? _person;
  String? _name;
  List<File> _photos = [];
  File? _contextPhoto;
  int? _contextMediaId;
  String? _contextAssetId;
  bool _busy = false;
  String? _error;
  int _repeats = 20;
  @override
  void initState() {
    super.initState();
    _person = widget.personId;
    if (_person != null) _trigger.text = 'sks$_person';
    if (widget.mediaId != null) Future<void>.microtask(_loadContextMedia);
  }

  Future<void> _loadContextMedia() async {
    if (mounted) setState(() => _busy = true);
    try {
      final source = await ref
          .read(mediaActionSourceProvider)
          .resolve(widget.mediaId!);
      if (source.isVideo) {
        throw const FormatException('Choose photos for this dataset.');
      }
      final file = await privatePickedPhoto(ref, source.photoBytes!);
      if (!mounted) {
        await file.delete();
        return;
      }
      setState(() {
        _contextMediaId = source.media.id;
        _contextAssetId = source.media.assetId;
        _contextPhoto = file;
        _photos = [file, ..._photos];
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _trigger.dispose();
    _contextPhoto?.delete().ignore();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final caps = studioCapabilities(ref.read(serverStatusProvider).value);
    if (caps == null ||
        _person == null ||
        _photos.length < 5 ||
        !RegExp(
          r'^[A-Za-z][A-Za-z0-9_]{2,63}$',
        ).hasMatch(_trigger.text.trim())) {
      setState(() => _error = l.invalidForm);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var total = 0;
      for (final file in _photos) {
        final size = await file.length();
        if (size > caps.limits.maxUploadMb * 1024 * 1024) {
          throw FormatException(l.fileTooLarge);
        }
        total += size;
      }
      if (total > caps.limits.blobCacheMb * 1024 * 1024) {
        throw FormatException(l.fileTooLarge);
      }
      final faces = await ref
          .read(studioRepositoryProvider)
          .sourceFaces(_person!);
      final db = ref.read(databaseProvider);
      final person = await (db.select(
        db.persons,
      )..where((row) => row.id.equals(_person!))).getSingleOrNull();
      if (person == null) {
        throw const FormatException('The selected identity no longer exists.');
      }
      final character = person.kind == 'character';
      final identityModel = character
          ? characterEmbeddingModelId
          : 'buffalo_l@1';
      if ((character || caps.hasOperationSupport) &&
          !caps.supportsOperation(
            'dataset_build',
            person.kind,
            identityModelId: identityModel,
          )) {
        throw FormatException(
          character && !caps.hasOperationSupport
              ? 'This PC does not report character dataset support. Update the PC server and reconnect.'
              : 'This PC cannot build a dataset for the selected identity model.',
        );
      }
      final anchor = datasetIdentityAnchor(faces, identityModel);
      if (!mounted) return;
      await prepareBackgroundForWork(context, ref);
      if (!mounted) return;
      final id = await ref
          .read(studioRepositoryProvider)
          .enqueueInputs(
            serverId: caps.serverId,
            type: 'build_lora_dataset',
            context: ArtifactContext(
              personId: _person,
              identityModelId: identityModel,
              mediaId: _contextPhoto != null && _photos.contains(_contextPhoto)
                  ? _contextMediaId
                  : null,
              assetId: _contextPhoto != null && _photos.contains(_contextPhoto)
                  ? _contextAssetId
                  : null,
            ),
            params: {
              'trigger_word': _trigger.text.trim(),
              'repeats': _repeats,
              'anchor_embedding': anchor,
              if (caps.hasOperationSupport) 'identity_model_id': identityModel,
            },
            inputs: {'images': _photos},
            personId: _person,
          );
      ref.read(jobTrackerProvider).start();
      if (mounted) context.pushReplacement('${Routes.jobs}/$id');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    ref.watch(serverStatusProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.loraDatasetBuild)),
      bottomNavigationBar: StickyActionBar(
        child: FilledButton(
          key: const Key('dataset-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(l.loraDatasetBuild),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ScreenIntro(title: l.loraDatasetTitle, body: l.loraPhotoHint),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'التحديد التلقائي الذكي للصور ⚡',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'اختر شخصاً وسيقوم النظام تلقائياً بانتقاء وتصنيف أفضل 20 صورة وفيديو تدريبية بدقة تشريحية عالية.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    key: const Key('dataset-auto-select'),
                    icon: const Icon(Icons.bolt, size: 18),
                    label: const Text('اختيار شخص وبدء التحديد التلقائي'),
                    onPressed: _busy
                        ? null
                        : () async {
                            final chosen = await pickPerson(
                              context,
                              allowNew: false,
                              kind: 'all',
                            );
                            if (!mounted) return;
                            if (chosen?.personId != null) {
                              final people = [
                                ...ref.read(peopleProvider).value ?? const [],
                                ...ref.read(charactersProvider).value ?? const [],
                              ];
                              final name = people
                                  .where((p) => p.id == chosen!.personId)
                                  .firstOrNull
                                  ?.name;
                              if (!context.mounted) return;
                              context.pushReplacement(
                                '${Routes.studioCuration}/${chosen!.personId}?name=${Uri.encodeComponent(name ?? 'person')}',
                              );
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_busy) const LinearProgressIndicator(),
          OutlinedButton(
            key: const Key('dataset-person'),
            onPressed: _busy
                ? null
                : () async {
                    final chosen = await pickPerson(
                      context,
                      allowNew: false,
                      kind: 'all',
                    );
                    if (!context.mounted) return;
                    if (chosen?.personId != null) {
                      final people = [
                        ...ref.read(peopleProvider).value ?? const [],
                        ...ref.read(charactersProvider).value ?? const [],
                      ];
                      final name = people
                          .where((p) => p.id == chosen!.personId)
                          .firstOrNull
                          ?.name;
                      if (!context.mounted) return;
                      context.pushReplacement(
                        '${Routes.studioCuration}/${chosen!.personId}?name=${Uri.encodeComponent(name ?? 'person')}',
                      );
                    }
                  },
            child: Text(
              _name ??
                  [
                    ...ref.watch(peopleProvider).value ?? const [],
                    ...ref.watch(charactersProvider).value ?? const [],
                  ].where((p) => p.id == _person).firstOrNull?.name ??
                  l.selectSourcePerson,
            ),
          ),
          TextField(
            controller: _trigger,
            maxLength: 64,
            decoration: InputDecoration(
              labelText: l.loraTrigger,
              helperText: l.loraTriggerHint,
            ),
          ),
          OutlinedButton(
            key: const Key('dataset-photos'),
            onPressed: _busy
                ? null
                : () async {
                    try {
                      final photos = await ref.read(loraPhotosPickerProvider)();
                      if (photos.isNotEmpty && mounted) {
                        setState(() => _photos = photos.take(64).toList());
                      }
                    } catch (e) {
                      if (context.mounted) {
                        studioError(context, e);
                      }
                    }
                  },
            child: Text('${l.loraChoosePhotos} (${_photos.length})'),
          ),
          OutlinedButton(
            onPressed: _busy || _photos.length >= 64
                ? null
                : () async {
                    try {
                      final file = await ref.read(loraVideoPickerProvider)();
                      if (file != null && mounted) {
                        setState(() => _photos.add(file));
                      }
                    } catch (e) {
                      if (context.mounted) studioError(context, e);
                    }
                  },
            child: Text(l.chooseTargetVideo),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final file in _photos)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child:
                            [
                              '.mp4',
                              '.mov',
                              '.mkv',
                              '.webm',
                              '.avi',
                              '.m4v',
                              '.3gp',
                              '.ts',
                              '.mts',
                              '.m2ts',
                            ].any(
                              (extension) =>
                                  file.path.toLowerCase().endsWith(extension),
                            )
                            ? ColoredBox(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainer,
                                child: const Icon(Icons.play_circle_outline),
                              )
                            : PreviewImage.file(
                                file,
                                fit: BoxFit.cover,
                                cacheWidth: 144,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.broken_image_outlined),
                              ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove input',
                      onPressed: _busy
                          ? null
                          : () => setState(() => _photos.remove(file)),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
            ],
          ),
          Text('${l.loraRepeats}: $_repeats'),
          Slider(
            value: _repeats.toDouble(),
            min: 1,
            max: 50,
            divisions: 49,
            onChanged: _busy
                ? null
                : (v) => setState(() => _repeats = v.round()),
          ),
        ],
      ),
    );
  }
}

class DatasetScreen extends ConsumerWidget {
  const DatasetScreen({super.key, required this.id});
  final String id;
  Widget _actions(
    BuildContext context,
    WidgetRef ref,
    List<DatasetItemRow> items,
  ) {
    final l = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton(
          onPressed: items.where((i) => i.included).length < 5
              ? null
              : () => context.push('${Routes.loraTrain}?dataset=$id'),
          child: Text(l.loraTrain),
        ),
        OutlinedButton(
          onPressed: () async {
            try {
              final zip = await ref
                  .read(loraRepositoryProvider)
                  .exportDataset(id);
              await SharePlus.instance.share(
                ShareParams(files: [XFile(zip.path)]),
              );
            } catch (e) {
              if (context.mounted) {
                studioError(context, e);
              }
            }
          },
          child: Text(l.loraExport),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final itemState = ref.watch(datasetItemsProvider(id));
    final currentItems = itemState.value;
    return Scaffold(
      appBar: AppBar(title: Text(l.loraDatasetEditor)),
      bottomNavigationBar: currentItems != null && currentItems.isNotEmpty
          ? StickyActionBar(child: _actions(context, ref, currentItems))
          : null,
      body: itemState.when(
        loading: () => const LoadingBox(),
        error: (_, _) =>
            RetryState(onRetry: () => ref.invalidate(datasetItemsProvider(id))),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.photo_library_outlined,
              title: l.loraNoDatasets,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ScreenIntro(
                title: l.datasetEditorIntro,
                body: l.datasetEditorHint,
              ),
              SurfaceSection(
                child: Text(
                  '${items.where((i) => i.included).length}/${items.length} · ${l.loraIncluded}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 16),
              for (final item in items)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            PreviewImage.file(
                              ref.read(fileStoreProvider).resolve(item.path),
                              width: 112,
                              height: 112,
                              fit: BoxFit.cover,
                              cacheWidth: 224,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(l.loraIncluded),
                                value: item.included,
                                onChanged: (v) => ref
                                    .read(loraRepositoryProvider)
                                    .updateItem(item, included: v),
                              ),
                            ),
                          ],
                        ),
                        TextButton(
                          onPressed: () async {
                            var caption = item.caption;
                            final saved = await showDialog<String>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text(l.loraCaption),
                                content: TextFormField(
                                  initialValue: caption,
                                  maxLines: 6,
                                  maxLength: 8192,
                                  onChanged: (v) => caption = v,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: Text(l.cancel),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, caption),
                                    child: Text(l.save),
                                  ),
                                ],
                              ),
                            );
                            if (saved != null && saved.trim().isNotEmpty) {
                              await ref
                                  .read(loraRepositoryProvider)
                                  .updateItem(item, caption: saved.trim());
                            }
                          },
                          child: Text(
                            item.caption,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.start,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class LoraTrainScreen extends ConsumerStatefulWidget {
  const LoraTrainScreen({super.key, this.datasetId});
  final String? datasetId;
  @override
  ConsumerState<LoraTrainScreen> createState() => _LoraTrainScreenState();
}

class _LoraTrainScreenState extends ConsumerState<LoraTrainScreen> {
  String? _dataset, _base;
  int _epochs = 10, _dim = 32, _resolution = 512;
  final _lr = TextEditingController(text: '0.0001');
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _dataset = widget.datasetId;
  }

  @override
  void dispose() {
    _lr.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final caps = studioCapabilities(ref.read(serverStatusProvider).value);
    final lr = double.tryParse(_lr.text.trim());
    if (caps == null ||
        _dataset == null ||
        _base == null ||
        lr == null ||
        !lr.isFinite ||
        lr < .000001 ||
        lr > .001) {
      setState(() => _error = l.invalidForm);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    File? zip;
    try {
      await prepareBackgroundForWork(context, ref);
      if (!mounted) return;
      final items = await ref
          .read(loraRepositoryProvider)
          .watchItems(_dataset!)
          .first;
      if (items.where((i) => i.included).length < 5) {
        throw FormatException(l.loraMinImages);
      }
      final dataset = await ref.read(loraRepositoryProvider).dataset(_dataset!);
      if (dataset == null) return;
      final identityModel = await ref
          .read(studioRepositoryProvider)
          .identityModelForDataset(dataset.id);
      if (identityModel != null &&
          identityModel != 'buffalo_l@1' &&
          identityModel != characterEmbeddingModelId) {
        throw const FormatException(
          'This dataset has an unsupported identity model.',
        );
      }
      if (identityModel != null &&
          caps.hasOperationSupport &&
          !caps.supportsOperation(
            'lora_train',
            identityModel == characterEmbeddingModelId ? 'character' : 'person',
            identityModelId: identityModel,
          )) {
        throw const FormatException(
          'This PC cannot train a dataset with this identity model.',
        );
      }
      zip = await ref.read(loraRepositoryProvider).exportDataset(_dataset!);
      final id = await ref
          .read(studioRepositoryProvider)
          .enqueueInputs(
            serverId: caps.serverId,
            type: 'train_lora',
            context: ArtifactContext(
              personId: dataset.personId,
              datasetId: dataset.id,
              identityModelId: identityModel,
            ),
            params: {
              'trigger_word': dataset.triggerWord,
              'output_name': 'character',
              'base_checkpoint': _base,
              'epochs': _epochs,
              'network_dim': _dim,
              'network_alpha': _dim ~/ 2,
              'learning_rate': lr,
              'max_resolution': _resolution,
              'batch_size': 1,
              if (identityModel != null && caps.hasOperationSupport)
                'identity_model_id': identityModel,
            },
            inputs: {
              'dataset': [zip],
            },
            personId: dataset.personId,
          );
      ref.read(jobTrackerProvider).start();
      if (mounted) context.pushReplacement('${Routes.jobs}/$id');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (zip != null && await zip.exists()) await zip.delete();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final caps = studioCapabilities(ref.watch(serverStatusProvider).value);
    final datasets = ref.watch(datasetsProvider).value ?? const <DatasetRow>[];
    if (!datasets.any((d) => d.id == _dataset)) {
      _dataset = datasets.firstOrNull?.id;
    }
    final bases = caps?.loraBaseCheckpoints ?? const <String>[];
    if (!bases.contains(_base)) _base = bases.firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(l.loraTrain)),
      bottomNavigationBar: StickyActionBar(
        child: FilledButton(
          key: const Key('train-submit'),
          onPressed:
              _busy ||
                  _dataset == null ||
                  _base == null ||
                  caps?.engines.loraTrain != true
              ? null
              : _submit,
          child: Text(l.loraTrain),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ScreenIntro(title: l.loraTrainHeadline, body: l.loraTrainHint),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (caps?.engines.loraTrain != true) Text(l.engineUnavailable),
          if (datasets.isEmpty)
            Text(l.loraNoDatasets)
          else
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: ValueKey('train-dataset-$_dataset'),
              initialValue: _dataset,
              decoration: InputDecoration(labelText: l.loraChooseDataset),
              items: [
                for (final d in datasets)
                  DropdownMenuItem(value: d.id, child: Text(d.triggerWord)),
              ],
              onChanged: (v) => setState(() => _dataset = v),
            ),
          if (bases.isEmpty)
            Text(l.loraNoBase)
          else
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: ValueKey('train-base-$_base'),
              initialValue: _base,
              decoration: InputDecoration(labelText: l.loraBase),
              items: [
                for (final b in bases)
                  DropdownMenuItem(value: b, child: Text(b)),
              ],
              onChanged: (v) => setState(() => _base = v),
            ),
          Text('${l.loraEpochs}: $_epochs'),
          Slider(
            value: _epochs.toDouble(),
            min: 1,
            max: 50,
            divisions: 49,
            onChanged: (v) => setState(() => _epochs = v.round()),
          ),
          ExpansionTile(
            key: const Key('train-advanced'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 16),
            title: Text(l.advancedOptions),
            children: [
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: _dim,
                decoration: InputDecoration(labelText: l.loraDim),
                items: [
                  for (final d in [4, 8, 16, 32, 64, 128])
                    DropdownMenuItem(value: d, child: Text('$d')),
                ],
                onChanged: (v) => setState(() => _dim = v!),
              ),
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: _resolution,
                decoration: InputDecoration(labelText: l.loraResolution),
                items: [
                  for (final r in [512, 768])
                    DropdownMenuItem(value: r, child: Text('$r')),
                ],
                onChanged: (v) => setState(() => _resolution = v!),
              ),
              TextField(
                controller: _lr,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: l.loraLearningRate),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class LoraGenerateScreen extends ConsumerStatefulWidget {
  const LoraGenerateScreen({super.key, this.loraId, this.referenceMediaId});
  final String? loraId;
  final int? referenceMediaId;
  @override
  ConsumerState<LoraGenerateScreen> createState() => _LoraGenerateScreenState();
}

class _LoraGenerateScreenState extends ConsumerState<LoraGenerateScreen> {
  String? _model, _base, _error;
  final _prompt = TextEditingController(),
      _seed = TextEditingController(text: '-1');
  int _count = 4;
  String _referenceMode = 'composition';
  File? _reference;
  int? _referenceMediaId;
  bool _busy = false, _initialized = false, _promptEdited = false;
  bool _loadingModelPrompt = false;
  bool _modelContextError = false;
  @override
  void initState() {
    super.initState();
    _model = widget.loraId;
    _loadingModelPrompt = _model != null;
    if (widget.referenceMediaId != null) {
      Future<void>.microtask(_loadContextReference);
    }
  }

  Future<void> _loadContextReference() async {
    if (mounted) setState(() => _busy = true);
    try {
      final source = await ref
          .read(mediaActionSourceProvider)
          .resolve(widget.referenceMediaId!);
      if (source.isVideo) {
        throw const FormatException('Choose a photo as a reference.');
      }
      final file = await privatePickedPhoto(ref, source.photoBytes!);
      if (!mounted) {
        await file.delete();
        return;
      }
      setState(() {
        _reference = file;
        _referenceMediaId = source.media.id;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _prompt.text = AppLocalizations.of(
        context,
      ).loraDefaultPrompt('{trigger}');
      _initialized = true;
      final selected = _model;
      if (selected != null) {
        Future<void>.microtask(() => _setDefaultPrompt(selected));
      }
    }
  }

  Future<void> _setDefaultPrompt(String modelId) async {
    if (mounted) {
      setState(() {
        _loadingModelPrompt = true;
        _modelContextError = false;
      });
    }
    try {
      final identity = await ref
          .read(studioRepositoryProvider)
          .identityModelForLora(modelId);
      if (!mounted || _model != modelId) return;
      if (!_promptEdited) {
        _prompt.text = identity == characterEmbeddingModelId
            ? 'Illustrated portrait of {trigger}, fully clothed, neutral expression, soft lighting'
            : AppLocalizations.of(context).loraDefaultPrompt('{trigger}');
      }
      setState(() => _loadingModelPrompt = false);
    } on Object {
      if (mounted && _model == modelId) {
        setState(() {
          _loadingModelPrompt = false;
          _modelContextError = true;
          _error =
              'Could not load the model context. Select the model again to retry.';
        });
      }
    }
  }

  @override
  void dispose() {
    _prompt.dispose();
    _seed.dispose();
    final reference = _reference;
    if (reference != null) reference.delete().catchError((_) => reference);
    super.dispose();
  }

  Future<void> _submit(LoraRow model) async {
    final l = AppLocalizations.of(context);
    final caps = studioCapabilities(ref.read(serverStatusProvider).value);
    if (!await ref.read(fileStoreProvider).resolve(model.path).exists()) {
      if (mounted) setState(() => _error = 'Model file unavailable');
      return;
    }
    if (!mounted) return;
    final seed = int.tryParse(_seed.text.trim());
    if (caps == null ||
        _base == null ||
        seed == null ||
        seed < -1 ||
        seed > 2147483647 ||
        _prompt.text.trim().isEmpty) {
      setState(() => _error = l.invalidForm);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await prepareBackgroundForWork(context, ref);
      if (!mounted) return;
      final identityModel = await ref
          .read(studioRepositoryProvider)
          .identityModelForLora(model.id);
      if (identityModel != null &&
          identityModel != 'buffalo_l@1' &&
          identityModel != characterEmbeddingModelId) {
        throw const FormatException(
          'This model has an unsupported identity model.',
        );
      }
      if (identityModel == characterEmbeddingModelId &&
          !caps.hasOperationSupport) {
        throw const FormatException(
          'This PC does not report character generation support. Update the PC server and reconnect.',
        );
      }
      if (identityModel != null &&
          caps.hasOperationSupport &&
          !caps.supportsOperation(
            'lora_generate',
            identityModel == characterEmbeddingModelId ? 'character' : 'person',
            identityModelId: identityModel,
          )) {
        throw const FormatException(
          'This PC cannot generate with this identity model.',
        );
      }
      final id = await ref
          .read(studioRepositoryProvider)
          .enqueueInputs(
            serverId: caps.serverId,
            type: 'generate_lora_images',
            context: ArtifactContext(
              personId: model.personId,
              modelId: model.id,
              referenceMediaId: _referenceMediaId,
              identityModelId: identityModel,
            ),
            params: {
              'trigger_word': model.triggerWord,
              'base_checkpoint': _base,
              'prompt': _prompt.text.trim().replaceAll(
                '{trigger}',
                model.triggerWord,
              ),
              'num_images': _count,
              'seed': seed,
              'steps': 30,
              'reference_mode': _referenceMode,
              'multi_angle': true,
              if (identityModel != null && caps.hasOperationSupport)
                'identity_model_id': identityModel,
            },
            inputs: {
              'lora': [ref.read(fileStoreProvider).resolve(model.path)],
              if (_reference != null) 'reference': [_reference!],
            },
            personId: model.personId,
          );
      ref.read(jobTrackerProvider).start();
      if (mounted) context.pushReplacement('${Routes.jobs}/$id');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final caps = studioCapabilities(ref.watch(serverStatusProvider).value);
    final modelState = ref.watch(lorasProvider);
    final models = modelState.value ?? const <LoraRow>[];
    if (modelState.hasValue &&
        _model != null &&
        !models.any((m) => m.id == _model)) {
      _model = null;
    }
    final selected = models.where((m) => m.id == _model).firstOrNull;
    final bases = caps?.loraBaseCheckpoints ?? const <String>[];
    if (!bases.contains(_base)) _base = bases.firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(l.loraGenerate)),
      bottomNavigationBar: StickyActionBar(
        child: FutureBuilder<bool>(
          future: selected == null
              ? Future.value(false)
              : ref.read(fileStoreProvider).resolve(selected.path).exists(),
          builder: (context, snapshot) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (selected != null &&
                  snapshot.connectionState == ConnectionState.done &&
                  snapshot.data != true)
                const Text('Model file unavailable'),
              FilledButton(
                key: const Key('generate-submit'),
                onPressed:
                    _busy ||
                        _loadingModelPrompt ||
                        _modelContextError ||
                        selected == null ||
                        _base == null ||
                        caps?.engines.loraGenerate != true ||
                        snapshot.data != true
                    ? null
                    : () => _submit(selected),
                child: Text(l.loraGenerate),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ScreenIntro(title: l.loraGenerateHeadline),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (caps?.engines.loraGenerate != true) Text(l.engineUnavailable),
          if (models.isEmpty)
            Text(l.loraNoModels)
          else
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: ValueKey('generate-model-$_model'),
              initialValue: _model,
              decoration: InputDecoration(
                labelText: l.loraModel,
                hintText: 'Select a model',
              ),
              items: [
                for (final m in models)
                  DropdownMenuItem(value: m.id, child: Text(m.triggerWord)),
              ],
              onChanged: (v) {
                setState(() => _model = v);
                if (v != null) _setDefaultPrompt(v);
              },
            ),
          if (bases.isEmpty)
            Text(l.loraNoBase)
          else
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: ValueKey('generate-base-$_base'),
              initialValue: _base,
              decoration: InputDecoration(labelText: l.loraBase),
              items: [
                for (final b in bases)
                  DropdownMenuItem(value: b, child: Text(b)),
              ],
              onChanged: (v) => setState(() => _base = v),
            ),
          TextField(
            controller: _prompt,
            onChanged: (_) => _promptEdited = true,
            minLines: 3,
            maxLines: 6,
            maxLength: 4000,
            decoration: InputDecoration(labelText: l.loraPrompt),
          ),
          Text('${l.loraCount}: $_count'),
          Slider(
            value: _count.toDouble(),
            min: 1,
            max: 16,
            divisions: 15,
            onChanged: (v) => setState(() => _count = v.round()),
          ),
          TextField(
            controller: _seed,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            decoration: InputDecoration(labelText: l.seed),
          ),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () async {
                    try {
                      final bytes = await ref
                          .read(photoPickerProvider)
                          .pickPhoto();
                      if (bytes != null) {
                        final file = await privatePickedPhoto(ref, bytes);
                        if (mounted) {
                          final previous = _reference;
                          setState(() {
                            _reference = file;
                            _referenceMediaId = null;
                          });
                          previous?.delete().ignore();
                        } else {
                          await file.delete();
                        }
                      }
                    } catch (e) {
                      if (context.mounted) {
                        studioError(context, e);
                      }
                    }
                  },
            child: Text(l.addReference),
          ),
          if (_reference != null) ...[
            PreviewImage.file(_reference!, height: 160, cacheWidth: 320),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _referenceMode,
              decoration: InputDecoration(labelText: l.loraReferenceMode),
              items: [
                DropdownMenuItem(
                  value: 'composition',
                  child: Text(l.referenceComposition),
                ),
                DropdownMenuItem(value: 'style', child: Text(l.referenceStyle)),
                DropdownMenuItem(value: 'both', child: Text(l.referenceBoth)),
              ],
              onChanged: (v) => setState(() => _referenceMode = v!),
            ),
          ],
          const SizedBox(height: 16),
          Text(l.privateResultsHint),
        ],
      ),
    );
  }
}
