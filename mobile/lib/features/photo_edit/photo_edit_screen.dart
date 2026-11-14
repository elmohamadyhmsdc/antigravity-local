import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/artifact_context.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../../studio_providers.dart';
import '../privacy/app_lock.dart';
import '../studio/studio_helpers.dart';
import 'mask_builder.dart';
import 'selection_model.dart';
import 'smart_selector.dart';

class PhotoEditScreen extends ConsumerStatefulWidget {
  const PhotoEditScreen({
    super.key,
    this.mediaId,
    this.initialPhotoBytes,
  });

  final int? mediaId;
  final Uint8List? initialPhotoBytes;

  @override
  ConsumerState<PhotoEditScreen> createState() => _PhotoEditScreenState();
}

class _PhotoEditScreenState extends ConsumerState<PhotoEditScreen> {
  final _promptController = TextEditingController();
  final _selectionModel = SelectionModel();

  Uint8List? _photoBytes;
  ui.Image? _decodedPhoto;
  SmartImageThumb? _smartThumb;
  int? _contextMediaId;
  String? _contextAssetId;

  var _activeTool = SelectionTool.brush;
  var _operation = PhotoEditOperation.remove;
  var _brushRadius = 0.035;
  var _smartTolerance = 0.22;
  var _strength = 0.85;
  var _busy = false;
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
    if (!_selectionModel.hasSelection) {
      setState(() => _error = 'Select an object or clothing first.');
      return;
    }
    if (_operation == PhotoEditOperation.replace &&
        _promptController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a description for the replacement.');
      return;
    }

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

      final maskBytes = await MaskBuilder.buildMaskPng(
        _selectionModel,
        width: targetW,
        height: targetH,
      );

      final photoFile = await privatePickedPhoto(ref, photo);
      filesToClean.add(photoFile);

      final fileStore = ref.read(fileStoreProvider);
      final maskPath = 'work/photo_edit/mask_${DateTime.now().microsecondsSinceEpoch}.png';
      await fileStore.write(maskPath, maskBytes);
      final maskFile = fileStore.resolve(maskPath);
      filesToClean.add(maskFile);

      setState(() {
        _progressText = 'Uploading to PC server...';
        _progress = 0.15;
      });

      final operationStr = _operation == PhotoEditOperation.remove ? 'remove' : 'replace';
      final promptStr = _promptController.text.trim();

