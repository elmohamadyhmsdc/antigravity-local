import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/artifact_context.dart';
import '../../data/repositories/media_queries.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../../studio_providers.dart';
import '../library/media_grid.dart';
import '../privacy/app_lock.dart';
import '../shared/person_picker.dart';
import '../studio/studio_helpers.dart';
import 'mask_builder.dart';
import 'reference_crop.dart';
import 'selection_model.dart';
import 'smart_selector.dart';

class PhotoEditScreen extends ConsumerStatefulWidget {
  const PhotoEditScreen({super.key, this.mediaId, this.initialPhotoBytes});

  final int? mediaId;
  final Uint8List? initialPhotoBytes;

  @override
  ConsumerState<PhotoEditScreen> createState() => _PhotoEditScreenState();
}

class _PhotoEditScreenState extends ConsumerState<PhotoEditScreen> {
  static const _maxReferences = 3;
  final _promptController = TextEditingController();
  final _selectionModel = SelectionModel();

  Uint8List? _photoBytes;
  ui.Image? _decodedPhoto;
  SmartImageThumb? _smartThumb;
  int? _contextMediaId;
  String? _contextAssetId;

  var _activeTool = SelectionTool.brush;
  var _operation = PhotoEditOperation.remove;
  var _selectedModel = PhotoEditModel.realisticVision;
  var _guided = false;
  var _autoBody = false;
  var _keepBodyShape = false;
  bool get _usesAutoBody =>
      _operation == PhotoEditOperation.replace && _autoBody;
  final _references = <Uint8List>[];
  var _brushRadius = 0.035;
  var _smartTolerance = 0.22;
  var _strength = 0.85;
  var _busy = false;
  String? _pendingJob;
  var _pausing = false;
  var _progressText = '';
  double _progress = 0.0;
  String? _error;

  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _baseScale = 1.0;
  Offset _baseOffset = Offset.zero;
  Offset _focalStart = Offset.zero;

  Uint8List? _resultBytes;
  File? _resultFile;
  var _showOriginal = false;
  var _savedToGallery = false;

  List<Offset> _activeStrokePoints = [];

  @override
  void initState() {
    super.initState();
    _selectionModel.addListener(_onSelectionChanged);
    if (widget.initialPhotoBytes != null) {
      _setPhoto(widget.initialPhotoBytes!);
    } else if (widget.mediaId != null) {
      Future<void>.microtask(_loadMediaPhoto);
    }
  }

