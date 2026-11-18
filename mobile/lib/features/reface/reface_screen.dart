import '../shared/image_preview.dart';
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
import '../../data/api/dtos/embedding.dart';
import '../../data/api/dtos/system.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/studio_repository.dart';
import '../../data/repositories/artifact_context.dart';
import '../../data/repositories/media_queries.dart';
import '../shared/media_target.dart';
import '../../l10n/app_localizations.dart';
import '../shared/screen_layout.dart';
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
import 'reface_options.dart';
import 'reface_preflight_card.dart';
import '../../domain/reface/angle_generation.dart';
import '../../domain/reface/reface_preflight.dart';
import '../../domain/reface/reface_time.dart';
import '../../domain/geometry/outline.dart';

class RefaceScreen extends ConsumerStatefulWidget {
  const RefaceScreen({
    super.key,
    this.personId,
    this.faceId,
    this.identitySetId,
    this.targetMediaId,
    this.targetDetectionId,
  });
  final int? personId;
  final int? faceId;
  final int? identitySetId;
  final int? targetMediaId;
  final int? targetDetectionId;
  @override
  ConsumerState<RefaceScreen> createState() => _RefaceScreenState();
}

class _RefaceScreenState extends ConsumerState<RefaceScreen> {
  int _step = 0;
  Uint8List? _photo;
  File? _video;
  AnalyzeImageResponse? _analysis;
  MediaDetection? _contextTarget;
  int? _contextMediaId;
  String? _contextAssetId;
  final _targets = <int>{};
  bool _replaceAllFaces = false;
  final _sources = <int>{};
  List<FaceRow> _faces = [];
  int? _person;
  String? _personName;
  int? _identitySet;
  var _identityMode = 'photos';
  var _qualityProfile = 'balanced';
  String? _dfm;
  var _restorer = 'auto';
  var _preset = 'natural';
  bool _parser = true, _occluder = true, _busy = false;
  String? _referenceModelId;
  bool _useIdentityBundle = true;
  bool _use3dGeometry = false;
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
  bool _directSource = false;
  final List<RefaceFaceGroup> _importedSources = [];
  int? _importedSource;
  String? _importedModelId;
  int _importedMediaCount = 0;

  ({String jobId, String modelId, String serverId})? _referenceJob;
  StreamIterator<JobRow?>? _referenceWait;
  String? _referenceStatus;
  double? _referenceProgress;

  List<LoraRow> _personModels(List<LoraRow> models) {
    if (_person == null ||
        _directSource ||
        _useImportedSource ||
        _identityMode == 'dfm') {
      return const [];
    }
    return models.where((model) => model.personId == _person).toList();
  }

  LoraRow? _selectedReferenceModel(List<LoraRow> models) => _personModels(
    models,
  ).where((model) => model.id == _referenceModelId).firstOrNull;

  String _referenceModelName(BuildContext context, LoraRow model) {
    final created = DateTime.fromMillisecondsSinceEpoch(model.createdAt);
    final locale = MaterialLocalizations.of(context);
    return '${model.triggerWord} · ${locale.formatCompactDate(created)} '
        '${locale.formatTimeOfDay(TimeOfDay.fromDateTime(created))}';
  }