      final jobId = await ref.read(studioRepositoryProvider).enqueueInputs(
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
          'mask_normalized': true,
          'strength': _strength,
        },
        inputs: {
          'image': [photoFile],
          'mask': [maskFile],
        },
      );

      ref.read(jobTrackerProvider).start();

      // Monitor job until completed or failed
      await _waitForJobCompletion(jobId);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      for (final f in filesToClean) {
        if (await f.exists()) await f.delete();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _waitForJobCompletion(String jobId) async {
    final repo = ref.read(studioRepositoryProvider);
    final files = ref.read(fileStoreProvider);

    for (var i = 0; i < 300; i++) {
      if (!mounted) return;
      await Future<void>.delayed(const Duration(seconds: 1));
      final job = await repo.job(jobId);
      if (job == null) continue;

      if (mounted) {
        setState(() {
          _progress = (job.progress / 100.0).clamp(0.15, 0.95);
          _progressText = job.status == 'running'
              ? 'Processing AI edit (${(job.progress).round()}%)...'
              : '${job.status}...';
        });
      }

      if (job.status == 'completed') {
        final resultRow = await (repo.db.select(repo.db.results)..where((r) => r.id.equals(jobId))).getSingleOrNull();
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
                _progress = 1.0;
                _progressText = 'Done';
              });
            }
            return;
          }
        }
      } else if (job.status == 'failed') {
        throw Exception(job.error != null && job.error!.isNotEmpty ? job.error! : 'AI edit failed on server.');
      }
    }
    throw TimeoutException('AI edit timed out.');
  }

  Future<void> _saveCopy() async {
    final file = _resultFile;
    if (file == null || _savedToGallery) return;

    try {
      final saved = await ref.read(privacyServiceProvider).exportMedia(file, 'image/png');
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photoBytes;
    final decoded = _decodedPhoto;
    final result = _resultBytes;

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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
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
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (photo == null || decoded == null)
                    const Center(child: CircularProgressIndicator())
                  else if (result != null && !_showOriginal)
                    Image.memory(
                      result,
                      fit: BoxFit.contain,
                    )
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
                          CircularProgressIndicator(value: _progress > 0 ? _progress : null),
                          const SizedBox(height: 16),
                          Text(
                            _progressText,
                            style: const TextStyle(color: Colors.white, fontSize: 16),
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
              _buildEditorControls(),
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
      final nx = ((canvasX - fittedRect.left) / fittedRect.width).clamp(0.0, 1.0);
      final ny = ((canvasY - fittedRect.top) / fittedRect.height).clamp(0.0, 1.0);
      return Offset(nx, ny);
    }

    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            if (_activeTool == SelectionTool.smartTap) {
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

            if (details.pointerCount == 1 &&
                (_activeTool == SelectionTool.brush || _activeTool == SelectionTool.eraser)) {
              final norm = toNormalized(details.localFocalPoint);
              if (norm != null) {
                setState(() => _activeStrokePoints = [norm]);
              }
            }
          },
          onScaleUpdate: (details) {
            if (details.pointerCount >= 2 || _activeTool == SelectionTool.move) {
              if (_activeStrokePoints.isNotEmpty) {
                setState(() => _activeStrokePoints = []);
              }
              final newScale = (_baseScale * details.scale).clamp(1.0, 8.0);
              final focal = details.localFocalPoint;
              Offset newOffset = focal - (focal - _baseOffset) * (newScale / _baseScale);
              newOffset += (details.localFocalPoint - _focalStart);

              if (newScale <= 1.0) {
                newOffset = Offset.zero;
              }

              setState(() {
                _scale = newScale;
                _offset = newOffset;
              });
            } else if (details.pointerCount == 1 &&
                (_activeTool == SelectionTool.brush || _activeTool == SelectionTool.eraser)) {
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                      const Icon(Icons.zoom_out_map, size: 14, color: Colors.white),
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

  Widget _buildEditorControls() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                        side: BorderSide.none,
                        onSelected: (v) {
                          if (v) setState(() => _operation = PhotoEditOperation.remove);
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                        side: BorderSide.none,
                        onSelected: (v) {
                          if (v) setState(() => _operation = PhotoEditOperation.replace);
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
                      onSelected: (_) => setState(() => _activeTool = SelectionTool.brush),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      key: const Key('tool-eraser'),
                      avatar: const Icon(Icons.auto_fix_normal, size: 17),
                      label: const Text('Eraser'),
                      selected: _activeTool == SelectionTool.eraser,
                      onSelected: (_) => setState(() => _activeTool = SelectionTool.eraser),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      key: const Key('tool-smart-tap'),
                      avatar: const Icon(Icons.touch_app, size: 17),
                      label: const Text('Smart Tap'),
                      selected: _activeTool == SelectionTool.smartTap,
                      onSelected: (_) => setState(() => _activeTool = SelectionTool.smartTap),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      key: const Key('tool-move'),
                      avatar: const Icon(Icons.pan_tool_outlined, size: 17),
                      label: const Text('Move & Zoom'),
                      selected: _activeTool == SelectionTool.move,
                      onSelected: (_) => setState(() => _activeTool = SelectionTool.move),
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
                          Row(
                            children: [
                              Text(
                                'Tolerance / الحساسية: ${(_smartTolerance * 100).round()}%',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: scheme.primary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Tap to select object/clothes',
                                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            ),
                            child: Slider(
                              key: const Key('smart-tolerance-slider'),
                              value: _smartTolerance,
                              min: 0.08,
                              max: 0.45,
                              divisions: 15,
                              onChanged: (v) => setState(() => _smartTolerance = v),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_activeTool != SelectionTool.move) ...[
                    Icon(Icons.line_weight, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
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
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  IconButton.filledTonal(
                    key: const Key('edit-undo'),
                    icon: const Icon(Icons.undo, size: 18),
                    tooltip: 'Undo',
                    onPressed: _selectionModel.canUndo ? _selectionModel.undo : null,
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    key: const Key('edit-redo'),
                    icon: const Icon(Icons.redo, size: 18),
                    tooltip: 'Redo',
                    onPressed: _selectionModel.canRedo ? _selectionModel.redo : null,
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    key: const Key('edit-clear'),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Clear',
                    onPressed: _selectionModel.canUndo ? _selectionModel.clear : null,
                  ),
                ],
              ),

              // Prompt TextField if Replace
              if (_operation == PhotoEditOperation.replace) ...[
                const SizedBox(height: 8),
                TextField(
                  key: const Key('instruction-input'),
                  controller: _promptController,
                  decoration: InputDecoration(
                    labelText: 'Prompt / الوصف (عربي أو إنجليزي)',
                    hintText: 'e.g. بدلة كلاسيك كحلي / elegant red evening dress...',
                    prefixIcon: Icon(Icons.auto_awesome, size: 18, color: scheme.primary),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ActionChip(
                        avatar: const Text('👔', style: TextStyle(fontSize: 13)),
                        label: const Text('بدلة كلاسيك كحلي'),
                        onPressed: () => setState(() => _promptController.text = 'بدلة كلاسيك كحلي'),
                      ),
                      const SizedBox(width: 5),
                      ActionChip(
                        avatar: const Text('👗', style: TextStyle(fontSize: 13)),
                        label: const Text('فستان سواريه أحمر'),
                        onPressed: () => setState(() => _promptController.text = 'فستان سواريه أحمر'),
                      ),
                      const SizedBox(width: 5),
                      ActionChip(
                        avatar: const Text('🧥', style: TextStyle(fontSize: 13)),
                        label: const Text('جاكيت جلد أسود'),
                        onPressed: () => setState(() => _promptController.text = 'جاكيت جلد أسود'),
                      ),
                      const SizedBox(width: 5),
                      ActionChip(
                        avatar: const Text('👕', style: TextStyle(fontSize: 13)),
                        label: const Text('قميص كاجوال أبيض'),
                        onPressed: () => setState(() => _promptController.text = 'قميص كاجوال أبيض'),
                      ),
                      const SizedBox(width: 5),
                      ActionChip(
                        avatar: const Text('⌚', style: TextStyle(fontSize: 13)),
                        label: const Text('ساعة يد فخمة'),
                        onPressed: () => setState(() => _promptController.text = 'ساعة يد فخمة'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.accessibility_new, size: 16, color: scheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Change Strength / قوة التغيير: ${(_strength * 100).round()}%',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _strength >= 0.80 ? 'واضح وقوي' : 'طبيعي معتدل',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: scheme.primary),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
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
                onPressed: (!_busy && _selectionModel.hasSelection) ? _submit : null,
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
                  onPressed: () => setState(() => _showOriginal = !_showOriginal),
                  icon: Icon(_showOriginal ? Icons.visibility : Icons.visibility_off, size: 18),
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
    required this.activePoints,
    required this.activeRadius,
    required this.isEraser,
  }) : super(repaint: model);

  final ui.Image image;
  final Rect fittedRect;
  final double scale;
  final Offset offset;
  final SelectionModel model;
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
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, src, fittedRect, Paint()..filterQuality = FilterQuality.medium);

    // 2. Draw mask overlay
    canvas.saveLayer(null, Paint());

    final maskPaint = Paint()
      ..color = const Color(0x77A855F7) // Semi-transparent purple
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
      final p = eraser ? (eraserPaint..strokeWidth = pxRadius * 2) : (maskPaint..strokeWidth = pxRadius * 2);

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
        ..color = isEraser ? Colors.redAccent.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 / scale;
      canvas.drawCircle(lastPt, activeRadius * fittedRect.width, ringPaint);
    }

    canvas.restore(); // restore layer
    canvas.restore(); // restore translate and scale
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) {
    return oldDelegate.scale != scale ||
        oldDelegate.offset != offset ||
        oldDelegate.activePoints != activePoints ||
        oldDelegate.activeRadius != activeRadius ||
        oldDelegate.isEraser != isEraser;
  }
}
