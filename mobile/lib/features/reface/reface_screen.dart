import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/router.dart';
import '../../data/api/dtos/analyze.dart';
import '../../data/api/dtos/system.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/studio_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../../studio_providers.dart';
import '../shared/crop_image.dart';
import '../shared/person_picker.dart';
import '../settings/background_screen.dart';

final studioVideoPickerProvider = Provider<Future<File?> Function()>(
  (ref) => () async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    return picked == null ? null : File(picked.path);
  },
);

class RefaceScreen extends ConsumerStatefulWidget {
  const RefaceScreen({super.key, this.personId});
  final int? personId;
  @override
  ConsumerState<RefaceScreen> createState() => _RefaceScreenState();
}

class _RefaceScreenState extends ConsumerState<RefaceScreen> {
  int _step = 0;
  Uint8List? _photo;
  File? _video;
  AnalyzeImageResponse? _analysis;
  final _targets = <int>{};
  final _sources = <int>{};
  List<FaceRow> _faces = [];
  int? _person;
  String? _personName;
  var _engine = 'v3';
  String? _dfm;
  var _restorer = 'auto';
  var _preset = 'natural';
  bool _parser = true, _occluder = true, _busy = false;
  bool _loraIdentity = false;
  String? _error;
  final _start = TextEditingController(text: '0');
  final _end = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.personId != null) {
      Future<void>.microtask(() => _loadPerson(widget.personId!));
    }
  }

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  Future<void> _loadPerson(int id) async {
    try {
      final faces = await ref.read(studioRepositoryProvider).sourceFaces(id);
      final people = await ref
          .read(peopleRepositoryProvider)
          .watchPeople()
          .first;
      final name = people.where((p) => p.id == id).firstOrNull?.name;
      if (!mounted) return;
      setState(() {
        _person = id;
        _personName = name;
        _faces = faces;
        _sources.clear();
        _sources.addAll(faces.take(20).map((f) => f.id));
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _pickPhoto() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(mobileApiProvider);
      if (api == null) return;
      final bytes = await ref.read(photoPickerProvider).pickPhoto();
      if (bytes == null) return;
      if (mounted) {
        setState(() {
          _photo = bytes;
          _video = null;
          _analysis = null;
          _targets.clear();
        });
      }
      final result = await api.analyzeImage(
        bytes,
        options: const AnalyzeOptions(minQuality: 0, detectBodies: false),
      );
      if (!mounted) return;
      setState(() {
        _analysis = result;
        _targets.addAll(List.generate(result.faces.length, (i) => i));
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickVideo() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await ref.read(studioVideoPickerProvider)();
      if (file != null && mounted) {
        setState(() {
          _video = file;
          _photo = null;
          _analysis = null;
          _targets.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Capabilities? _caps(ServerStatus? status) => switch (status) {
    ServerReady(:final capabilities) => capabilities,
    ServerBusy(:final capabilities) => capabilities,
    _ => null,
  };

  bool _validate(AppLocalizations l10n) {
    String? error;
    if (_step == 0) {
      if (_video == null && _analysis == null) {
        error = l10n.chooseTargetRequired;
      } else if (_video == null && _targets.isEmpty) {
        error = l10n.selectFaceRequired;
      } else if (_video != null) {
        final start = double.tryParse(_start.text.trim());
        final end = _end.text.trim().isEmpty
            ? null
            : double.tryParse(_end.text.trim());
        if (start == null ||
            !start.isFinite ||
            start < 0 ||
            start > 86400 ||
            (_end.text.trim().isNotEmpty &&
                (end == null ||
                    !end.isFinite ||
                    end <= start ||
                    end > 86400))) {
          error = l10n.invalidTrimRange;
        }
      }
    }
    if (_step == 1 &&
        _engine != 'dfm' &&
        (_person == null || _sources.isEmpty)) {
      error = l10n.selectIdentityRequired;
    }
    setState(() => _error = error);
    return error == null;
  }

  Future<void> _submit(Capabilities caps) async {
    await prepareBackgroundForWork(context, ref);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    File? temporary;
    try {
      if (ref.read(studioApiProvider) == null) {
        throw FormatException(l10n.studioNeedsPc);
      }
      var file = _video;
      if (file == null) {
        final tmp = await getTemporaryDirectory();
        temporary = File(
          '${tmp.path}/reface-${DateTime.now().microsecondsSinceEpoch}.jpg',
        );
        await temporary.writeAsBytes(_photo!, flush: true);
        file = temporary;
      }
      if (await file.length() > caps.limits.maxUploadMb * 1024 * 1024) {
        throw FormatException(l10n.fileTooLarge);
      }
      final source = _engine == 'dfm'
          ? <Map<String, dynamic>>[]
          : StudioRepository.encodeFaces(
              _faces
                  .where((f) => _sources.contains(f.id))
                  .take(_loraIdentity ? 60 : 100),
              caps.embeddingModelId,
            );
      if (_loraIdentity && _engine != 'dfm') {
        final models = ref.read(lorasProvider).value ?? const <LoraRow>[];
        final model = models
            .where((m) => m.personId == _person && m.identityJson != null)
            .firstOrNull;
        if (model != null) {
          final identity =
              jsonDecode(model.identityJson!) as Map<String, dynamic>;
          if (identity['model_id'] != caps.embeddingModelId) {
            throw const FormatException(
              'Rebuild this LoRA identity with the current PC model.',
            );
          }
          source.addAll(
            (identity['faces'] as List)
                .take(40)
                .map((e) => Map<String, dynamic>.from(e as Map)),
          );
        }
      }
      final params = <String, dynamic>{
        'source_faces': source,
        'model_id': caps.embeddingModelId,
        'restorer': _restorer,
        'use_parser': _parser,
        'use_occluder': _occluder,
        'realism_preset': _preset,
        if (_engine == 'dfm') 'dfm_model': _dfm,
        if (_video == null)
          'target_faces': [
            for (final i in _targets) _analysis!.faces[i].bbox.toJson(),
          ],
        if (_video != null) 'start_time': double.parse(_start.text.trim()),
        if (_video != null && _end.text.trim().isNotEmpty)
          'end_time': double.parse(_end.text.trim()),
      };
      final id = await ref
          .read(studioRepositoryProvider)
          .enqueue(
            serverId: caps.serverId,
            type: 'reface_${_video == null ? 'image' : 'video'}_$_engine',
            params: params,
            target: file,
            video: _video != null,
            personId: _person,
          );
      ref.read(jobTrackerProvider).start();
      if (mounted) context.pushReplacement('${Routes.jobs}/$id');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final caps = _caps(ref.watch(serverStatusProvider).value);
    final available = <String>[
      if (caps?.engines.refaceV3 == true) 'v3',
      if (caps?.engines.refaceV2 == true) 'v2',
      if (caps?.engines.dfmModels.isNotEmpty == true) 'dfm',
    ];
    if (available.isNotEmpty && !available.contains(_engine)) {
      _engine = available.first;
    }
    if (caps != null &&
        caps.engines.dfmModels.isNotEmpty &&
        !caps.engines.dfmModels.contains(_dfm)) {
      _dfm = caps.engines.dfmModels.first;
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.refaceTitle)),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: Stepper(
              currentStep: _step,
              onStepCancel: _busy || _step == 0
                  ? null
                  : () => setState(() {
                      _step--;
                      _error = null;
                    }),
              onStepContinue: _busy || caps == null || available.isEmpty
                  ? null
                  : () {
                      if (!_validate(l10n)) return;
                      if (_step < 3) {
                        setState(() => _step++);
                      } else {
                        _submit(caps);
                      }
                    },
              controlsBuilder: (context, details) => Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      key: details.isActive
                          ? const Key('reface-next')
                          : ValueKey('reface-next-${details.stepIndex}'),
                      onPressed: details.onStepContinue,
                      child: Text(_step == 3 ? l10n.submitReface : l10n.next),
                    ),
                    if (_step > 0)
                      TextButton(
                        onPressed: details.onStepCancel,
                        child: Text(l10n.back),
                      ),
                  ],
                ),
              ),
              steps: [
                Step(
                  title: Text(l10n.refaceTarget),
                  isActive: _step == 0,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (caps == null) Text(l10n.studioNeedsPc),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            key: const Key('reface-photo'),
                            onPressed: _busy || caps == null
                                ? null
                                : _pickPhoto,
                            child: Text(l10n.chooseTargetPhoto),
                          ),
                          OutlinedButton(
                            key: const Key('reface-video'),
                            onPressed: _busy ? null : _pickVideo,
                            child: Text(l10n.chooseTargetVideo),
                          ),
                        ],
                      ),
                      if (_photo != null && _analysis != null) ...[
                        const SizedBox(height: 12),
                        AspectRatio(
                          aspectRatio: _analysis!.imageW / _analysis!.imageH,
                          child: LayoutBuilder(
                            builder: (context, constraints) => Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.memory(_photo!, fit: BoxFit.fill),
                                for (
                                  var i = 0;
                                  i < _analysis!.faces.length;
                                  i++
                                )
                                  Positioned(
                                    left:
                                        _analysis!.faces[i].bbox.x /
                                        _analysis!.imageW *
                                        constraints.maxWidth,
                                    top:
                                        _analysis!.faces[i].bbox.y /
                                        _analysis!.imageH *
                                        constraints.maxHeight,
                                    width:
                                        _analysis!.faces[i].bbox.w /
                                        _analysis!.imageW *
                                        constraints.maxWidth,
                                    height:
                                        _analysis!.faces[i].bbox.h /
                                        _analysis!.imageH *
                                        constraints.maxHeight,
                                    child: Semantics(
                                      label: l10n.analyzeFaceTitle(i + 1),
                                      selected: _targets.contains(i),
                                      button: true,
                                      child: GestureDetector(
                                        key: Key('target-face-$i'),
                                        onTap: () => setState(() {
                                          if (!_targets.remove(i)) {
                                            _targets.add(i);
                                          }
                                        }),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: _targets.contains(i)
                                                  ? Colors.greenAccent
                                                  : Colors.white,
                                              width: 3,
                                            ),
                                          ),
                                          alignment: Alignment.topLeft,
                                          child: Text(
                                            '${i + 1}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              backgroundColor: Colors.black,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Text(l10n.selectedTargetFaces),
                        if (_analysis!.faces.isEmpty) Text(l10n.analyzeNoFaces),
                      ],
                      if (_video != null) ...[
                        Text(_video!.uri.pathSegments.last),
                        Text(l10n.videoSwapsAllFaces),
                        TextField(
                          controller: _start,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: l10n.videoTrimStart,
                          ),
                        ),
                        TextField(
                          controller: _end,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: l10n.videoTrimEnd,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Step(
                  title: Text(l10n.refaceIdentity),
                  isActive: _step == 1,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (available.isNotEmpty)
                        DropdownButtonFormField<String>(
                          key: ValueKey('identity-engine-$_engine'),
                          initialValue: _engine,
                          decoration: InputDecoration(
                            labelText: l10n.refaceEngine,
                          ),
                          items: [
                            for (final e in available)
                              DropdownMenuItem(
                                value: e,
                                child: Text(
                                  e == 'v3'
                                      ? l10n.refaceHd
                                      : e == 'v2'
                                      ? l10n.refaceLegacy
                                      : l10n.refacePro,
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() => _engine = v!),
                        ),
                      OutlinedButton(
                        key: const Key('reface-person'),
                        onPressed: _busy
                            ? null
                            : () async {
                                final person = await pickPerson(
                                  context,
                                  allowNew: false,
                                  title: l10n.selectSourcePerson,
                                );
                                if (person?.personId != null && mounted) {
                                  await _loadPerson(person!.personId!);
                                }
                              },
                        child: Text(_personName ?? l10n.selectSourcePerson),
                      ),
                      Text(l10n.sourceFacesHint),
                      if ((ref.watch(lorasProvider).value ?? const <LoraRow>[])
                          .any(
                            (m) =>
                                m.personId == _person && m.identityJson != null,
                          ))
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.loraIdentity),
                          value: _loraIdentity,
                          onChanged: (v) => setState(() => _loraIdentity = v),
                        ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final face in _faces)
                            SizedBox(
                              width: 76,
                              child: Column(
                                children: [
                                  SizedBox(
                                    width: 64,
                                    height: 64,
                                    child: CropImage(path: face.cropPath),
                                  ),
                                  Checkbox(
                                    key: Key('source-face-${face.id}'),
                                    value: _sources.contains(face.id),
                                    onChanged: (_) => setState(() {
                                      if (!_sources.remove(face.id)) {
                                        _sources.add(face.id);
                                      }
                                    }),
                                  ),
                                  Text('${(face.qualityScore * 100).round()}%'),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Step(
                  title: Text(l10n.refaceQuality),
                  isActive: _step == 2,
                  content: Column(
                    children: [
                      if (available.isEmpty) Text(l10n.studioNoEngine),
                      if (available.isNotEmpty)
                        DropdownButtonFormField<String>(
                          initialValue: _engine,
                          decoration: InputDecoration(
                            labelText: l10n.refaceEngine,
                          ),
                          items: [
                            for (final e in available)
                              DropdownMenuItem(
                                value: e,
                                child: Text(
                                  e == 'v3'
                                      ? l10n.refaceHd
                                      : e == 'v2'
                                      ? l10n.refaceLegacy
                                      : l10n.refacePro,
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() => _engine = v!),
                        ),
                      if (_engine == 'dfm' && caps != null)
                        DropdownButtonFormField<String>(
                          initialValue: _dfm,
                          decoration: InputDecoration(labelText: l10n.dfmModel),
                          items: [
                            for (final m in caps.engines.dfmModels)
                              DropdownMenuItem(value: m, child: Text(m)),
                          ],
                          onChanged: (v) => setState(() => _dfm = v),
                        ),
                      DropdownButtonFormField<String>(
                        initialValue: _restorer,
                        decoration: InputDecoration(
                          labelText: l10n.refaceRestorer,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'auto',
                            child: Text(l10n.restorerAuto),
                          ),
                          DropdownMenuItem(
                            value: 'none',
                            child: Text(l10n.restorerNone),
                          ),
                          for (final r in caps?.restorers ?? <String>[])
                            DropdownMenuItem(value: r, child: Text(r)),
                        ],
                        onChanged: (v) => setState(() => _restorer = v!),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _preset,
                        decoration: InputDecoration(
                          labelText: l10n.refacePreset,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'natural',
                            child: Text(l10n.presetNatural),
                          ),
                          DropdownMenuItem(
                            value: 'maximum_detail',
                            child: Text(l10n.presetDetail),
                          ),
                          DropdownMenuItem(
                            value: 'clean',
                            child: Text(l10n.presetClean),
                          ),
                        ],
                        onChanged: (v) => setState(() => _preset = v!),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.useFaceParser),
                        value: _parser,
                        onChanged: (v) => setState(() => _parser = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.protectOcclusions),
                        value: _occluder,
                        onChanged: (v) => setState(() => _occluder = v),
                      ),
                    ],
                  ),
                ),
                Step(
                  title: Text(l10n.refaceReview),
                  isActive: _step == 3,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_video == null ? l10n.resultPhoto : l10n.resultVideo} · $_engine · $_preset',
                      ),
                      if (_engine != 'dfm')
                        Text(
                          '${_personName ?? l10n.refaceIdentity} · ${_sources.length}',
                        ),
                      const SizedBox(height: 12),
                      Text(l10n.refaceReviewHint),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