  List<Map<String, dynamic>> _generatedFaces(LoraRow model, String modelId) {
    try {
      final stored = model.identityJson;
      if (stored == null) return const [];
      final identity = jsonDecode(stored) as Map<String, dynamic>;
      if (identity['model_id'] != modelId) return const [];
      return [
        for (final face in (identity['faces'] as List).take(40))
          if (face is Map &&
              face['embedding'] is String &&
              face['quality'] is num)
            {...Map<String, dynamic>.from(face), 'generated': true},
      ];
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  /// "Before we start": the target's face sizes and poses against the source's, from what the phone already
  /// measured (no PC). Null when there is nothing to compare (a trained identity, or sources read from media).
  RefacePreflight? _preflight({
    List<Map<String, dynamic>> generated = const [],
  }) {
    if (_identityMode == 'dfm' || _useImportedSource) return null;
    final targets = <PreflightTarget>[];
    if (_video == null) {
      final faces = _analysis?.faces ?? const <DetectedFace>[];
      final picked = _replaceAllFaces
          ? [for (var i = 0; i < faces.length; i++) i]
          : _targets.toList();
      for (final i in picked) {
        if (i < 0 || i >= faces.length) continue;
        final q = faces[i].quality;
        targets.add(
          PreflightTarget(
            facePx: q.facePx,
            yaw: q.pose?.yaw,
            pitch: q.pose?.pitch,
          ),
        );
      }
    } else {
      final picked = _replaceAllFaces
          ? [for (var i = 0; i < _videoFaces.length; i++) i]
          : _targets.toList();
      for (final i in picked) {
        if (i < 0 || i >= _videoFaces.length) continue;
        // one entry per distinct appearance the scan sampled of this person
        for (final face in _videoFaces[i].samples) {
          final q = face.quality;
          targets.add(
            PreflightTarget(
              facePx: q.facePx,
              yaw: q.pose?.yaw,
              pitch: q.pose?.pitch,
            ),
          );
        }
      }
    }
    final sources = <PreflightSource>[
      for (final f in _faces)
        if (_sources.contains(f.id))
          PreflightSource(yaw: f.yaw, pitch: f.pitch, facePx: f.facePx),
    ];
    for (final face in generated) {
      final pose = face['pose'];
      sources.add(
        PreflightSource(
          yaw: pose is Map ? (pose['yaw'] as num?)?.toDouble() : null,
          pitch: pose is Map ? (pose['pitch'] as num?)?.toDouble() : null,
          generated: true,
        ),
      );
    }
    return RefacePreflight(targets: targets, sources: sources);
  }

  Future<void> _measureReferenceTarget() async {
    if (!_replaceAllFaces) return;
    final video = _video;
    if (video != null && _videoFaces.isEmpty) {
      final generation = ++_targetScanGeneration;
      await _detectVideoFaces(generation, _videoTrim!);
      if (!mounted) return;
      if (_targetScanError case final error?) throw FormatException(error);
    } else if (video == null && _analysis == null) {
      final result = await ref
          .read(mobileApiProvider)!
          .analyzeImage(
            _photo!,
            options: const AnalyzeOptions(minQuality: 0, detectBodies: false),
          );
      if (mounted) setState(() => _analysis = result);
    }
  }

  Future<void> _waitForPortraits(String id) async {
    final l = AppLocalizations.of(context);
    final jobs = StreamIterator(
      ref.read(studioRepositoryProvider).watchJob(id),
    );
    _referenceWait = jobs;
    try {
      while (await jobs.moveNext() && mounted) {
        final job = jobs.current;
        switch (job?.status) {
          case 'completed':
            return;
          case 'paused':
            throw FormatException(l.refaceModelPaused);
          case null || 'failed' || 'lost' || 'cancelled':
            _referenceJob = null;
            throw FormatException(job?.error ?? l.refaceModelFailed);
          default:
            setState(() => _referenceProgress = job!.progress.clamp(0.0, 1.0));
        }
      }
    } finally {
      await jobs.cancel();
      _referenceWait = null;
    }
  }

  Future<List<Map<String, dynamic>>> _prepareModelReferences(
    Capabilities caps,
    LoraRow model,
  ) async {
    final l = AppLocalizations.of(context);
    final api = ref.read(mobileApiProvider);
    if (api == null) throw FormatException(l.studioNeedsPc);
    final studio = ref.read(studioRepositoryProvider);
    final loras = ref.read(loraRepositoryProvider);
    final files = ref.read(fileStoreProvider);
    final tracker = ref.read(jobTrackerProvider);
    setState(() => _referenceStatus = l.refaceModelCheckingTarget);
    await _measureReferenceTarget();
    if (!mounted) return const [];
    final existing = _generatedFaces(model, caps.embeddingModelId);
    final preflight = _preflight(generated: existing)!;
    if (preflight.targetFaces == 0) throw FormatException(l.selectFaceRequired);
    final plan = AngleGenerationPlan.forModel(preflight);
    final trainingFaces = _sources.isEmpty
        ? await loras.trainingReferenceFaces(model, api, caps.embeddingModelId)
        : const <DetectedFace>[];
    if (!mounted) return const [];
    if (_sources.isEmpty && trainingFaces.isEmpty) {
      throw FormatException(l.refaceModelNeedsReference);
    }
    final trainingReferences = [
      for (final face in trainingFaces)
        {
          'embedding': encodeEmbedding(face.embedding),
          'quality': face.quality.score,
          if (face.quality.pose case final pose?)
            'pose': {'yaw': pose.yaw, 'pitch': pose.pitch, 'roll': pose.roll},
        },
    ];
    final pending = _referenceJob;
    String? id =
        pending?.modelId == model.id && pending?.serverId == caps.serverId
        ? pending?.jobId
        : null;
    if (id == null && plan == null) return [...trainingReferences, ...existing];
    if (id == null) {
      if (!caps.engines.loraGenerate || caps.loraBaseCheckpoints.isEmpty) {
        throw FormatException(l.refaceModelUnavailable);
      }
      final modelContext = await studio.contextFor(model.id);
      final identityModel = modelContext?.identityModelId;
      final trainedBase = modelContext?.loraBaseCheckpoint;
      if (trainedBase != null &&
          !caps.loraBaseCheckpoints.contains(trainedBase)) {
        throw FormatException(l.refaceModelBaseUnavailable);
      }
      if ((identityModel != null && identityModel != caps.embeddingModelId) ||
          (caps.hasOperationSupport &&
              !caps.supportsOperation(
                'lora_generate',
                'person',
                identityModelId: caps.embeddingModelId,
              ))) {
        throw FormatException(l.refaceModelUnavailable);
      }
      final file = files.resolve(model.path);
      if (!await file.exists()) {
        throw FormatException(l.refaceModelFileUnavailable);
      }
      if (!mounted) return const [];
      setState(() => _referenceStatus = l.refaceModelGenerating);
      id = await studio.enqueueInputs(
        serverId: caps.serverId,
        type: 'generate_lora_images',
        context: ArtifactContext(
          personId: model.personId,
          modelId: model.id,
          identityModelId: identityModel,
        ),
        params: {
          'trigger_word': model.triggerWord,
          'base_checkpoint': trainedBase ?? caps.loraBaseCheckpoints.first,
          'prompt': l.loraDefaultPrompt(model.triggerWord),
          'num_images': plan!.count,
          'angles': plan.angles,
          'seed': -1,
          'steps': 30,
          if (identityModel != null && caps.hasOperationSupport)
            'identity_model_id': identityModel,
        },
        inputs: {
          'lora': [file],
        },
        personId: model.personId,
      );
      _referenceJob = (jobId: id, modelId: model.id, serverId: caps.serverId);
    }
    tracker.start();
    if (!mounted) return const [];
    setState(() => _referenceStatus = l.refaceModelGenerating);
    await _waitForPortraits(id);
    if (!mounted) return const [];
    setState(() {
      _referenceStatus = l.refaceModelVerifying;
      _referenceProgress = null;
    });
    try {
      await loras.buildIdentity(model, api, trainingFaces: trainingFaces);
    } on FormatException {
      // A new attempt is useful when the generated portraits failed verification.
      _referenceJob = null;
      rethrow;
    }
    final updated = await loras.model(model.id);
    if (!mounted) return const [];
    final generated = updated == null
        ? const <Map<String, dynamic>>[]
        : _generatedFaces(updated, caps.embeddingModelId);
    _referenceJob = null;
    if (generated.isEmpty) throw FormatException(l.refaceModelFailed);
    return [...trainingReferences, ...generated];
  }

  /// How long each quality choice would take for this photo or clip ("about 40 s"), from what the PC reports
  /// it typically needs per face. Empty when the PC does not say or the request is not sized yet.
  Map<String, String> _takes(Capabilities? caps) {
    if (caps == null || _identityMode == 'dfm') return const {};
    final video = _video != null;
    final trim = _videoTrim;
    final frames = video
        ? (trim == null ? 0 : RefaceTime.framesOf(trim.end - trim.start))
        : 1;
    final picked = _replaceAllFaces
        ? (video ? _videoFaces.length : _analysis?.faces.length ?? 0)
        : _targets.length;
    return {
      for (final entry
          in (video ? caps.refaceVideoMs : caps.refacePhotoMs).entries)
        if (RefaceTime.processing(
              msPerFace: entry.value,
              frames: frames,
              faces: picked,
            )
            case final cost?)
          entry.key: RefaceTime.words(cost),
    };
  }

  @override
  void dispose() {
    unawaited(_referenceWait?.cancel());
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
      _detectingTarget = !_replaceAllFaces;
      _targetScanProgress = 0;
      _targetScanError = null;
    });
    if (_replaceAllFaces) return;
    _targetScanTimer = Timer(
      const Duration(milliseconds: 500),
      () => _detectVideoFaces(generation, trim),
    );
  }