  @override
  void dispose() {
    _selectionModel.removeListener(_onSelectionChanged);
    _selectionModel.dispose();
    _promptController.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadMediaPhoto() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final source = await ref
          .read(mediaActionSourceProvider)
          .resolve(widget.mediaId!);
      if (source.isVideo) {
        throw const FormatException('AI Photo Edit requires a still photo.');
      }
      final bytes = source.photoBytes;
      if (bytes == null) {
        throw const FormatException('Could not read photo bytes.');
      }
      _contextMediaId = source.media.id;
      _contextAssetId = source.media.assetId;
      await _setPhoto(bytes);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPhoto(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final thumb = await SmartSelector.createThumbnail(frame.image);
      if (!mounted) return;
      setState(() {
        _photoBytes = bytes;
        _decodedPhoto = frame.image;
        _smartThumb = thumb;
        _resultBytes = null;
        _resultFile = null;
        _showOriginal = false;
        _savedToGallery = false;
        _selectionModel.clear();
        _scale = 1.0;
        _offset = Offset.zero;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to decode image: $e');
    }
  }

  Future<void> _submit() async {
    final photo = _photoBytes;
    final decoded = _decodedPhoto;
    final caps = studioCapabilities(ref.read(serverStatusProvider).value);

    if (photo == null || decoded == null) return;
    if (caps == null) {
      setState(() => _error = 'PC GPU server is offline or not paired.');
      return;
    }
    final automatic = _usesAutoBody;
    final keepShape =
        _operation == PhotoEditOperation.replace &&
        (_keepBodyShape || automatic);
    if (automatic && !caps.engines.photoEditAutoBody ||
        keepShape && !caps.engines.photoEditBodyShape) {
      setState(
        () => _error = 'This PC does not have the body editing models ready.',
      );
      return;
    }
    if (!automatic && !_selectionModel.hasSelection) {
      setState(
        () => _error = 'Select the body area, clothing, or object to edit.',
      );
      return;
    }
    if (_operation == PhotoEditOperation.replace &&
        (!_guided || automatic) &&
        _promptController.text.trim().isEmpty) {
      setState(
        () => _error = 'Please enter a description for the replacement.',
      );
      return;
    }
    final operation = _operation;
    final guided = operation == PhotoEditOperation.replace && _guided;
    final model = guided ? PhotoEditModel.realisticVision : _selectedModel;
    final references = guided
        ? List<Uint8List>.of(_references)
        : const <Uint8List>[];
    if (guided && (!caps.engines.photoEditReference || references.isEmpty)) {
      setState(
        () => _error = caps.engines.photoEditReference
            ? 'Add at least one reference photo or choose Text only.'
            : 'Photo guidance is unavailable on this PC.',
      );
      return;
    }
    if (!guided &&
        operation == PhotoEditOperation.replace &&
        !_availableModels(caps.photoEditModels).contains(model)) {
      setState(
        () => _error = 'That model is unavailable. Choose another model.',
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _progressText = 'Preparing mask...';
      _progress = 0.05;
    });

    final filesToClean = <File>[];
    try {
      // 1. Generate normalized PNG mask (capped to max 1024 for mobile memory safety)
      int targetW = decoded.width;
      int targetH = decoded.height;
      final maxDim = max(targetW, targetH);
      if (maxDim > 1024) {
        final scale = 1024.0 / maxDim;
        targetW = (targetW * scale).round();
        targetH = (targetH * scale).round();
      }

      final photoFile = await privatePickedPhoto(ref, photo);
      filesToClean.add(photoFile);
      File? maskFile;
      if (!automatic) {
        final maskBytes = await MaskBuilder.buildMaskPng(
          _selectionModel,
          width: targetW,
          height: targetH,
        );
        final fileStore = ref.read(fileStoreProvider);
        final maskPath =
            'work/photo_edit/mask_${DateTime.now().microsecondsSinceEpoch}.png';
        await fileStore.write(maskPath, maskBytes);
        maskFile = fileStore.resolve(maskPath);
        filesToClean.add(maskFile);
      }
      final referenceFiles = <File>[];
      for (final bytes in references) {
        final file = await privatePickedPhoto(ref, bytes);
        referenceFiles.add(file);
        filesToClean.add(file);
      }
      if (!mounted) return;

      setState(() {
        _progressText = 'Uploading to PC server...';
        _progress = 0.15;
      });

      final operationStr = operation == PhotoEditOperation.remove
          ? 'remove'
          : 'replace';
      final promptStr = _promptController.text.trim();

      final jobId = await ref
          .read(studioRepositoryProvider)
          .enqueueInputs(
            serverId: caps.serverId,
            type: 'edit_image',
            context: ArtifactContext(
              mediaId: _contextMediaId,
              assetId: _contextAssetId,
            ),
            params: {
              'operation': operationStr,
              'instruction': promptStr,
              'steps': 26,
              if (!automatic) 'mask_normalized': true,
              if (automatic) 'auto_body': true,
              if (keepShape) 'preserve_body_shape': true,
              'strength': _strength,
              if (operation == PhotoEditOperation.replace) 'model': model.id,
            },
            inputs: {
              'image': [photoFile],
              if (maskFile != null) 'mask': [maskFile],
              if (referenceFiles.isNotEmpty) 'refs': referenceFiles,
            },
          );

      if (!mounted) return;
      setState(() => _pendingJob = jobId);
      ref.read(jobTrackerProvider).start();

      // Monitor job until completed or failed
      await _waitForJobCompletion(jobId);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      for (final f in filesToClean) {
        if (await f.exists()) await f.delete();
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _pendingJob = null;
        });
      }
    }
  }

