import '../shared/image_preview.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/api/dtos/analyze.dart';
import '../../domain/geometry/outline.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../library_providers.dart';
import '../../data/repositories/media_queries.dart';
import '../../data/repositories/artifact_context.dart';
import '../shared/media_target.dart';
import '../../studio_providers.dart';
import '../studio/studio_helpers.dart';
import '../shared/screen_layout.dart';
import '../settings/background_screen.dart';

class RestyleScreen extends ConsumerStatefulWidget {
  const RestyleScreen({super.key, this.targetMediaId, this.targetDetectionId});
  final int? targetMediaId;
  final int? targetDetectionId;
  @override
  ConsumerState<RestyleScreen> createState() => _RestyleScreenState();
}

class _RestyleScreenState extends ConsumerState<RestyleScreen> {
  final _prompt = TextEditingController(),
      _negative = TextEditingController(),
      _seed = TextEditingController(text: '-1');
  Uint8List? _photo;
  AnalyzeImageResponse? _analysis;
  MediaDetection? _contextTarget;
  int? _contextMediaId;
  String? _contextAssetId;
  final _references = <Uint8List>[];
  var _busy = false, _refine = true;
  var _face = 0;
  var _strength = .6, _padding = .15;
  var _steps = 26;
  String? _error;
  bool _initialized = false;
  @override
  void initState() {
    super.initState();
    if (widget.targetMediaId != null) {
      Future<void>.microtask(_loadContextTarget);
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
      if (source.isVideo) {
        throw const FormatException('Restyle requires a photo.');
      }
      _contextTarget = source.target;
      _contextMediaId = source.media.id;
      _contextAssetId = source.media.assetId;
      await _setPhoto(source.photoBytes!, target: source.target);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _detectCurrent() async {
    final photo = _photo;
    if (photo == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _setPhoto(photo, target: _contextTarget);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPhoto(Uint8List bytes, {MediaDetection? target}) async {
    if (!mounted) return;
    setState(() {
      _photo = bytes;
      _analysis = null;
      _face = -1;
    });
    final api = ref.read(mobileApiProvider);
    if (api == null) return;
    final result = await api.analyzeImage(
      bytes,
      options: const AnalyzeOptions(detectBodies: false, minQuality: 0),
    );
    if (!mounted) return;
    final matched = matchTargetFace(result, target);
    setState(() {
      _analysis = result;
      _face = target == null && result.faces.length == 1 ? 0 : (matched ?? -1);
      if (target != null && matched == null) {
        _error = 'Select the target person in this photo.';
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final l = AppLocalizations.of(context);
      _prompt.text = l.restyleDefaultPrompt;
      _negative.text = l.restyleNegativeDefault;
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _prompt.dispose();
    _negative.dispose();
    _seed.dispose();
    super.dispose();
  }

  Future<void> _pick({bool reference = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await ref.read(photoPickerProvider).pickPhoto();
      if (bytes == null) return;
      if (reference) {
        if (mounted) setState(() => _references.add(bytes));
        return;
      }
      _contextTarget = null;
      _contextMediaId = null;
      _contextAssetId = null;
      await _setPhoto(bytes);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  BBox? get _protected {
    final result = _analysis;
    if (result == null || _face < 0 || _face >= result.faces.length) {
      return null;
    }
    final b = result.faces[_face].bbox;
    final x = (b.x - b.w * _padding).clamp(0, result.imageW.toDouble());
    final y = (b.y - b.h * _padding).clamp(0, result.imageH.toDouble());
    final right = (b.x + b.w * (1 + _padding)).clamp(
      x,
      result.imageW.toDouble(),
    );
    final bottom = (b.y + b.h * (1 + _padding)).clamp(
      y,
      result.imageH.toDouble(),
    );
    return BBox(
      x: x.toDouble(),
      y: y.toDouble(),
      w: (right - x).toDouble(),
      h: (bottom - y).toDouble(),
    );
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final caps = studioCapabilities(ref.read(serverStatusProvider).value);
    if (_photo == null || _analysis == null || caps == null) return;
    if (_prompt.text.trim().isEmpty) {
      setState(() => _error = l.promptRequired);
      return;
    }
    final seed = int.tryParse(_seed.text.trim());
    if (seed == null || seed < -1 || seed > 2147483647) {
      setState(() => _error = l.invalidForm);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final temporary = <File>[];
    try {
      await prepareBackgroundForWork(context, ref);
      if (!mounted) return;
      final image = await privatePickedPhoto(ref, _photo!);
      temporary.add(image);
      for (final bytes in _references) {
        temporary.add(await privatePickedPhoto(ref, bytes));
      }
      final matchedTarget = _analysis == null
          ? null
          : matchTargetFace(_analysis!, _contextTarget);
      final selectedContext = matchedTarget != null && matchedTarget == _face
          ? _contextTarget
          : null;
      final id = await ref
          .read(studioRepositoryProvider)
          .enqueueInputs(
            serverId: caps.serverId,
            type: 'undress_image',
            context: ArtifactContext(
              mediaId: _contextMediaId,
              assetId: _contextAssetId,
              detectionId: selectedContext?.id,
              targetPersonId: selectedContext?.personId,
            ),
            params: {
              'prompt': _prompt.text.trim(),
              'negative_prompt': _negative.text.trim(),
              'seed': seed,
              'strength': _strength,
              'steps': _steps,
              'refine': _refine && caps.engines.restyleRefine,
              if (_protected != null) 'face_bbox': _protected!.toJson(),
            },
            inputs: {
              'image': [image],
              if (temporary.length > 1) 'refs': temporary.skip(1).toList(),
            },
          );
      ref.read(jobTrackerProvider).start();
      if (mounted) context.pushReplacement('${Routes.jobs}/$id');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      for (final f in temporary) {
        if (await f.exists()) await f.delete();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final caps = studioCapabilities(ref.watch(serverStatusProvider).value);
    final box = _protected;
    return Scaffold(
      appBar: AppBar(title: Text(l.restyleTitle)),
      bottomNavigationBar: StickyActionBar(
        child: FilledButton(
          key: const Key('restyle-submit'),
          onPressed:
              _busy ||
                  _analysis == null ||
                  (_analysis!.faces.length > 1 && _face < 0) ||
                  caps?.engines.undress != true
              ? null
              : _submit,
          child: Text(l.restyleCreate),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ScreenIntro(title: l.studioRestyleAction, body: l.restyleHint),
          if (caps == null)
            Text(l.studioNeedsPc)
          else if (!caps.engines.undress)
            Text(l.engineUnavailable),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_busy) const LinearProgressIndicator(),
          OutlinedButton(
            key: const Key('restyle-photo'),
            onPressed: _busy || caps == null ? null : () => _pick(),
            child: Text(l.chooseTargetPhoto),
          ),
          if (_photo != null && _analysis == null && caps != null)
            TextButton(
              onPressed: _busy ? null : _detectCurrent,
              child: const Text('Detect target faces'),
            ),
          if (_photo != null && _analysis != null)
            ImageExpand(
              source: ImagePreviewSource.bytes(_photo!),
              child: AspectRatio(
                aspectRatio: _analysis!.imageW / _analysis!.imageH,
                child: LayoutBuilder(
                  builder: (context, c) => Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(_photo!, fit: BoxFit.fill),
                      if (box != null)
                        Positioned(
                          left: box.x / _analysis!.imageW * c.maxWidth,
                          top: box.y / _analysis!.imageH * c.maxHeight,
                          width: box.w / _analysis!.imageW * c.maxWidth,
                          height: box.h / _analysis!.imageH * c.maxHeight,
                          child: CustomPaint(
                            painter: DetectionBoxPainter(
                              isFace: true,
                              outline:
                                  _analysis != null &&
                                      _analysis!.faces.isNotEmpty &&
                                      _face >= 0 &&
                                      _face < _analysis!.faces.length &&
                                      _analysis!.faces[_face].outline != null
                                  ? [
                                      for (final p
                                          in _analysis!.faces[_face].outline!)
                                        Offset(
                                          (p.dx - box.x) / box.w,
                                          (p.dy - box.y) / box.h,
                                        ),
                                    ]
                                  : null,
                              fillColor: Colors.greenAccent.withValues(
                                alpha: 0.15,
                              ),
                              borderColor: Colors.greenAccent,
                              borderWidth: 3,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (_analysis?.faces.isNotEmpty == true) ...[
            if (_face < 0) const Text('Select the target person.'),
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: _face < 0 ? null : _face,
              decoration: InputDecoration(labelText: l.restyleFace),
              items: [
                for (var i = 0; i < _analysis!.faces.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(l.analyzeFaceTitle(i + 1)),
                  ),
              ],
              onChanged: (v) => setState(() => _face = v!),
            ),
            Text(l.restylePadding),
            Slider(
              value: _padding,
              min: 0,
              max: .5,
              onChanged: (v) => setState(() => _padding = v),
            ),
          ],
          TextField(
            key: const Key('restyle-prompt'),
            controller: _prompt,
            minLines: 3,
            maxLines: 6,
            maxLength: 4000,
            decoration: InputDecoration(labelText: l.restylePrompt),
          ),
          Text(l.restyleStrength),
          Slider(
            value: _strength,
            min: .05,
            max: 1,
            label: _strength.toStringAsFixed(2),
            onChanged: (v) => setState(() => _strength = v),
          ),
          ExpansionTile(
            title: Text(l.advancedOptions),
            children: [
              TextField(
                controller: _negative,
                maxLines: 4,
                maxLength: 4000,
                decoration: InputDecoration(labelText: l.restyleNegative),
              ),
              TextField(
                controller: _seed,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                decoration: InputDecoration(labelText: l.seed),
              ),
              Text('${l.steps}: $_steps'),
              Slider(
                value: _steps.toDouble(),
                min: 5,
                max: 80,
                divisions: 75,
                onChanged: (v) => setState(() => _steps = v.round()),
              ),
              SwitchListTile(
                title: Text(l.refineOutput),
                subtitle: caps?.engines.restyleRefine == false
                    ? Text(l.restyleRefineUnavailable)
                    : null,
                value: _refine && (caps?.engines.restyleRefine ?? false),
                onChanged: caps?.engines.restyleRefine != true
                    ? null
                    : (v) => setState(() => _refine = v),
              ),
            ],
          ),
          Text('${l.restyleReferences} (${_references.length}/4)'),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < _references.length; i++)
                InputChip(
                  avatar: PreviewImage.memory(_references[i]),
                  label: Text('${i + 1}'),
                  onDeleted: () => setState(() => _references.removeAt(i)),
                ),
            ],
          ),
          OutlinedButton(
            onPressed: _busy || _references.length >= 4
                ? null
                : () => _pick(reference: true),
            child: Text(l.addReference),
          ),
          const SizedBox(height: 16),
          Text(l.privateResultsHint),
        ],
      ),
    );
  }
}