  void _setReplaceAllFaces(bool value) {
    _targetScanTimer?.cancel();
    final generation = ++_targetScanGeneration;
    final trim = _videoTrim;
    final rescan =
        !value && _video != null && trim != null && _videoFaces.isEmpty;
    setState(() {
      _replaceAllFaces = value;
      _detectingTarget = rescan;
      _targetScanProgress = 0;
      _targetScanError = null;
      _error = null;
    });
    if (rescan) {
      _detectVideoFaces(generation, trim);
    } else if (!value && _photo != null && _analysis == null) {
      _pickPhoto(_photo!);
    }
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
          final faces = result.faces
              .where((face) => face.quality.score > 0 && face.detScore >= .5)
              .toList();
          mergeRefaceFaces(groups, faces);
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
        _referenceModelId = null;
        _referenceJob = null;
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
    if (widget.targetMediaId != null) {
      Future<void>.microtask(_loadContextTarget);
    }
    if (widget.faceId != null) {
      Future<void>.microtask(() => _loadFace(widget.faceId!));
    } else if (widget.personId != null) {
      Future<void>.microtask(() async {
        await _loadPerson(widget.personId!);
        if (mounted && widget.identitySetId != null) {
          final identities = await ref.read(identitySetsProvider.future);
          if (mounted &&
              identities.any(
                (item) =>
                    item.id == widget.identitySetId &&
                    item.personId == widget.personId,
              )) {
            await _useIdentity(widget.identitySetId!);
          }
        }
      });
    }
  }