  Future<void> _addReference({required bool fromPerson}) async {
    if (_references.length >= _maxReferences) return;
    try {
      Uint8List? bytes;
      if (fromPerson) {
        final choice = await pickPerson(
          context,
          allowNew: false,
          title: 'Choose the person',
        );
        final personId = choice?.personId;
        if (!mounted || personId == null) return;
        final photo = await showModalBottomSheet<MediaListItem>(
          context: context,
          useSafeArea: true,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) => FractionallySizedBox(
            heightFactor: .85,
            child: Column(
              children: [
                const ListTile(title: Text('Choose a photo of this person')),
                Expanded(
                  child: MediaGrid(
                    filter: MediaFilter(personId: personId, kind: 'photo'),
                    empty: const Center(
                      child: Text('No photos are assigned to this person.'),
                    ),
                    onSelect: (photo) => Navigator.of(context).pop(photo),
                  ),
                ),
              ],
            ),
          ),
        );
        if (!mounted || photo == null) return;
        final source = await ref
            .read(mediaActionSourceProvider)
            .resolve(photo.id, maxSide: 1280);
        bytes = source.photoBytes;
        if (bytes == null) {
          throw const FormatException(
            'This reference photo could not be opened.',
          );
        }
      } else {
        bytes = await ref.read(photoPickerProvider).pickPhoto();
      }
      if (!mounted || bytes == null) return;
      final crop = await choosePhotoEditReference(context, bytes);
      if (!mounted || crop == null) return;
      setState(() => _references.add(crop));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _pauseEdit() async {
    final id = _pendingJob;
    if (id == null || _pausing) return;
    setState(() => _pausing = true);
    try {
      final job = await ref.read(studioRepositoryProvider).job(id);
      if (job != null && mounted) {
        await ref.read(jobTrackerProvider).pause(job);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _pausing = false);
    }
  }

  Future<void> _waitForJobCompletion(String jobId) async {
    final repo = ref.read(studioRepositoryProvider);
    final files = ref.read(fileStoreProvider);

    while (mounted) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      final job = await repo.job(jobId);
      if (job == null) {
        throw const FormatException('This edit is no longer available.');
      }

      if (mounted) {
        setState(() {
          _progress = job.progress.clamp(0.15, 0.95);
          _progressText = job.status == 'running'
              ? 'Processing AI edit (${(job.progress * 100).round()}%)...'
              : '${job.status}...';
        });
      }

      if (job.status == 'completed') {
        final resultRow = await (repo.db.select(
          repo.db.results,
        )..where((r) => r.id.equals(jobId))).getSingleOrNull();
        final path = resultRow?.path;
        if (path != null) {
          final resFile = files.resolve(path);
          if (await resFile.exists()) {
            final resBytes = await resFile.readAsBytes();
            if (mounted) {
              setState(() {
                _resultBytes = resBytes;
                _resultFile = resFile;
                _showOriginal = false;
                _savedToGallery = false;
                _progress = 1.0;
                _progressText = 'Done';
              });
            }
            return;
          }
        }
      } else if (job.status == 'paused') {
        if (_pausing) continue;
        if (job.error?.isNotEmpty == true) throw Exception(job.error);
        return;
      } else if (job.status == 'failed' || job.status == 'lost') {
        throw Exception(
          job.error != null && job.error!.isNotEmpty
              ? job.error!
              : 'AI edit failed on server.',
        );
      }
    }
  }

