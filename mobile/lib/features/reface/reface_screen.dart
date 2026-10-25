import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import '../shared/empty_state.dart';
import '../settings/background_screen.dart';
import 'reface_media.dart';
import 'reface_video_trimmer.dart';
import 'reface_faces.dart';
import 'reface_face_choices.dart';

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
  int? _identitySet;
  var _engine = 'v3';
  String? _dfm;
  var _restorer = 'auto';
  var _preset = 'natural';
  bool _parser = true, _occluder = true, _busy = false;
  bool _loraIdentity = false;
  double _identityBoost = .5;
  String? _error;
  VideoTrimSelection? _videoTrim;
  int _targetRevision = 0;
  Timer? _targetScanTimer;
  int _targetScanGeneration = 0;
  bool _detectingTarget = false;
  double _targetScanProgress = 0;
  String? _targetScanError;
  Duration _previewPosition = Duration.zero;
  List<RefaceFaceGroup> _videoFaces = [];
  String? _targetModelId;
  bool _useImportedSource = false;
  final List<RefaceFaceGroup> _importedSources = [];
  int? _importedSource;
  String? _importedModelId;
  int _importedMediaCount = 0;

  @override
  void dispose() {
    _targetScanGeneration++;
    _targetScanTimer?.cancel();
    super.dispose();
  }

  void _trimChanged(VideoTrimSelection trim) {
    if (!mounted ||
        (_videoTrim?.start == trim.start && _videoTrim?.end == trim.end)) {
      return;
    }
    final generation = ++_targetScanGeneration;
    _targetScanTimer?.cancel();
    setState(() {
      _videoTrim = trim;
      _videoFaces = [];
      _targets.clear();
      _detectingTarget = true;
      _targetScanProgress = 0;
      _targetScanError = null;
    });
    _targetScanTimer = Timer(
      const Duration(milliseconds: 500),
      () => _detectVideoFaces(generation, trim),
    );
  }

  Future<void> _detectVideoFaces(
    int generation,
    VideoTrimSelection trim, {
    bool append = false,
    int count = 12,
  }) async {
    if (!mounted || generation != _targetScanGeneration) return;
    final l10n = AppLocalizations.of(context);
    bool current() => mounted && generation == _targetScanGeneration;
    try {
      final api = ref.read(mobileApiProvider);
      if (api == null || _video == null) {
        throw FormatException(l10n.studioNeedsPc);
      }
      final frames = await ref.read(refaceVideoFramesProvider)(
        _video!,
        start: trim.start,
        end: trim.end,
        count: count,
      );
      if (!current()) return;
      if (frames.isEmpty) {
        throw FormatException(l10n.videoUnavailableBody);
      }
      final groups = append
          ? _videoFaces.map(RefaceFaceGroup.copy).toList()
          : <RefaceFaceGroup>[];
      final selection = append ? Set<int>.of(_targets) : <int>{};
      String? model = append ? _targetModelId : null;
      for (var i = 0; i < frames.length; i++) {
        if (!current()) return;
        final result = await api.analyzeImage(
          frames[i],
          options: const AnalyzeOptions(minQuality: 0, detectBodies: false),
        );
        if (!current()) return;
        if (model != null && model != result.modelId) {
          throw const FormatException(
            'The face model changed. Detect the target again.',
          );
        }
        model = result.modelId;
        mergeRefaceFaces(groups, result.faces, selected: selection);
        setState(() => _targetScanProgress = (i + 1) / frames.length);
      }
      if (current()) {
        setState(() {
          _videoFaces = groups;
          _targetModelId = model;
          _targets
            ..clear()
            ..addAll(selection);
          if (groups.length == 1) _targets.add(0);
          _error = null;
        });
      }
    } catch (error) {
      if (current()) {
        setState(() {
          _targetScanError = error is PlatformException
              ? (error.message ?? l10n.videoUnavailableBody)
              : error is TimeoutException
              ? l10n.refaceVideoReadTimeout
              : '$error';
          _error = _targetScanError;
        });
      }
    } finally {
      if (current()) setState(() => _detectingTarget = false);
    }
  }

  void _detectShownFrame() {
    final trim = _videoTrim;
    if (trim == null) return;
    _targetScanTimer?.cancel();
    final generation = ++_targetScanGeneration;
    final position = Duration(
      microseconds: _previewPosition.inMicroseconds.clamp(
        trim.start.inMicroseconds,
        trim.end.inMicroseconds - 1000,
      ),
    );
    setState(() {
      _detectingTarget = true;
      _targetScanProgress = 0;
      _targetScanError = null;
      _error = null;
    });
    _detectVideoFaces(
      generation,
      VideoTrimSelection(
        start: position,
        end: position + const Duration(milliseconds: 1),
        duration: trim.duration,
      ),
      append: true,
      count: 1,
    );
  }

  Future<void> _addSourceMedia() async {
    final l10n = AppLocalizations.of(context);
    final location = await chooseRefaceMediaSource(context);
    if (location == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(mobileApiProvider);
      if (api == null) {
        throw FormatException(l10n.studioNeedsPc);
      }
      final media = await ref.read(refaceSourcePickerProvider)(location);
      if (media.isEmpty || !mounted) return;
      // Work on a copy: cancellation/failure cannot leave a half-imported identity.
      final groups = [
        for (final group in _importedSources) RefaceFaceGroup.copy(group),
      ];
      var model = _importedModelId;
      for (final file in media) {
        final frames = await isVideoTarget(file)
            ? await ref.read(refaceVideoFramesProvider)(
                File(file.path),
                count: 12,
              )
            : [await file.readAsBytes()];
        if (!mounted) return;
        if (frames.isEmpty) {
          throw FormatException(l10n.videoUnavailableBody);
        }
        for (final frame in frames) {
          final result = await api.analyzeImage(
            frame,
            options: const AnalyzeOptions(minQuality: 0, detectBodies: false),
          );
          if (!mounted) return;
          if (model != null && model != result.modelId) {
            throw const FormatException(
              'The face model changed. Clear the source photos and choose them again.',
            );
          }
          model = result.modelId;
          mergeRefaceFaces(
            groups,
            result.faces
                .where((face) => face.quality.score > 0 && face.detScore >= .5)
                .toList(),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _importedSources
          ..clear()
          ..addAll(groups);
        _importedModelId = model;
        _importedMediaCount += media.length;
        _importedSource = groups.length == 1 ? 0 : null;
        _useImportedSource = true;
        _person = null;
        _personName = null;
        _identitySet = null;
        _sources.clear();
        _faces = [];
        _loraIdentity = false;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.personId != null) {
      Future<void>.microtask(() => _loadPerson(widget.personId!));
    }
  }

  void _chooseEngine(String value) {
    setState(() {
      _engine = value;
      _restorer = 'auto';
      _preset = 'natural';
      _parser = true;
    });
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
        _useImportedSource = false;
        _loraIdentity = false;
        _identitySet = null;
        _personName = name;
        _faces = faces;
        _sources.clear();
        _sources.addAll(faces.take(20).map((f) => f.id));
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _saveIdentity() async {
    final l = AppLocalizations.of(context);
    var draft = '';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.identitySave),
        content: TextField(
          key: const Key('identity-name'),
          onChanged: (value) => draft = value,
          autofocus: true,
          maxLength: 80,
          decoration: InputDecoration(labelText: l.identityName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft),
            child: Text(l.save),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final id = await ref
          .read(identityRepositoryProvider)
          .save(name: name, personId: _person!, faceIds: _sources);
      if (mounted) {
        setState(() {
          _identitySet = id;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useIdentity(int id) async {
    setState(() => _busy = true);
    try {
      final faces = await ref.read(identityRepositoryProvider).faces(id);
      if (!mounted) return;
      setState(() {
        // Include saved faces even if they are outside the person's top 100.
        final byId = {
          for (final f in _faces) f.id: f,
          for (final f in faces) f.id: f,
        };
        _faces = byId.values.toList();
        _sources
          ..clear()
          ..addAll(faces.map((f) => f.id));
        _identitySet = id;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteIdentity() async {
    final l = AppLocalizations.of(context);
    final id = _identitySet;
    if (id == null ||
        !await confirm(
          context,
          title: l.identityDelete,
          body: l.identityDeleteBody,
          confirmLabel: l.identityDelete,
          cancelLabel: l.cancel,
          destructive: true,
        )) {
      return;
    }
    try {
      await ref.read(identityRepositoryProvider).delete(id);
      if (mounted) setState(() => _identitySet = null);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _pickPhoto(Uint8List bytes) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(mobileApiProvider);
      if (api == null) return;
      if (mounted) {
        setState(() {
          _photo = bytes;
          _video = null;
          _videoTrim = null;
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
        _targetModelId = result.modelId;
        _targets.addAll(List.generate(result.faces.length, (i) => i));
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickTarget() async {
    final source = await chooseRefaceMediaSource(context);
    if (source == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final target = await ref.read(refaceTargetPickerProvider)(source);
      if (target == null || !mounted) return;
      _targetScanGeneration++;
      _targetScanTimer?.cancel();
      _detectingTarget = false;
      _targetScanError = null;
      _videoFaces = [];
      if (target.photo != null) {
        await _pickPhoto(target.photo!);
      } else if (target.video != null) {
        setState(() {
          _video = target.video;
          _videoTrim = null;
          _targetRevision++;
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
        if (_detectingTarget) {
          error = l10n.refaceFindingFaces;
        } else if (_videoFaces.isEmpty || _targets.isEmpty) {
          error = l10n.selectFaceRequired;
        }
        final trim = _videoTrim;
        if (trim == null) {
          error = l10n.refaceTrimLoading;
        } else if (trim.startSeconds < 0 ||
            trim.endSeconds <= trim.startSeconds ||
            trim.endSeconds > 86400) {
          error = l10n.invalidTrimRange;
        }
      }
    }
    if (_step == 1 &&
        _engine != 'dfm' &&
        (_useImportedSource
            ? _importedSource == null
            : (_person == null || _sources.isEmpty))) {
      error = l10n.selectIdentityRequired;
    }
    setState(() => _error = error);
    return error == null;
  }

  Future<void> _submit(Capabilities caps, {bool preview = false}) async {
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
      if (_targetModelId != caps.embeddingModelId ||
          (_useImportedSource &&
              _engine != 'dfm' &&
              _importedModelId != caps.embeddingModelId)) {
        throw const FormatException(
          'The face model changed. Detect the target and source again.',
        );
      }
      if (_video != null &&
          (_engine == 'v2' || _videoFaces.isEmpty || _targets.isEmpty)) {
        throw FormatException(l10n.selectFaceRequired);
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
          : _useImportedSource
          ? _importedSources[_importedSource!].encode()
          : StudioRepository.encodeFaces(
              (await ref
                      .read(identityRepositoryProvider)
                      .selection(
                        personId: _person!,
                        faceIds: _sources,
                        modelId: caps.embeddingModelId,
                      ))
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
                .map(
                  (e) => <String, dynamic>{
                    ...Map<String, dynamic>.from(e as Map),
                    'generated': true,
                  },
                ),
          );
        }
      }
      final params = <String, dynamic>{
        'source_faces': source,
        'model_id': caps.embeddingModelId,
        if (_engine != 'dfm') 'restorer': _restorer,
        if (_engine != 'v2') 'use_parser': _parser,
        'use_occluder': _occluder,
        if (_engine != 'v2') 'realism_preset': _preset,
        if (_engine == 'v3') 'identity_boost': _identityBoost,
        'preview': preview,
        if (_engine == 'dfm') 'dfm_model': _dfm,
        if (_video == null)
          'target_faces': [
            for (final i in _targets) _analysis!.faces[i].bbox.toJson(),
          ],
        if (_video != null)
          ...encodeVideoTargetSelection(_videoFaces, _targets),
        if (_video != null) ...{
          'start_time': _videoTrim!.startSeconds,
          'end_time': _videoTrim!.endSeconds,
        },
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
      if (mounted) {
        if (preview) {
          await context.push('${Routes.jobs}/$id');
        } else {
          context.pushReplacement('${Routes.jobs}/$id');
        }
      }
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
    final identitySets =
        (ref.watch(identitySetsProvider).value ?? const <IdentitySetRow>[])
            .where((set) => set.personId == _person)
            .toList();
    final savedIdentity = identitySets.any((s) => s.id == _identitySet)
        ? _identitySet
        : null;
    final available = <String>[
      if (caps?.engines.refaceV3 == true) 'v3',
      if (caps?.engines.refaceV2 == true && _video == null) 'v2',
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
                      OutlinedButton.icon(
                        key: const Key('reface-target'),
                        onPressed: _busy || caps == null ? null : _pickTarget,
                        icon: const Icon(Icons.perm_media_outlined),
                        label: Text(l10n.chooseTargetMedia),
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
                        RefaceFaceChoices(
                          groups: [
                            for (final face in _analysis!.faces)
                              RefaceFaceGroup(face),
                          ],
                          selected: _targets,
                          keyPrefix: 'photo-target-face',
                          enabled: !_busy,
                          onToggle: (index) => setState(() {
                            if (!_targets.remove(index)) _targets.add(index);
                          }),
                        ),
                        if (_analysis!.faces.isEmpty) Text(l10n.analyzeNoFaces),
                      ],
                      if (_video != null) ...[
                        Text(_video!.uri.pathSegments.last),
                        const SizedBox(height: 12),
                        RefaceVideoTrimmer(
                          key: ValueKey('reface-trimmer-$_targetRevision'),
                          file: _video!,
                          active: _step == 0,
                          enabled: !_busy,
                          onChanged: _trimChanged,
                          onPositionChanged: (position) =>
                              _previewPosition = position,
                        ),
                        const SizedBox(height: 12),
                        Text(l10n.refaceTargetPeopleHint),
                        if (_detectingTarget) ...[
                          LinearProgressIndicator(
                            value: _targetScanProgress == 0
                                ? null
                                : _targetScanProgress,
                          ),
                          Text(
                            _targetScanProgress == 0
                                ? l10n.refaceReadingVideo
                                : l10n.refaceFindingFaces,
                            key: const Key('reface-video-scan-status'),
                          ),
                        ] else ...[
                          if (_targetScanError != null)
                            Text(
                              _targetScanError!,
                              key: const Key('reface-video-scan-error'),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            )
                          else if (_videoFaces.isEmpty && _videoTrim != null)
                            Text(l10n.analyzeNoFaces)
                          else if (_videoFaces.isNotEmpty)
                            Text(
                              l10n.refaceVideoPeopleFound(_videoFaces.length),
                            ),
                          RefaceFaceChoices(
                            groups: _videoFaces,
                            selected: _targets,
                            keyPrefix: 'video-target-face',
                            enabled: !_busy,
                            onToggle: (index) => setState(() {
                              if (!_targets.remove(index)) _targets.add(index);
                            }),
                          ),
                          TextButton.icon(
                            key: const Key('reface-detect-video-faces'),
                            onPressed:
                                _busy || caps == null || _videoTrim == null
                                ? null
                                : () {
                                    _targetScanTimer?.cancel();
                                    final generation = ++_targetScanGeneration;
                                    setState(() {
                                      _detectingTarget = true;
                                      _targetScanProgress = 0;
                                      _targetScanError = null;
                                      _error = null;
                                    });
                                    _detectVideoFaces(generation, _videoTrim!);
                                  },
                            icon: const Icon(Icons.face_outlined),
                            label: Text(l10n.refaceDetectVideoFaces),
                          ),
                          TextButton.icon(
                            key: const Key('reface-detect-current-frame'),
                            onPressed:
                                _busy || caps == null || _videoTrim == null
                                ? null
                                : _detectShownFrame,
                            icon: const Icon(Icons.center_focus_strong),
                            label: Text(l10n.refaceDetectShownFrame),
                          ),
                          if (caps == null) Text(l10n.studioNeedsPc),
                        ],
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
                          onChanged: (v) => _chooseEngine(v!),
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
                      if (_engine != 'dfm') ...[
                        OutlinedButton.icon(
                          key: const Key('reface-source-media'),
                          onPressed: _busy || caps == null
                              ? null
                              : _addSourceMedia,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: Text(l10n.refaceAddSourceMedia),
                        ),
                        Text(l10n.refaceSourceMediaHint),
                        if (_busy)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: LinearProgressIndicator(),
                          ),
                        if (_importedMediaCount > 0) ...[
                          Text(
                            l10n.refaceSourceMediaCount(_importedMediaCount),
                          ),
                          if (_importedSources.isEmpty)
                            Text(l10n.analyzeNoFaces),
                          RefaceFaceChoices(
                            groups: _importedSources,
                            selected: {
                              _useImportedSource && _importedSource != null
                                  ? _importedSource!
                                  : -1,
                            },
                            keyPrefix: 'imported-source-face',
                            enabled: !_busy,
                            onToggle: (index) => setState(() {
                              _useImportedSource = true;
                              _importedSource = index;
                              _person = null;
                              _personName = null;
                              _identitySet = null;
                              _loraIdentity = false;
                              _sources.clear();
                              _faces = [];
                            }),
                          ),
                          TextButton(
                            key: const Key('reface-clear-source-media'),
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _importedSources.clear();
                                    _importedSource = null;
                                    _importedModelId = null;
                                    _importedMediaCount = 0;
                                    _useImportedSource = false;
                                  }),
                            child: Text(l10n.refaceClearSourceMedia),
                          ),
                        ],
                      ],
                      Text(l10n.sourceFacesHint),
                      if (_person != null && _engine != 'dfm') ...[
                        if (identitySets.isNotEmpty)
                          DropdownButtonFormField<int>(
                            key: ValueKey('identity-set-$savedIdentity'),
                            initialValue: savedIdentity,
                            decoration: InputDecoration(
                              labelText: l10n.identitySaved,
                            ),
                            items: [
                              for (final set in identitySets)
                                DropdownMenuItem(
                                  value: set.id,
                                  child: Text(set.name),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (id) {
                                    if (id != null) _useIdentity(id);
                                  },
                          ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              key: const Key('identity-save'),
                              onPressed: _busy || _sources.isEmpty
                                  ? null
                                  : _saveIdentity,
                              icon: const Icon(Icons.bookmark_add_outlined),
                              label: Text(l10n.identitySave),
                            ),
                            if (savedIdentity != null)
                              TextButton.icon(
                                onPressed: _busy ? null : _deleteIdentity,
                                icon: const Icon(Icons.delete_outline),
                                label: Text(l10n.identityDelete),
                              ),
                          ],
                        ),
                      ],
                      if (!_useImportedSource &&
                          _person != null &&
                          (ref.watch(lorasProvider).value ?? const <LoraRow>[])
                              .any(
                                (m) =>
                                    m.personId == _person &&
                                    m.identityJson != null,
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
                                      _identitySet = null;
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
                          key: ValueKey('quality-engine-$_engine'),
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
                          onChanged: (v) => _chooseEngine(v!),
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
                      if (_engine != 'dfm')
                        DropdownButtonFormField<String>(
                          key: ValueKey('restorer-$_engine'),
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
                            for (final r
                                in _engine == 'v3'
                                    ? caps?.restorers ?? <String>[]
                                    : <String>[])
                              DropdownMenuItem(value: r, child: Text(r)),
                          ],
                          onChanged: (v) => setState(() => _restorer = v!),
                        ),
                      if (_engine != 'v2')
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
                      if (_engine != 'v2')
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.useFaceParser),
                          value: _parser,
                          onChanged: (v) => setState(() => _parser = v),
                        ),
                      if (_engine == 'v3') ...[
                        Text(l10n.refaceIdentityBoost),
                        Slider(
                          key: const Key('reface-identity-boost'),
                          value: _identityBoost,
                          min: 0,
                          max: 1,
                          divisions: 20,
                          label: _identityBoost.toStringAsFixed(2),
                          onChanged: (value) =>
                              setState(() => _identityBoost = value),
                        ),
                      ],
                      if (_engine == 'v2') Text(l10n.refaceLegacyHint),
                      if (_engine == 'dfm') Text(l10n.refaceDfmHint),
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
                          '${_useImportedSource ? l10n.refaceSourceMedia : (_personName ?? l10n.refaceIdentity)} · ${_useImportedSource && _importedSource != null ? _importedSources[_importedSource!].samples.length : _sources.length}',
                        ),
                      const SizedBox(height: 12),
                      Text(l10n.refaceReviewHint),
                      if (_videoTrim case final trim?)
                        Text(
                          '${l10n.refaceTrimStart}: ${trimTime(trim.start)} · ${l10n.refaceTrimEnd}: ${trimTime(trim.end)}',
                        ),
                      const SizedBox(height: 12),
                      Text(l10n.refacePreviewHint),
                      OutlinedButton(
                        key: const Key('reface-preview'),
                        onPressed: _busy || caps == null
                            ? null
                            : () => _submit(caps, preview: true),
                        child: Text(l10n.refacePreview),
                      ),
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