  Future<void> _loadContextTarget() async {
    if (mounted) setState(() => _busy = true);
    try {
      final source = await ref
          .read(mediaActionSourceProvider)
          .resolve(
            widget.targetMediaId!,
            targetDetectionId: widget.targetDetectionId,
          );
      if (!mounted) return;
      _contextTarget = source.target;
      if (source.target?.figure == 'character') {
        throw const FormatException('Reface is available for people only.');
      }
      _contextMediaId = source.media.id;
      _contextAssetId = source.media.assetId;
      if (source.isVideo) {
        setState(() {
          _video = source.originalFile;
          _videoTrim = null;
          _targetRevision++;
          _photo = null;
          _analysis = null;
          _targets.clear();
        });
      } else {
        await _pickPhoto(source.photoBytes!, target: source.target);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _chooseIdentityMode(String value) {
    setState(() {
      _identityMode = value;
      if (value == 'dfm') {
        _qualityProfile = 'balanced';
        _referenceModelId = null;
        _referenceJob = null;
      }
      _restorer = 'auto';
      _preset = 'natural';
      _parser = _qualityProfile != 'fast';
    });
  }

  void _chooseQualityProfile(String value) {
    setState(() {
      _qualityProfile = value;
      _restorer = 'auto';
      _parser = value != 'fast';
    });
  }

  Future<void> _loadPerson(int id) async {
    try {
      final modelId =
          _caps(ref.read(serverStatusProvider).value)?.embeddingModelId ??
          'buffalo_l@1';
      final faces = await ref
          .read(studioRepositoryProvider)
          .refaceSources(id, modelId: modelId);
      final db = ref.read(databaseProvider);
      final person = await (db.select(
        db.persons,
      )..where((p) => p.id.equals(id))).getSingleOrNull();
      if (person == null || person.kind != 'person') {
        throw const FormatException('Reface is available for people only.');
      }
      final name = person.name;
      if (!mounted) return;
      setState(() {
        _person = id;

        _directSource = false;
        _useImportedSource = false;
        _referenceModelId = null;
        _referenceJob = null;
        _useIdentityBundle = true;
        _identitySet = null;
        _personName = name;
        _error = null;
        _faces = faces;
        _sources.clear();
        _sources.addAll(
          StudioRepository.diverseSources(faces, 20).map((f) => f.id),
        );
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _loadFace(int id) async {
    try {
      final db = ref.read(databaseProvider);
      final face = await (db.select(
        db.faces,
      )..where((f) => f.id.equals(id))).getSingle();
      if (face.kind != 'person') {
        throw const FormatException('Reface is available for people only.');
      }
      if (!mounted) return;
      setState(() {
        _directSource = true;

        _person = face.personId;
        _personName = 'Face ${face.id}';
        _faces = [face];
        _sources
          ..clear()
          ..add(face.id);
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
        _useIdentityBundle = false;
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

  Future<void> _pickPhoto(Uint8List bytes, {MediaDetection? target}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(mobileApiProvider);
      if (mounted) {
        setState(() {
          _photo = bytes;
          _video = null;
          _videoTrim = null;
          _analysis = null;
          _targets.clear();
        });
      }
      if (api == null || _replaceAllFaces) return;
      final result = await api.analyzeImage(
        bytes,
        options: const AnalyzeOptions(minQuality: 0, detectBodies: false),
      );
      if (!mounted) return;
      setState(() {
        _analysis = result;
        _targetModelId = result.modelId;
        if (target != null) {
          final matched = matchTargetFace(result, target);
          if (matched != null) {
            _targets.add(matched);
          } else {
            _error = 'Select the target person in this photo.';
          }
        } else if (result.faces.length == 1) {
          _targets.add(0);
        }
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
      _contextTarget = null;
      _contextMediaId = null;
      _contextAssetId = null;
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

  Future<String?> _savedIdentityBundle(Capabilities caps) async {
    final personId = _person;
    if (!_useIdentityBundle ||
        personId == null ||
        _identityMode == 'dfm' ||
        _directSource ||
        _useImportedSource ||
        _referenceModelId != null ||
        !caps.engines.identityBundle) {
      return null;
    }
    return ref
        .read(studioRepositoryProvider)
        .savedRefaceProfile(personId, caps.embeddingModelId);
  }

  Future<void> _buildIdentity(
    Capabilities caps, {
    required bool fromGallery,
  }) async {
    final personId = _person;
    if (personId == null || _busy || !caps.engines.identityBundle) return;
    final l = AppLocalizations.of(context);
    final location = fromGallery ? null : await chooseRefaceMediaSource(context);
    if ((!fromGallery && location == null) || !mounted || _person != personId) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    Directory? staging;
    try {
      final repo = ref.read(studioRepositoryProvider);
      final inputs = <File>[];
      final faceIds = <int>[];
      if (fromGallery) {
        final faces = await repo.refaceSources(
          personId,
          faceIds: _sources,
          modelId: caps.embeddingModelId,
        );
        for (final face in faces) {
          if (inputs.length == 64) break;
          final path = face.cropPath;
          if (path == null) continue;
          try {
            final file = repo.files.resolve(path);
            if (await file.length() == 0) continue;
            inputs.add(file);
            faceIds.add(face.id);
          } on FileSystemException {
            // Crops can be evicted or removed after the face was selected.
          } on FormatException {
            // Older libraries can contain paths that no longer resolve.
          }
        }
      } else {
        final picked = await ref.read(refaceSourcePickerProvider)(location!);
        if (picked.isEmpty || !mounted) return;
        for (final source in picked) {
          if (await isVideoTarget(source)) {
            staging ??= await (await getTemporaryDirectory()).createTemp(
              'identity-',
            );
            final frames = await ref.read(refaceVideoFramesProvider)(
              File(source.path),
            );
            for (final frame in frames) {
              if (inputs.length == 64) break;
              final file = File('${staging.path}/${inputs.length}.jpg');
              inputs.add(await file.writeAsBytes(frame));
            }
          } else {
            inputs.add(File(source.path));
          }
          if (inputs.length == 64) break;
        }
      }
      if (!mounted) return;
      if (inputs.isEmpty) {
        throw FormatException(
          fromGallery
              ? l.refaceProfileNoCrops
              : 'Choose clear source photos or a readable video.',
        );
      }
      await prepareBackgroundForWork(context, ref);
      if (!mounted) return;
      await repo.enqueueInputs(
        serverId: caps.serverId,
        type: 'build_identity',
        params: const {},
        inputs: {'images': inputs},
        personId: personId,
        context: fromGallery
            ? ArtifactContext(
                personId: personId,
                identityModelId: caps.embeddingModelId,
                sourceFaceIds: faceIds,
              )
            : null,
      );
      if (!mounted) return;
      ref.read(jobTrackerProvider).start();
      setState(() => _useIdentityBundle = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Identity build queued. Follow its progress in Studio.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      try {
        await staging?.delete(recursive: true);
      } on FileSystemException {
        // The durable queue owns its staged copies.
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _validate(AppLocalizations l10n, {bool hasBundle = false}) {
    String? error;
    if (_step == 0) {
      if (_video == null &&
          (_photo == null || (!_replaceAllFaces && _analysis == null))) {
        error = l10n.chooseTargetRequired;
      } else if (_video == null && !_replaceAllFaces && _targets.isEmpty) {
        error = l10n.selectFaceRequired;
      } else if (_video != null) {
        if (!_replaceAllFaces && _detectingTarget) {
          error = l10n.refaceFindingFaces;
        } else if (!_replaceAllFaces &&
            (_videoFaces.isEmpty || _targets.isEmpty)) {
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
        _identityMode != 'dfm' &&
        (_useImportedSource
            ? _importedSource == null
            : ((!_directSource && _person == null) ||
                  (_sources.isEmpty &&
                      !hasBundle &&
                      _referenceModelId == null)))) {
      error = l10n.selectIdentityRequired;
    }
    setState(() => _error = error);
    return error == null;
  }

  Future<void> _submit(Capabilities caps, {bool preview = false}) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    File? temporary;
    File? bundleFile;
    try {
      await prepareBackgroundForWork(context, ref);
      if (!mounted) return;
      if (ref.read(studioApiProvider) == null) {
        throw FormatException(l10n.studioNeedsPc);
      }
      if ((!_replaceAllFaces && _targetModelId != caps.embeddingModelId) ||
          (_useImportedSource &&
              _identityMode != 'dfm' &&
              _importedModelId != caps.embeddingModelId)) {
        throw const FormatException(
          'The face model changed. Detect the target and source again.',
        );
      }
      if (!_replaceAllFaces &&
          _video != null &&
          (_videoFaces.isEmpty || _targets.isEmpty)) {
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
      if (!mounted) return;
      final modelId = _referenceModelId;
      final model = modelId == null
          ? null
          : await ref.read(loraRepositoryProvider).model(modelId);
      if (!mounted) return;
      if (modelId != null && (model == null || model.personId != _person)) {
        throw FormatException(l10n.refaceModelFileUnavailable);
      }
      final modelSources = model == null
          ? const <Map<String, dynamic>>[]
          : await _prepareModelReferences(caps, model);
      if (!mounted) return;
      final identityBundle = await _savedIdentityBundle(caps);
      final source = <Map<String, dynamic>>[];
      if (_identityMode != 'dfm' && identityBundle == null) {
        if (_useImportedSource) {
          source.addAll(_importedSources[_importedSource!].encode());
        } else {
          final db = ref.read(databaseProvider);
          final faces = _directSource
              ? await (db.select(
                  db.faces,
                )..where((f) => f.id.isIn(_sources))).get()
              : await ref
                    .read(studioRepositoryProvider)
                    .refaceSources(
                      _person!,
                      faceIds: _sources,
                      modelId: caps.embeddingModelId,
                    );
          if (faces.length != _sources.length) {
            throw FormatException(l10n.refaceProfileSourcesChanged);
          }
          if (faces.isNotEmpty || model == null) {
            source.addAll(
              StudioRepository.encodeFaces(
                faces.take(100 - modelSources.length),
                caps.embeddingModelId,
              ),
            );
          }
        }
      }
      source.addAll(modelSources);
      if (identityBundle != null) {
        final tmp = await getTemporaryDirectory();
        bundleFile = File(
          '${tmp.path}/reface-identity-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        await bundleFile.writeAsString(identityBundle);
      }
      final params = <String, dynamic>{
        'source_faces': source,
        'model_id': caps.embeddingModelId,
        if (_identityMode != 'dfm') 'restorer': _restorer,
        'use_parser': _parser,
        'use_occluder': _occluder,
        'realism_preset': _preset,
        'quality_profile': _qualityProfile,
        if (caps.engines.refaceGeometry && _use3dGeometry)
          'use_3d_geometry': true,
        if (_identityMode != 'dfm') 'identity_boost': _identityBoost,
        'preview': preview,
        if (_identityMode == 'dfm') 'dfm_model': _dfm,
        if (!_replaceAllFaces && _video == null)
          'target_faces': [
            for (final i in _targets) _analysis!.faces[i].bbox.toJson(),
          ],
        if (!_replaceAllFaces && _video != null)
          ...encodeVideoTargetSelection(_videoFaces, _targets),
        if (_video != null) ...{
          'start_time': _videoTrim!.startSeconds,
          'end_time': _videoTrim!.endSeconds,
        },
      };
      final matchedTarget = _analysis == null
          ? null
          : matchTargetFace(_analysis!, _contextTarget);
      final selectedContext =
          !_replaceAllFaces &&
              _targets.length == 1 &&
              matchedTarget != null &&
              _targets.contains(matchedTarget)
          ? _contextTarget
          : null;
      final id = await ref
          .read(studioRepositoryProvider)
          .enqueue(
            serverId: caps.serverId,
            type: 'reface_${_video == null ? 'image' : 'video'}',
            params: params,
            target: file,
            video: _video != null,
            identityBundle: bundleFile,
            personId: _person,
            context: ArtifactContext(
              mediaId: _contextMediaId,
              assetId: _contextAssetId,
              detectionId: selectedContext?.id,
              targetPersonId: selectedContext?.personId,
              personId: _identityMode == 'dfm' || _useImportedSource
                  ? null
                  : _person,
              modelId: model?.id,
            ),
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
      if (bundleFile != null && await bundleFile.exists()) {
        await bundleFile.delete();
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _referenceStatus = null;
          _referenceProgress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final caps = _caps(ref.watch(serverStatusProvider).value);
    final models = ref.watch(lorasProvider).value ?? const <LoraRow>[];
    final personModels = _personModels(models);
    final referenceModel = _selectedReferenceModel(models);
    final buildingProfile =
        _person != null &&
        (ref.watch(jobsProvider).value ?? const <JobRow>[]).any(
          (job) => job.type == 'build_identity' &&
              job.personId == _person &&
              !const [
                'completed',
                'failed',
                'paused',
                'lost',
                'cancelled',
              ].contains(job.status),
        );
    final identitySets =
        (ref.watch(identitySetsProvider).value ?? const <IdentitySetRow>[])
            .where((set) => set.personId == _person)
            .toList();
    final savedIdentity = identitySets.any((s) => s.id == _identitySet)
        ? _identitySet
        : null;
    final available = <String>[
      if (caps?.engines.reface == true) 'photos',
      if (caps?.engines.reface == true &&
          caps?.engines.dfmModels.isNotEmpty == true)
        'dfm',
    ];
    if (!available.contains(_identityMode)) _identityMode = 'photos';
    if (_restorer != 'auto' &&
        _restorer != 'none' &&
        !(caps?.restorers.contains(_restorer) ?? false)) {
      _restorer = 'auto';
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
          if (_referenceStatus case final status?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(status, key: const Key('reface-model-status')),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    key: const Key('reface-angles-progress'),
                    value: _referenceProgress,
                    semanticsLabel: status,
                  ),
                ],
              ),
            )
          else if (_busy)
            const LinearProgressIndicator(),
          Expanded(
            child: GuidedWorkflow(
              progressLabel: l10n.workflowProgress(_step + 1, 3),
              currentStep: _step,
              onStepCancel: _busy || _step == 0
                  ? null
                  : () => setState(() {
                      _step--;
                      _error = null;
                    }),
              onStepContinue: _busy || caps == null || available.isEmpty
                  ? null
                  : () async {
                      final bundle = _step == 1 ? await _savedIdentityBundle(caps) : null;
                      if (!mounted || !_validate(l10n, hasBundle: bundle != null)) return;
                      if (_step < 2) {
                        setState(() => _step++);
                      } else {
                        _submit(caps);
                      }
                    },
              controlsBuilder: (context, details) => Row(
                children: [
                  if (_step > 0) ...[
                    TextButton(
                      onPressed: details.onStepCancel,
                      child: Text(l10n.back),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: FilledButton(
                      key: const Key('reface-next'),
                      onPressed: details.onStepContinue,
                      child: Text(
                        _step != 2
                            ? l10n.next
                            : referenceModel == null
                            ? l10n.submitReface
                            : l10n.refaceModelStart,
                      ),
                    ),
                  ),
                ],
              ),
              steps: [
                Step(
                  title: Text(l10n.refaceTarget),
                  isActive: _step == 0,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (caps == null) Text(l10n.studioNeedsPc),
                      if (caps != null && available.isEmpty)
                        Text(l10n.refaceUnifiedUnavailable),
                      OutlinedButton.icon(
                        key: const Key('reface-target'),
                        onPressed: _busy || caps == null ? null : _pickTarget,
                        icon: const Icon(Icons.perm_media_outlined),
                        label: Text(l10n.chooseTargetMedia),
                      ),
                      SwitchListTile(
                        key: const Key('reface-all-faces'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.refaceAllFaces),
                        subtitle: Text(l10n.refaceAllFacesHint),
                        value: _replaceAllFaces,
                        onChanged: _busy ? null : _setReplaceAllFaces,
                      ),
                      if (_photo != null &&
                          _analysis == null &&
                          caps != null &&
                          !_replaceAllFaces)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () =>
                                    _pickPhoto(_photo!, target: _contextTarget),
                          child: const Text('Detect target faces'),
                        ),
                      if (_photo != null && _analysis == null)
                        PreviewImage.memory(
                          _photo!,
                          height: 220,
                          fit: BoxFit.contain,
                        ),
                      if (_photo != null && _analysis != null) ...[
                        const SizedBox(height: 12),
                        ImageExpand(
                          source: ImagePreviewSource.bytes(_photo!),
                          child: AspectRatio(
                            aspectRatio: _analysis!.imageW / _analysis!.imageH,
                            child: LayoutBuilder(
                              builder: (context, constraints) => Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.memory(_photo!, fit: BoxFit.fill),
                                  if (!_replaceAllFaces)
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
                                            child: CustomPaint(
                                              painter: DetectionBoxPainter(
                                                isFace: true,
                                                outline:
                                                    _analysis!
                                                            .faces[i]
                                                            .outline ==
                                                        null
                                                    ? null
                                                    : [
                                                        for (final p
                                                            in _analysis!
                                                                .faces[i]
                                                                .outline!)
                                                          Offset(
                                                            (p.dx -
                                                                    _analysis!
                                                                        .faces[i]
                                                                        .bbox
                                                                        .x) /
                                                                _analysis!
                                                                    .faces[i]
                                                                    .bbox
                                                                    .w,
                                                            (p.dy -
                                                                    _analysis!
                                                                        .faces[i]
                                                                        .bbox
                                                                        .y) /
                                                                _analysis!
                                                                    .faces[i]
                                                                    .bbox
                                                                    .h,
                                                          ),
                                                      ],
                                                fillColor: _targets.contains(i)
                                                    ? Colors.greenAccent
                                                          .withValues(
                                                            alpha: 0.20,
                                                          )
                                                    : Colors.black.withValues(
                                                        alpha: 0.10,
                                                      ),
                                                borderColor:
                                                    _targets.contains(i)
                                                    ? Colors.greenAccent
                                                    : Colors.white,
                                                borderWidth: 3,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (!_replaceAllFaces) ...[
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
                          if (_analysis!.faces.isEmpty)
                            Text(l10n.analyzeNoFaces),
                        ],
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
                        if (!_replaceAllFaces) ...[
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
                                if (!_targets.remove(index)) {
                                  _targets.add(index);
                                }
                              }),
                            ),
                            TextButton.icon(
                              key: const Key('reface-detect-video-faces'),
                              onPressed:
                                  _busy || caps == null || _videoTrim == null
                                  ? null
                                  : () {
                                      _targetScanTimer?.cancel();
                                      final generation =
                                          ++_targetScanGeneration;
                                      setState(() {
                                        _detectingTarget = true;
                                        _targetScanProgress = 0;
                                        _targetScanError = null;
                                        _error = null;
                                      });
                                      _detectVideoFaces(
                                        generation,
                                        _videoTrim!,
                                      );
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
                    ],
                  ),
                ),
                Step(
                  title: const Text('Source identity'),
                  isActive: _step == 1,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (available.contains('dfm'))
                        DropdownButtonFormField<String>(
                          key: ValueKey('identity-source-$_identityMode'),
                          isExpanded: true,
                          initialValue: _identityMode,
                          decoration: InputDecoration(
                            labelText: l10n.refaceIdentityMethod,
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'photos',
                              child: Text(l10n.refacePhotosIdentity),
                            ),
                            DropdownMenuItem(
                              value: 'dfm',
                              child: Text(l10n.refaceTrainedIdentity),
                            ),
                          ],
                          onChanged: (value) => _chooseIdentityMode(value!),
                        ),
                      if (_identityMode != 'dfm')
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
                      if (personModels.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          key: ValueKey('reface-reference-model-$_person'),
                          initialValue: referenceModel?.id ?? '',
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: l10n.refaceModelSource,
                          ),
                          items: [
                            DropdownMenuItem(
                              value: '',
                              child: Text(l10n.refacePhotosIdentity),
                            ),
                            for (final model in personModels)
                              DropdownMenuItem(
                                value: model.id,
                                child: Text(
                                  _referenceModelName(context, model),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: _busy
                              ? null
                              : (value) {
                                  setState(() {
                                    _referenceModelId = value == ''
                                        ? null
                                        : value;
                                    if (_referenceJob?.modelId !=
                                        _referenceModelId) {
                                      _referenceJob = null;
                                    }
                                    _error = null;
                                  });
                                },
                        ),
                        Text(l10n.refaceModelSourceHint),
                      ],
                      if (_identityMode != 'dfm' &&
                          referenceModel == null &&
                          _person != null &&
                          !_directSource &&
                          !_useImportedSource &&
                          caps != null &&
                          caps.engines.identityBundle) ...[
                        FilledButton.tonalIcon(
                          key: const Key('reface-build-gallery-profile'),
                          onPressed: _busy || buildingProfile || _sources.isEmpty
                              ? null
                              : () => _buildIdentity(caps, fromGallery: true),
                          icon: const Icon(Icons.collections_outlined),
                          label: Text(
                            buildingProfile
                                ? l10n.refaceProfileBuilding
                                : l10n.refaceBuildGalleryProfile,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy || buildingProfile
                              ? null
                              : () => _buildIdentity(caps, fromGallery: false),
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: Text(l10n.refaceBuildImportedProfile),
                        ),
                        SwitchListTile(
                          title: Text(l10n.refaceUseSavedProfile),
                          value: _useIdentityBundle,
                          onChanged: _busy || buildingProfile
                              ? null
                              : (value) => setState(() => _useIdentityBundle = value),
                        ),
                      ],
                      if (_identityMode != 'dfm' &&
                          referenceModel == null &&
                          _faces.isNotEmpty &&
                          caps != null &&
                          _faces.any(
                            (face) => face.modelId != caps.embeddingModelId,
                          ))
                        const Text(
                          'These source faces use a different embedding model from the connected PC. Select compatible source faces or a matching model.',
                        ),
                      if (_identityMode != 'dfm' && referenceModel == null) ...[
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
                              _referenceModelId = null;
                              _referenceJob = null;
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
                      if (referenceModel == null && _identityMode != 'dfm')
                        Text(l10n.sourceFacesHint),
                      if (_person != null &&
                          referenceModel == null &&
                          _identityMode != 'dfm') ...[
                        if (identitySets.isNotEmpty)
                          DropdownButtonFormField<int>(
                            isExpanded: true,
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
                      if (referenceModel == null && _identityMode != 'dfm')
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
                                      onChanged: _busy
                                          ? null
                                          : (_) => setState(() {
                                              _identitySet = null;
                                              _useIdentityBundle = false;
                                              if (!_sources.remove(face.id)) {
                                                _sources.add(face.id);
                                              }
                                            }),
                                    ),
                                    Text(
                                      '${(face.qualityScore * 100).round()}%',
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                Step(
                  title: const Text('Review / options'),
                  isActive: _step == 2,
                  content: Column(
                    children: [
                      if (available.isEmpty)
                        Text(l10n.refaceUnifiedUnavailable),
                      if (referenceModel != null)
                        Text(
                          '${l10n.refaceModelSource} · ${_referenceModelName(context, referenceModel)}',
                        ),
                      if (_identityMode != 'dfm')
                        RefaceOptionPicker(
                          fieldKey: const Key('reface-quality-profile'),
                          descriptionKey: const Key(
                            'reface-quality-description',
                          ),
                          label: l10n.refaceQualityProfile,
                          value: _qualityProfile,
                          options: qualityOptions(l10n, takes: _takes(caps)),
                          onChanged: _chooseQualityProfile,
                        ),
                      ExpansionTile(
                        title: const Text('Advanced options'),
                        children: [
                          if (_identityMode == 'dfm' && caps != null) ...[
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: _dfm,
                              decoration: InputDecoration(
                                labelText: l10n.dfmModel,
                              ),
                              items: [
                                for (final model in caps.engines.dfmModels)
                                  DropdownMenuItem(
                                    value: model,
                                    child: Text(model),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _dfm = value),
                            ),
                            Text(l10n.refaceDfmHint),
                          ] else ...[
                            Text(l10n.refaceRestorationIntro),
                            const SizedBox(height: 12),
                            RefaceOptionPicker(
                              fieldKey: ValueKey('restorer-$_qualityProfile'),
                              descriptionKey: const Key(
                                'reface-restorer-description',
                              ),
                              label: l10n.refaceRestorer,
                              value: _restorer,
                              options: restorationOptions(
                                l10n,
                                caps?.restorers ?? [],
                                caps?.refaceProfiles[_qualityProfile],
                              ),
                              onChanged: (value) =>
                                  setState(() => _restorer = value),
                            ),
                            DropdownButtonFormField<String>(
                              isExpanded: true,
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
                              onChanged: (value) =>
                                  setState(() => _preset = value!),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(l10n.useFaceParser),
                              value: _parser,
                              onChanged: (value) =>
                                  setState(() => _parser = value),
                            ),
                            if (caps?.engines.refaceGeometry ?? false)
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'Experimental 3D visibility mask',
                                ),
                                value: _use3dGeometry,
                                onChanged: (value) => setState(() => _use3dGeometry = value),
                              ),
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
                          Text(l10n.refaceSpeedNote),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.protectOcclusions),
                            value: _occluder,
                            onChanged: (v) => setState(() => _occluder = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        '${l10n.refaceTitle} · ${_video == null ? l10n.resultPhoto : l10n.resultVideo} · ${_identityMode == 'dfm' ? l10n.refaceTrainedIdentity : qualityOptions(l10n).firstWhere((option) => option.value == _qualityProfile).title}',
                      ),
                      Text(
                        _replaceAllFaces
                            ? l10n.refaceAllFaces
                            : l10n.selectedTargetFaces,
                      ),
                      if (_identityMode != 'dfm')
                        Text(
                          '${_useImportedSource ? l10n.refaceSourceMedia : (_personName ?? l10n.refaceIdentity)} · ${_useImportedSource && _importedSource != null ? _importedSources[_importedSource!].samples.length : _sources.length}',
                        ),
                      const SizedBox(height: 12),
                      Text(l10n.refaceReviewHint),
                      if (_preflight(
                            generated: referenceModel == null || caps == null
                                ? const []
                                : _generatedFaces(
                                    referenceModel,
                                    caps.embeddingModelId,
                                  ),
                          )
                          case final preflight?
                          when preflight.targetFaces > 0 ||
                              referenceModel == null) ...[
                        const SizedBox(height: 12),
                        RefacePreflightCard(preflight: preflight),
                      ],
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