  Future<void> _saveCopy() async {
    final file = _resultFile;
    if (file == null || _savedToGallery) return;

    try {
      final saved = await ref
          .read(privacyServiceProvider)
          .exportMedia(file, 'image/png');
      if (mounted) {
        setState(() => _savedToGallery = saved);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saved ? 'Saved a copy to gallery' : 'Could not save copy',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photoBytes;
    final decoded = _decodedPhoto;
    final result = _resultBytes;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Photo Edit'),
        actions: [
          if (result != null && !_busy)
            TextButton.icon(
              key: const Key('save-copy-button'),
              onPressed: _saveCopy,
              icon: Icon(_savedToGallery ? Icons.check : Icons.save_alt),
              label: Text(_savedToGallery ? 'Saved' : 'Save Copy'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_error != null)
              Container(
                color: Theme.of(context).colorScheme.errorContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _error = null),
                    ),
                  ],
                ),
              ),

            // Canvas Area
            if (!keyboardVisible)
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (photo == null || decoded == null)
                      const Center(child: CircularProgressIndicator())
                    else if (result != null && !_showOriginal)
                      Image.memory(result, fit: BoxFit.contain)
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return _buildInteractiveCanvas(
                            constraints.maxWidth,
                            constraints.maxHeight,
                            decoded,
                          );
                        },
                      ),

                    // Progress Overlay
                    if (_busy)
                      Container(
                        color: Colors.black54,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              value: _progress > 0 ? _progress : null,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _progressText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                            if (_pendingJob != null)
                              FilledButton.tonal(
                                onPressed: _pausing ? null : _pauseEdit,
                                child: const Text('Pause edit'),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

            // Bottom Controls
            if (result != null)
              _buildResultControls()
            else
              Flexible(
                key: const ValueKey('photo-edit-controls'),
                flex: keyboardVisible ? 1 : 0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .70,
                  ),
                  child: SingleChildScrollView(
                    reverse: keyboardVisible,
                    child: _buildEditorControls(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _performSmartSelect(Offset norm) {
    final thumb = _smartThumb;
    List<Rect> rects = [];
    if (thumb != null) {
      rects = SmartSelector.floodSelect(
        rgbaBytes: thumb.rgbaBytes,
        width: thumb.width,
        height: thumb.height,
        seedNorm: norm,
        tolerance: _smartTolerance,
      );
    }

    if (rects.isNotEmpty) {
      _selectionModel.addStroke(
        SelectionStroke(
          points: [norm],
          radius: _brushRadius,
          filledRects: rects,
          isEraser: false,
        ),
      );
    } else {
      _selectionModel.addStroke(
        SelectionStroke(
          points: [norm],
          radius: _brushRadius * 1.5,
          isEraser: false,
        ),
      );
    }
  }

  Widget _buildInteractiveCanvas(
    double viewWidth,
    double viewHeight,
    ui.Image image,
  ) {
    final imageAspect = image.width / image.height;
    final viewAspect = viewWidth / viewHeight;

    double drawW, drawH, offsetX, offsetY;
    if (viewAspect > imageAspect) {
      drawH = viewHeight;
      drawW = viewHeight * imageAspect;
      offsetX = (viewWidth - drawW) / 2;
      offsetY = 0;
    } else {
      drawW = viewWidth;
      drawH = viewWidth / imageAspect;
      offsetX = 0;
      offsetY = (viewHeight - drawH) / 2;
    }

    final fittedRect = Rect.fromLTWH(offsetX, offsetY, drawW, drawH);

    Offset? toNormalized(Offset screenPos) {
      final canvasX = (screenPos.dx - _offset.dx) / _scale;
      final canvasY = (screenPos.dy - _offset.dy) / _scale;
      if (!fittedRect.contains(Offset(canvasX, canvasY))) return null;
      final nx = ((canvasX - fittedRect.left) / fittedRect.width).clamp(
        0.0,
        1.0,
      );
      final ny = ((canvasY - fittedRect.top) / fittedRect.height).clamp(
        0.0,
        1.0,
      );
      return Offset(nx, ny);
    }

    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            if (!_usesAutoBody && _activeTool == SelectionTool.smartTap) {
              final norm = toNormalized(details.localPosition);
              if (norm != null) {
                _performSmartSelect(norm);
              }
            }
          },
          onScaleStart: (details) {
            _baseScale = _scale;
            _baseOffset = _offset;
            _focalStart = details.localFocalPoint;

            if (!_usesAutoBody &&
                details.pointerCount == 1 &&
                (_activeTool == SelectionTool.brush ||
                    _activeTool == SelectionTool.eraser)) {
              final norm = toNormalized(details.localFocalPoint);
              if (norm != null) {
                setState(() => _activeStrokePoints = [norm]);
              }
            }
          },
          onScaleUpdate: (details) {
            if (details.pointerCount >= 2 ||
                _activeTool == SelectionTool.move) {
              if (_activeStrokePoints.isNotEmpty) {
                setState(() => _activeStrokePoints = []);
              }
              final newScale = (_baseScale * details.scale).clamp(1.0, 8.0);
              final focal = details.localFocalPoint;
              Offset newOffset =
                  focal - (focal - _baseOffset) * (newScale / _baseScale);
              newOffset += (details.localFocalPoint - _focalStart);

              if (newScale <= 1.0) {
                newOffset = Offset.zero;
              }

              setState(() {
                _scale = newScale;
                _offset = newOffset;
              });
            } else if (details.pointerCount == 1 &&
                (_activeTool == SelectionTool.brush ||
                    _activeTool == SelectionTool.eraser)) {
              final norm = toNormalized(details.localFocalPoint);
              if (norm != null) {
                setState(() => _activeStrokePoints.add(norm));
              }
            }
          },
          onScaleEnd: (details) {
            if (_activeStrokePoints.isNotEmpty) {
              _selectionModel.addStroke(
                SelectionStroke(
                  points: List.of(_activeStrokePoints),
                  radius: _brushRadius,
                  isEraser: _activeTool == SelectionTool.eraser,
                ),
              );
              setState(() => _activeStrokePoints = []);
            }
            if (_scale <= 1.02) {
              setState(() {
                _scale = 1.0;
                _offset = Offset.zero;
              });
            }
          },
          child: CustomPaint(
            size: Size(viewWidth, viewHeight),
            painter: _CanvasPainter(
              image: image,
              fittedRect: fittedRect,
              scale: _scale,
              offset: _offset,
              model: _selectionModel,
              showSelection: !_usesAutoBody,
              activePoints: _activeStrokePoints,
              activeRadius: _brushRadius,
              isEraser: _activeTool == SelectionTool.eraser,
            ),
          ),
        ),

        // Floating Reset Zoom Button when zoomed in
        if (_scale > 1.05 || _offset != Offset.zero)
          Positioned(
            top: 16,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: const Key('reset-zoom-button'),
                onTap: () {
                  setState(() {
                    _scale = 1.0;
                    _offset = Offset.zero;
                  });
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24, width: 0.8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.zoom_out_map,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${(_scale * 100).round()}% (1.0x)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<PhotoEditModel> _availableModels(List<String>? advertised) => [
    for (final model in PhotoEditModel.values)
      if (advertised?.contains(model.id) ?? (model != PhotoEditModel.sdxlGguf))
        model,
  ];

  Widget _buildEditorControls() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final caps = _operation == PhotoEditOperation.replace
        ? studioCapabilities(ref.watch(serverStatusProvider).value)
        : null;
    final models = _availableModels(caps?.photoEditModels);
    final canGuide =
        caps?.engines.photoEdit == true &&
        caps?.engines.photoEditReference == true;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow.withValues(alpha: 0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.7),
                width: 0.8,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Operations Row (Segmented Style)
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant, width: 0.8),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        key: const Key('op-remove'),
                        avatar: const Icon(Icons.auto_fix_high, size: 16),
                        label: const Center(child: Text('Remove / إزالة')),
                        selected: _operation == PhotoEditOperation.remove,
                        showCheckmark: false,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                        side: BorderSide.none,
                        onSelected: (v) {
                          if (v) {
                            setState(
                              () => _operation = PhotoEditOperation.remove,
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: ChoiceChip(
                        key: const Key('op-replace'),
                        avatar: const Icon(Icons.psychology_outlined, size: 16),
                        label: const Center(child: Text('Replace / استبدال')),
                        selected: _operation == PhotoEditOperation.replace,
                        showCheckmark: false,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                        side: BorderSide.none,
                        onSelected: (v) {
                          if (v) {
                            setState(
                              () => _operation = PhotoEditOperation.replace,
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Tools Row: Brush, Eraser, Smart Tap, Move
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      key: const Key('tool-brush'),
                      avatar: const Icon(Icons.brush, size: 17),
                      label: const Text('Brush'),
                      selected: _activeTool == SelectionTool.brush,
                      onSelected: (_) =>
                          setState(() => _activeTool = SelectionTool.brush),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      key: const Key('tool-eraser'),
                      avatar: const Icon(Icons.auto_fix_normal, size: 17),
                      label: const Text('Eraser'),
                      selected: _activeTool == SelectionTool.eraser,
                      onSelected: (_) =>
                          setState(() => _activeTool = SelectionTool.eraser),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      key: const Key('tool-smart-tap'),
                      avatar: const Icon(Icons.touch_app, size: 17),
                      label: const Text('Smart Tap'),
                      selected: _activeTool == SelectionTool.smartTap,
                      onSelected: (_) =>
                          setState(() => _activeTool = SelectionTool.smartTap),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      key: const Key('tool-move'),
                      avatar: const Icon(Icons.pan_tool_outlined, size: 17),
                      label: const Text('Move & Zoom'),
                      selected: _activeTool == SelectionTool.move,
                      onSelected: (_) =>
                          setState(() => _activeTool = SelectionTool.move),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Brush Size / Tolerance Slider + History Controls
              Row(
                children: [
                  if (_activeTool == SelectionTool.smartTap) ...[
                    Icon(Icons.tune, size: 18, color: scheme.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Tolerance / الحساسية: ${(_smartTolerance * 100).round()}%',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: scheme.primary,
                            ),
                          ),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                            ),
                            child: Slider(
                              key: const Key('smart-tolerance-slider'),
                              value: _smartTolerance,
                              min: 0.08,
                              max: 0.45,
                              divisions: 15,
                              onChanged: (v) =>
                                  setState(() => _smartTolerance = v),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_activeTool != SelectionTool.move) ...[
                    Icon(
                      Icons.line_weight,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                        ),
                        child: Slider(
                          value: _brushRadius,
                          min: 0.008,
                          max: 0.12,
                          onChanged: (v) => setState(() => _brushRadius = v),
                        ),
                      ),
                    ),
                  ] else
                    Expanded(
                      child: Text(
                        'Pinch to zoom, drag to pan the image.',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  IconButton.filledTonal(
                    key: const Key('edit-undo'),
                    icon: const Icon(Icons.undo, size: 18),
                    tooltip: 'Undo',
                    onPressed: _selectionModel.canUndo
                        ? _selectionModel.undo
                        : null,
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    key: const Key('edit-redo'),
                    icon: const Icon(Icons.redo, size: 18),
                    tooltip: 'Redo',
                    onPressed: _selectionModel.canRedo
                        ? _selectionModel.redo
                        : null,
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    key: const Key('edit-clear'),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Clear',
                    onPressed: _selectionModel.canUndo
                        ? _selectionModel.clear
                        : null,
                  ),
                ],
              ),

              // Prompt TextField if Replace
              if (_operation == PhotoEditOperation.replace) ...[
                const SizedBox(height: 8),
                if (caps?.engines.photoEditAutoBody == true ||
                    caps?.engines.photoEditBodyShape == true ||
                    _autoBody ||
                    _keepBodyShape)
                  Wrap(
                    spacing: 6,
                    children: [
                      if (caps?.engines.photoEditAutoBody == true || _autoBody)
                        FilterChip(
                          key: const Key('auto-clothing-selection'),
                          label: const Text('Auto-select clothing'),
                          selected: _autoBody,
                          onSelected: _busy
                              ? null
                              : (value) => setState(() => _autoBody = value),
                        ),
                      if (caps?.engines.photoEditBodyShape == true ||
                          _keepBodyShape)
                        FilterChip(
                          key: const Key('keep-body-outline'),
                          label: const Text('Keep body outline'),
                          selected: _keepBodyShape || _autoBody,
                          onSelected: _busy || _autoBody
                              ? null
                              : (value) =>
                                    setState(() => _keepBodyShape = value),
                        ),
                    ],
                  ),
                if (canGuide || _guided)
                  Row(
                    spacing: 6,
                    children: [
                      ChoiceChip(
                        key: const Key('text-only-edit'),
                        label: const Text('Text only'),
                        selected: !_guided,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _guided = false),
                      ),
                      ChoiceChip(
                        key: const Key('photo-guided-edit'),
                        label: const Text('Photo guide'),
                        selected: _guided,
                        onSelected: _busy || !canGuide
                            ? null
                            : (_) => setState(() => _guided = true),
                      ),
                    ],
                  ),
                if (_guided)
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var index = 0; index < _references.length; index++)
                        InputChip(
                          label: Text('Photo ${index + 1}'),
                          avatar: CircleAvatar(
                            backgroundImage: MemoryImage(_references[index]),
                          ),
                          onDeleted: _busy
                              ? null
                              : () =>
                                    setState(() => _references.removeAt(index)),
                        ),
                      if (_references.length < _maxReferences) ...[
                        ActionChip(
                          key: const Key('reference-from-person'),
                          avatar: const Icon(Icons.person_search, size: 16),
                          label: const Text('From person'),
                          onPressed: _busy || !canGuide
                              ? null
                              : () => _addReference(fromPerson: true),
                        ),
                        ActionChip(
                          key: const Key('reference-from-gallery'),
                          avatar: const Icon(
                            Icons.photo_library_outlined,
                            size: 16,
                          ),
                          label: const Text('From gallery'),
                          onPressed: _busy || !canGuide
                              ? null
                              : () => _addReference(fromPerson: false),
                        ),
                      ],
                    ],
                  )
                else if (models.isNotEmpty)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = max(
                        116.0,
                        (constraints.maxWidth - 4 * (models.length - 1)) /
                            models.length,
                      );
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          spacing: 4,
                          children: [
                            for (final model in models)
                              SizedBox(
                                width: width,
                                child: ChoiceChip(
                                  key: Key(
                                    'model-${model.id.replaceAll('_', '-')}',
                                  ),
                                  label: Text(
                                    model.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  selected: _selectedModel == model,
                                  showCheckmark: false,
                                  onSelected: _busy
                                      ? null
                                      : (selected) {
                                          if (selected) {
                                            setState(
                                              () => _selectedModel = model,
                                            );
                                          }
                                        },
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                if (!_guided && models.contains(_selectedModel))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
                    child: Text(
                      _selectedModel.description,
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                TextField(
                  key: const Key('instruction-input'),
                  controller: _promptController,
                  decoration: InputDecoration(
                    labelText: _guided && !_autoBody
                        ? 'Optional description / وصف اختياري'
                        : 'Prompt / الوصف (عربي أو إنجليزي)',
                    hintText: _autoBody
                        ? 'e.g. بدّل القميص والبنطلون لبدلة كحلي'
                        : 'e.g. جاكيت جلد أسود / black leather jacket',
                    prefixIcon: Icon(
                      Icons.auto_awesome,
                      size: 18,
                      color: scheme.primary,
                    ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ActionChip(
                        avatar: const Text(
                          '👔',
                          style: TextStyle(fontSize: 13),
                        ),
                        label: const Text('بدلة كلاسيك كحلي'),
                        onPressed: () => setState(
                          () => _promptController.text = 'بدلة كلاسيك كحلي',
                        ),
                      ),
                      const SizedBox(width: 5),
                      ActionChip(
                        avatar: const Text(
                          '👗',
                          style: TextStyle(fontSize: 13),
                        ),
                        label: const Text('فستان سواريه أحمر'),
                        onPressed: () => setState(
                          () => _promptController.text = 'فستان سواريه أحمر',
                        ),
                      ),
                      const SizedBox(width: 5),
                      ActionChip(
                        avatar: const Text(
                          '🧥',
                          style: TextStyle(fontSize: 13),
                        ),
                        label: const Text('جاكيت جلد أسود'),
                        onPressed: () => setState(
                          () => _promptController.text = 'جاكيت جلد أسود',
                        ),
                      ),
                      const SizedBox(width: 5),
                      ActionChip(
                        avatar: const Text(
                          '👕',
                          style: TextStyle(fontSize: 13),
                        ),
                        label: const Text('قميص كاجوال أبيض'),
                        onPressed: () => setState(
                          () => _promptController.text = 'قميص كاجوال أبيض',
                        ),
                      ),
                      const SizedBox(width: 5),
                      ActionChip(
                        avatar: const Text('⌚', style: TextStyle(fontSize: 13)),
                        label: const Text('ساعة يد فخمة'),
                        onPressed: () => setState(
                          () => _promptController.text = 'ساعة يد فخمة',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.accessibility_new,
                      size: 16,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Change Strength / قوة التغيير: ${(_strength * 100).round()}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _strength >= 0.80 ? 'واضح وقوي' : 'طبيعي معتدل',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                  ),
                  child: Slider(
                    key: const Key('strength-slider'),
                    value: _strength,
                    min: 0.60,
                    max: 1.0,
                    divisions: 8,
                    onChanged: (v) => setState(() => _strength = v),
                  ),
                ),
              ],

              const SizedBox(height: 10),

              // Generate Action Button
              FilledButton.icon(
                key: const Key('generate-button'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed:
                    (!_busy && (_usesAutoBody || _selectionModel.hasSelection))
                    ? _submit
                    : null,
                icon: const Icon(Icons.auto_fix_high, size: 20),
                label: Text(
                  _operation == PhotoEditOperation.remove
                      ? 'Remove Selection / مسح المحدد'
                      : 'Replace with Prompt / استبدال بالوصف',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultControls() {
    final scheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow.withValues(alpha: 0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.7),
                width: 0.8,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('toggle-before-after'),
                  onPressed: () =>
                      setState(() => _showOriginal = !_showOriginal),
                  icon: Icon(
                    _showOriginal ? Icons.visibility : Icons.visibility_off,
                    size: 18,
                  ),
                  label: Text(_showOriginal ? 'Show Result' : 'Show Before'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  key: const Key('edit-again-button'),
                  onPressed: () {
                    setState(() {
                      _resultBytes = null;
                      _resultFile = null;
                    });
                  },
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Edit Again'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter({
    required this.image,
    required this.fittedRect,
    required this.scale,
    required this.offset,
    required this.model,
    required this.showSelection,
    required this.activePoints,
    required this.activeRadius,
    required this.isEraser,
  }) : super(repaint: model);

  final ui.Image image;
  final Rect fittedRect;
  final double scale;
  final Offset offset;
  final SelectionModel model;
  final bool showSelection;
  final List<Offset> activePoints;
  final double activeRadius;
  final bool isEraser;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale, scale);

    // 1. Draw the photo inside fittedRect
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(
      image,
      src,
      fittedRect,
      Paint()..filterQuality = FilterQuality.medium,
    );
    if (!showSelection) {
      canvas.restore();
      return;
    }

    // 2. Draw mask overlay
    canvas.saveLayer(null, Paint());

    final maskPaint = Paint()
      ..color =
          const Color(0x77A855F7) // Semi-transparent purple
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final maskFill = Paint()
      ..color = const Color(0x77A855F7)
      ..style = PaintingStyle.fill;

    final eraserPaint = Paint()
      ..blendMode = BlendMode.clear
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final eraserFill = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.fill;

    void drawStroke(List<Offset> points, double radius, bool eraser) {
      if (points.isEmpty) return;
      final pxRadius = radius * fittedRect.width;
      final p = eraser
          ? (eraserPaint..strokeWidth = pxRadius * 2)
          : (maskPaint..strokeWidth = pxRadius * 2);

      if (points.length == 1) {
        final pt = Offset(
          fittedRect.left + points[0].dx * fittedRect.width,
          fittedRect.top + points[0].dy * fittedRect.height,
        );
        canvas.drawCircle(pt, pxRadius, eraser ? eraserFill : maskFill);
      } else {
        final path = Path();
        final first = Offset(
          fittedRect.left + points[0].dx * fittedRect.width,
          fittedRect.top + points[0].dy * fittedRect.height,
        );
        path.moveTo(first.dx, first.dy);
        for (var i = 1; i < points.length; i++) {
          final pt = Offset(
            fittedRect.left + points[i].dx * fittedRect.width,
            fittedRect.top + points[i].dy * fittedRect.height,
          );
          path.lineTo(pt.dx, pt.dy);
        }
        canvas.drawPath(path, p);
      }
    }

    for (final stroke in model.strokes) {
      if (stroke.filledRects != null && stroke.filledRects!.isNotEmpty) {
        final p = stroke.isEraser ? eraserFill : maskFill;
        for (final r in stroke.filledRects!) {
          canvas.drawRect(
            Rect.fromLTRB(
              fittedRect.left + r.left * fittedRect.width,
              fittedRect.top + r.top * fittedRect.height,
              fittedRect.left + r.right * fittedRect.width,
              fittedRect.top + r.bottom * fittedRect.height,
            ),
            p,
          );
        }
      }

      if (stroke.points.isNotEmpty) {
        drawStroke(stroke.points, stroke.radius, stroke.isEraser);
      }
    }

    if (activePoints.isNotEmpty) {
      drawStroke(activePoints, activeRadius, isEraser);
      // Precision brush touch indicator circle
      final lastPt = Offset(
        fittedRect.left + activePoints.last.dx * fittedRect.width,
        fittedRect.top + activePoints.last.dy * fittedRect.height,
      );
      final ringPaint = Paint()
        ..color = isEraser
            ? Colors.redAccent.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 / scale;
      canvas.drawCircle(lastPt, activeRadius * fittedRect.width, ringPaint);
    }

    canvas.restore(); // restore layer
    canvas.restore(); // restore translate and scale
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) {
    return oldDelegate.showSelection != showSelection ||
        oldDelegate.scale != scale ||
        oldDelegate.offset != offset ||
        oldDelegate.activePoints != activePoints ||
        oldDelegate.activeRadius != activeRadius ||
        oldDelegate.isEraser != isEraser;
  }
}
