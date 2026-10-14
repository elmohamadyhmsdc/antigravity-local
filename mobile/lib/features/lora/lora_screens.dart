import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/router.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/lora_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../../studio_providers.dart';
import '../shared/empty_state.dart';
import '../shared/person_picker.dart';
import '../studio/studio_helpers.dart';
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

class LoraScreen extends ConsumerWidget {
  const LoraScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final datasets = ref.watch(datasetsProvider).value ?? const <DatasetRow>[];
    final models = ref.watch(lorasProvider).value ?? const <LoraRow>[];
    return Scaffold(
      appBar: AppBar(title: Text(l.loraTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l.loraHint, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('lora-build'),
            onPressed: () => context.push(Routes.loraBuild),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(l.loraDatasetBuild),
          ),
          const SizedBox(height: 24),
          Text(
            l.loraDatasetTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (datasets.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l.loraNoDatasets),
            ),
          for (final dataset in datasets)
            Card(
              child: ListTile(
                title: Text(dataset.triggerWord),
                subtitle: Text(l.loraDatasetEditor),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('${Routes.datasets}/${dataset.id}'),
              ),
            ),
          const SizedBox(height: 24),
          Text(l.loraModel, style: Theme.of(context).textTheme.titleLarge),
          if (models.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l.loraNoModels),
            ),
          for (final model in models)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.triggerWord,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: () => context.push(
                            '${Routes.loraGenerate}?id=${model.id}',
                          ),
                          child: Text(l.loraGenerate),
                        ),
                        OutlinedButton(
                          onPressed: () async {
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
                            } catch (e) {
                              if (context.mounted) {
                                studioError(context, e);
                              }
                            }
                          },
                          child: Text(l.resultShare),
                        ),
                        TextButton(
                          onPressed: () async {
                            try {
                              final api = ref.read(mobileApiProvider);
                              if (api == null) return;
                              await ref
                                  .read(loraRepositoryProvider)
                                  .buildIdentity(model, api);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(l.loraIdentityReady)),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                studioError(context, e);
                              }
                            }
                          },
                          child: Text(l.loraBuildIdentity),
                        ),
                      ],
                    ),
                    Text(l.loraIdentityHint),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DatasetBuildScreen extends ConsumerStatefulWidget {
  const DatasetBuildScreen({super.key});
  @override
  ConsumerState<DatasetBuildScreen> createState() => _DatasetBuildScreenState();
}

class _DatasetBuildScreenState extends ConsumerState<DatasetBuildScreen> {
  final _trigger = TextEditingController(text: 'skscharacter');
  int? _person;
  String? _name;
  List<File> _photos = [];
  bool _busy = false;
  String? _error;
  int _repeats = 20;
  @override
  void dispose() {
    _trigger.dispose();
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
      await prepareBackgroundForWork(context, ref);
      if (!mounted) return;
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
      if (faces.any((face) => face.modelId != caps.embeddingModelId)) {
        throw FormatException(l.selectIdentityRequired);
      }
      final id = await ref
          .read(studioRepositoryProvider)
          .enqueueInputs(
            serverId: caps.serverId,
            type: 'build_lora_dataset',
            params: {
              'trigger_word': _trigger.text.trim(),
              'repeats': _repeats,
              'anchor_embedding': LoraRepository.anchor(faces),
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
    return Scaffold(
      appBar: AppBar(title: Text(l.loraDatasetBuild)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l.loraPhotoHint),
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
                    final chosen = await pickPerson(context, allowNew: false);
                    if (chosen?.personId != null && mounted) {
                      final people = ref.read(peopleProvider).value ?? const [];
                      setState(() {
                        _person = chosen!.personId;
                        _name = people
                            .where((p) => p.id == _person)
                            .firstOrNull
                            ?.name;
                        _trigger.text = 'sks$_person';
                      });
                    }
                  },
            child: Text(_name ?? l.selectSourcePerson),
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
              for (final file in _photos.take(12))
                Image.file(
                  file,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  cacheWidth: 144,
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
          FilledButton(
            key: const Key('dataset-submit'),
            onPressed: _busy ? null : _submit,
            child: Text(l.loraDatasetBuild),
          ),
        ],
      ),
    );
  }
}

class DatasetScreen extends ConsumerWidget {
  const DatasetScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.loraDatasetEditor)),
      body: ref
          .watch(datasetItemsProvider(id))
          .when(
            loading: () => const LoadingBox(),
            error: (e, _) => Center(child: Text('$e')),
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
                  Text(
                    '${items.where((i) => i.included).length}/${items.length} · ${l.loraIncluded}',
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: items.where((i) => i.included).length < 5
                            ? null
                            : () => context.push(
                                '${Routes.loraTrain}?dataset=$id',
                              ),
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
                  ),
                  for (final item in items)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Image.file(
                                  ref
                                      .read(fileStoreProvider)
                                      .resolve(item.path),
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
      zip = await ref.read(loraRepositoryProvider).exportDataset(_dataset!);
      final id = await ref
          .read(studioRepositoryProvider)
          .enqueueInputs(
            serverId: caps.serverId,
            type: 'train_lora',
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l.loraTrainHint),
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
          DropdownButtonFormField<int>(
            initialValue: _dim,
            decoration: InputDecoration(labelText: l.loraDim),
            items: [
              for (final d in [4, 8, 16, 32, 64, 128])
                DropdownMenuItem(value: d, child: Text('$d')),
            ],
            onChanged: (v) => setState(() => _dim = v!),
          ),
          DropdownButtonFormField<int>(
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
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: l.loraLearningRate),
          ),
          const SizedBox(height: 16),
          FilledButton(
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
        ],
      ),
    );
  }
}

class LoraGenerateScreen extends ConsumerStatefulWidget {
  const LoraGenerateScreen({super.key, this.loraId});
  final String? loraId;
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
  bool _busy = false, _initialized = false;
  @override
  void initState() {
    super.initState();
    _model = widget.loraId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _prompt.text = AppLocalizations.of(
        context,
      ).loraDefaultPrompt('{trigger}');
      _initialized = true;
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
      final id = await ref
          .read(studioRepositoryProvider)
          .enqueueInputs(
            serverId: caps.serverId,
            type: 'generate_lora_images',
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
    final models = ref.watch(lorasProvider).value ?? const <LoraRow>[];
    if (!models.any((m) => m.id == _model)) _model = models.firstOrNull?.id;
    final selected = models.where((m) => m.id == _model).firstOrNull;
    final bases = caps?.loraBaseCheckpoints ?? const <String>[];
    if (!bases.contains(_base)) _base = bases.firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(l.loraGenerate)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
              key: ValueKey('generate-model-$_model'),
              initialValue: _model,
              decoration: InputDecoration(labelText: l.loraModel),
              items: [
                for (final m in models)
                  DropdownMenuItem(value: m.id, child: Text(m.triggerWord)),
              ],
              onChanged: (v) => setState(() => _model = v),
            ),
          if (bases.isEmpty)
            Text(l.loraNoBase)
          else
            DropdownButtonFormField<String>(
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
                        if (mounted) setState(() => _reference = file);
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
            Image.file(_reference!, height: 160, cacheWidth: 320),
            DropdownButtonFormField<String>(
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
          FilledButton(
            key: const Key('generate-submit'),
            onPressed:
                _busy ||
                    selected == null ||
                    _base == null ||
                    caps?.engines.loraGenerate != true
                ? null
                : () => _submit(selected),
            child: Text(l.loraGenerate),
          ),
        ],
      ),
    );
  }
}
