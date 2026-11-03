import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/api/dtos/embedding.dart';
import '../../data/media/media_library.dart';
import '../../data/repositories/artifact_context.dart';
import '../../data/repositories/media_queries.dart';
import '../../domain/curation/auto_dataset_curator.dart';
import '../../features/settings/background_screen.dart';
import '../../features/studio/studio_helpers.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../../studio_providers.dart';
import '../../ui/pickers/media_picker.dart';
import 'curation_controller.dart';
import 'lora_screens.dart' show datasetIdentityAnchor;

class CurationReviewScreen extends ConsumerStatefulWidget {
  const CurationReviewScreen({
    super.key,
    required this.personId,
    this.personName = 'person',
  });

  final int personId;
  final String personName;

  @override
  ConsumerState<CurationReviewScreen> createState() =>
      _CurationReviewScreenState();
}

class _CurationReviewScreenState extends ConsumerState<CurationReviewScreen> {
  String _activeCategory = 'all';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(curationControllerProvider.notifier)
          .load(widget.personId, widget.personName);
    });
  }

  void _deleteItem(CurationCandidate c) {
    ref.read(curationControllerProvider.notifier).removeItem(c);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('تم استبعاد الصورة من التدريب'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          key: const Key('curation-undo'),
          label: 'تراجع ↩',
          onPressed: () {
            ref.read(curationControllerProvider.notifier).undoLastRemoval();
          },
        ),
      ),
    );
  }

  Future<void> _onAdd() async {
    final state = ref.read(curationControllerProvider);
    final existingIds = state.all.map((c) => c.assetId).toSet();

    final pickedCandidates =
        await showModalBottomSheet<List<CurationCandidate>>(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (ctx) => FractionallySizedBox(
            heightFactor: 0.85,
            child: _PersonMediaPickerSheet(
              personId: widget.personId,
              personName: widget.personName,
              existingAssetIds: existingIds,
              activeCategory: _activeCategory,
            ),
          ),
        );

    if (pickedCandidates == null || pickedCandidates.isEmpty || !mounted) return;

    final currentCat = switch (_activeCategory) {
      'face' => CurationCategory.face,
      'upper' => CurationCategory.upper,
      _ => CurationCategory.body,
    };

    ref.read(curationControllerProvider.notifier).addItems(
      pickedCandidates,
      currentCat,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تمت إضافة ${pickedCandidates.length} صورة بنجاح'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _onSubmit() async {
    final caps = studioCapabilities(ref.read(serverStatusProvider).value);
    if (caps == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء التأكد من الاتصال بالكمبيوتر لبدء التدريب'),
        ),
      );
      return;
    }

    final state = ref.read(curationControllerProvider);
    if (state.totalCount < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب اختيار 5 صور على الأقل لبدء تدريب الموديل'),
        ),
      );
      return;
    }

    if (!RegExp(
      r'^[A-Za-z][A-Za-z0-9_]{2,63}$',
    ).hasMatch(state.triggerWord.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الكلمة المفتاحية (Trigger word) غير صالحة'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final mediaLib = ref.read(mediaLibraryProvider);
      final photos = <File>[];

      for (final c in state.all) {
        File? file;
        if (mediaLib is OriginalMediaLibrary) {
          file = await (mediaLib as OriginalMediaLibrary).originalFile(c.assetId);
        }
        if (file == null || !await file.exists()) {
          final bytes = await mediaLib.viewerImage(c.assetId);
          if (bytes != null) {
            file = await privatePickedPhoto(ref, bytes);
          }
        }
        if (file != null && await file.exists()) {
          photos.add(file);
        }
      }

      if (photos.length < 5) {
        throw FormatException(
          'تعذر استخراج ملفات الصور للتدريب (تم استخراج ${photos.length} فقط)',
        );
      }

      final faces = await ref
          .read(studioRepositoryProvider)
          .sourceFaces(widget.personId);
      final db = ref.read(databaseProvider);
      final person = await (db.select(
        db.persons,
      )..where((r) => r.id.equals(widget.personId))).getSingleOrNull();
      if (person == null) {
        throw const FormatException('الشخص المختار لم يعد موجوداً في قاعدة البيانات');
      }

      final isCharacter = person.kind == 'character';
      final identityModel = isCharacter
          ? characterEmbeddingModelId
          : 'buffalo_l@1';
      final anchor = datasetIdentityAnchor(faces, identityModel);

      if (!mounted) return;
      await prepareBackgroundForWork(context, ref);
      if (!mounted) return;

      final jobId = await ref
          .read(studioRepositoryProvider)
          .enqueueInputs(
            serverId: caps.serverId,
            type: 'build_lora_dataset',
            context: ArtifactContext(
              personId: widget.personId,
              identityModelId: identityModel,
            ),
            params: {
              'trigger_word': state.triggerWord.trim(),
              'repeats': 20,
              'anchor_embedding': anchor,
              // sent only when turned OFF: the default is on everywhere, so a PC that predates the option still
              // accepts the job (an unknown option is a 400 there). The resolution choice is a training
              // setting (max_resolution), not a dataset one, so it is not sent here.
              if (!state.faceDetailerEnabled) 'enable_face_detailer': false,
              if (caps.hasOperationSupport) 'identity_model_id': identityModel,
            },
            inputs: {'images': photos},
            personId: widget.personId,
          );

      ref.read(jobTrackerProvider).start();
      if (mounted) {
        context.pushReplacement('${Routes.jobs}/$jobId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل بدء التدريب: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _openSettings(BuildContext context, CurationState state) {
    final triggerController =
        TextEditingController(text: state.triggerWord);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final currentState = ref.watch(curationControllerProvider);
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'إعدادات الموديل والتدريب',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('curation-trigger-input'),
                    controller: triggerController,
                    decoration: const InputDecoration(
                      labelText: 'الكلمة المفتاحية (Trigger Word)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      ref
                          .read(curationControllerProvider.notifier)
                          .setTriggerWord(val);
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    key: const Key('curation-detailer-switch'),
                    title: const Text('تمريرة الوجه الفائق (Face Detailer)'),
                    subtitle: const Text(
                      'استعادة ملامح الوجه بدقة في اللقطات البعيدة',
                    ),
                    value: currentState.faceDetailerEnabled,
                    onChanged: (_) {
                      ref
                          .read(curationControllerProvider.notifier)
                          .toggleFaceDetailer();
                      setModalState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    key: const Key('curation-exposed-switch'),
                    title: const Text('تفضيل الصور المكشوفة'),
                    subtitle: const Text(
                      'مفتوح: الأجسام اللي فيها مناطق مكشوفة بتتقدّم في الاختيار (لحد 90% من أماكن الأجسام). '
                      'مقفول (الافتراضي): اختيار متوازن بالجودة والتنوع بس. تغييره بيعيد اختيار الأجسام.',
                    ),
                    value: currentState.preferExposed,
                    onChanged: (v) {
                      ref
                          .read(curationControllerProvider.notifier)
                          .setPreferExposed(v);
                      setModalState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    key: const Key('curation-resolution-dropdown'),
                    title: const Text('وضع الدقة (Resolution)'),
                    subtitle: Text(
                      currentState.resolutionMode == '512x768'
                          ? '512×768 (سريع ومناسب للـ 6GB VRAM)'
                          : '512×512 (مربع)',
                    ),
                    trailing: const Text(
                      '~8 دقائق',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('حفظ الإعدادات'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<CurationCandidate> _filteredCandidates(CurationState state) {
    switch (_activeCategory) {
      case 'face':
        return state.faces;
      case 'upper':
        return state.upper;
      case 'body':
        return state.body;
      default:
        return state.all;
    }
  }

  String _formatTime(int? ms) {
    if (ms == null) return '00:00';
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(curationControllerProvider);
    final theme = Theme.of(context);
    final items = _filteredCandidates(state);

    return Scaffold(
      appBar: AppBar(
        title: Text('تدريب موديل (${state.personName})'),
        actions: [
          IconButton(
            key: const Key('curation-settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _openSettings(context, state),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              OutlinedButton.icon(
                key: const Key('curation-add'),
                icon: const Icon(Icons.add),
                label: const Text('إضافة'),
                onPressed: _onAdd,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('curation-submit'),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.bolt_rounded),
                  label: Text(
                    _isSubmitting
                        ? 'جاري إعداد التدريب...'
                        : 'بدء تدريب الموديل الآن ⚡',
                  ),
                  onPressed:
                      (state.canSubmit && !_isSubmitting) ? _onSubmit : null,
                ),
              ),
            ],
          ),
        ),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Live Quality Status Pill
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Container(
                    key: const Key('curation-status-pill'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: state.isReady
                          ? Colors.green.withValues(alpha: 0.12)
                          : Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: state.isReady
                            ? Colors.green.withValues(alpha: 0.3)
                            : Colors.amber.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          state.isReady
                              ? Icons.check_circle_rounded
                              : Icons.info_outline_rounded,
                          size: 18,
                          color: state.isReady ? Colors.green : Colors.amber,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            state.isReady
                                ? 'جاهز: ${state.totalCount} صورة مختارة تلقائياً (جودة ممتازة)'
                                : 'تم اختيار ${state.totalCount} صور (ينصح بـ 15+ لجودة ممتازة)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: state.isReady
                                  ? Colors.green.shade800
                                  : Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Category Filter Tabs
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      FilterChip(
                        key: const Key('curation-tab-all'),
                        label: Text('الكل (${state.totalCount})'),
                        selected: _activeCategory == 'all',
                        onSelected: (s) {
                          if (s) setState(() => _activeCategory = 'all');
                        },
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        key: const Key('curation-tab-face'),
                        label: Text('👤 ملامح (${state.faces.length})'),
                        selected: _activeCategory == 'face',
                        onSelected: (s) {
                          if (s) setState(() => _activeCategory = 'face');
                        },
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        key: const Key('curation-tab-upper'),
                        label: Text('👕 نصف جسم (${state.upper.length})'),
                        selected: _activeCategory == 'upper',
                        onSelected: (s) {
                          if (s) setState(() => _activeCategory = 'upper');
                        },
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        key: const Key('curation-tab-body'),
                        label: Text('🔥 كامل وأقل لبس (${state.body.length})'),
                        selected: _activeCategory == 'body',
                        onSelected: (s) {
                          if (s) setState(() => _activeCategory = 'body');
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // 3. Candidates Grid
                Expanded(
                  child: items.isEmpty
                      ? const Center(
                          child: Text('لا توجد صور في هذا القسم'),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 0.8,
                          ),
                          itemCount: items.length,
                          itemBuilder: (ctx, idx) {
                            final c = items[idx];
                            return Stack(
                              key: Key('curation-card-${c.detectionId}'),
                              children: [
                                Positioned.fill(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: theme.dividerColor,
                                        ),
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          key: Key(
                                            'curation-preview-${c.detectionId}',
                                          ),
                                          onTap: () {
                                            context.push(
                                              '${Routes.media}/${c.mediaId}?personId=${widget.personId}',
                                            );
                                          },
                                          child: _CandidateThumbnail(
                                            candidate: c,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Delete Action
                                Positioned(
                                  top: 4,
                                  left: 4,
                                  child: GestureDetector(
                                    key: Key('curation-delete-${c.detectionId}'),
                                    onTap: () => _deleteItem(c),
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.7),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                // Badges
                                Positioned(
                                  bottom: 4,
                                  right: 4,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (c.hasExposedRegion)
                                        Container(
                                          key: Key('badge-exposed-${c.detectionId}'),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          margin: const EdgeInsets.only(bottom: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade700,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'كشف عالي',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      if (c.isVideo)
                                        Container(
                                          key: Key('badge-video-${c.detectionId}'),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.8),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '🎬 ${_formatTime(c.timestampMs)}',
                                            style: const TextStyle(
                                              fontSize: 9,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _CandidateThumbnail extends ConsumerWidget {
  const _CandidateThumbnail({required this.candidate});
  final CurationCandidate candidate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbs = ref.watch(thumbnailServiceProvider);
    final cached = thumbs.getSync(candidate.assetId, size: 256);
    if (cached != null) {
      return Image.memory(
        cached,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        cacheWidth: 256,
        cacheHeight: 256,
      );
    }

    return FutureBuilder<Uint8List?>(
      initialData: cached,
      future: thumbs.get(candidate.assetId, width: 256, height: 256),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data != null) {
          return Image.memory(
            data,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            cacheWidth: 256,
            cacheHeight: 256,
          );
        }
        final theme = Theme.of(context);
        return Container(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Center(
            child: Icon(
              candidate.category == CurationCategory.face
                  ? Icons.face_rounded
                  : candidate.category == CurationCategory.upper
                      ? Icons.person_rounded
                      : Icons.accessibility_new_rounded,
              size: 36,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
        );
      },
    );
  }
}

class _PersonMediaPickerSheet extends ConsumerStatefulWidget {
  const _PersonMediaPickerSheet({
    required this.personId,
    required this.personName,
    required this.existingAssetIds,
    required this.activeCategory,
  });

  final int personId;
  final String personName;
  final Set<String> existingAssetIds;
  final String activeCategory;

  @override
  ConsumerState<_PersonMediaPickerSheet> createState() =>
      _PersonMediaPickerSheetState();
}

class _PersonMediaPickerSheetState
    extends ConsumerState<_PersonMediaPickerSheet> {
  List<MediaListItem> _items = [];
  final Set<int> _selectedMediaIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPersonMedia();
  }

  Future<void> _loadPersonMedia() async {
    try {
      final queries = ref.read(mediaQueriesProvider);
      final list = await queries.page(
        MediaFilter(personId: widget.personId),
        offset: 0,
        limit: 120,
      );
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickFromAllGallery() async {
    final picked = await MediaPicker.pick(context, multiple: true);
    if (picked == null || picked.isEmpty || !mounted) return;

    final currentCat = switch (widget.activeCategory) {
      'face' => CurationCategory.face,
      'upper' => CurationCategory.upper,
      _ => CurationCategory.body,
    };

    final candidates = picked.map((asset) {
      final now = DateTime.now().microsecondsSinceEpoch;
      return CurationCandidate(
        detectionId: now + (int.tryParse(asset.id) ?? 0),
        mediaId: int.tryParse(asset.id) ?? 0,
        assetId: asset.id,
        isVideo: asset.kind == 'video',
        category: currentCat,
        quality: 0.85,
        hasExposedRegion: currentCat == CurationCategory.body,
        skinRatio: currentCat == CurationCategory.body ? 0.5 : 0.0,
      );
    }).toList();

    Navigator.of(context).pop(candidates);
  }

  void _confirmSelection() {
    final currentCat = switch (widget.activeCategory) {
      'face' => CurationCategory.face,
      'upper' => CurationCategory.upper,
      _ => CurationCategory.body,
    };

    final candidates = <CurationCandidate>[];
    for (final item in _items) {
      if (_selectedMediaIds.contains(item.id)) {
        final now = DateTime.now().microsecondsSinceEpoch;
        candidates.add(
          CurationCandidate(
            detectionId: now + item.id,
            mediaId: item.id,
            assetId: item.assetId,
            isVideo: item.kind == 'video',
            category: currentCat,
            quality: 0.85,
            hasExposedRegion: currentCat == CurationCategory.body,
            skinRatio: currentCat == CurationCategory.body ? 0.5 : 0.0,
          ),
        );
      }
    }
    Navigator.of(context).pop(candidates);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('curation-person-picker-sheet'),
      appBar: AppBar(
        title: Text('إضافة صور لـ ${widget.personName}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            key: const Key('curation-picker-all-gallery'),
            onPressed: _pickFromAllGallery,
            child: const Text('كل الاستوديو 📁'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: FilledButton(
            key: const Key('curation-picker-confirm'),
            onPressed: _selectedMediaIds.isEmpty ? null : _confirmSelection,
            child: Text(
              _selectedMediaIds.isEmpty
                  ? 'اختر صوراً للإضافة'
                  : 'إضافة ${_selectedMediaIds.length} صور للتدريب',
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('لم يتم العثور على صور إضافية لهذا الشخص'),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('تصفح كل ألبوم الهاتف 📁'),
                        onPressed: _pickFromAllGallery,
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (ctx, idx) {
                    final item = _items[idx];
                    final isAlreadyAdded =
                        widget.existingAssetIds.contains(item.assetId);
                    final isSelected = _selectedMediaIds.contains(item.id);

                    return GestureDetector(
                      key: Key('picker-item-${item.id}'),
                      onTap: isAlreadyAdded
                          ? null
                          : () {
                              setState(() {
                                if (isSelected) {
                                  _selectedMediaIds.remove(item.id);
                                } else {
                                  _selectedMediaIds.add(item.id);
                                }
                              });
                            },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _CandidateThumbnail(
                              candidate: CurationCandidate(
                                detectionId: item.id,
                                mediaId: item.id,
                                assetId: item.assetId,
                                isVideo: item.kind == 'video',
                                category: CurationCategory.face,
                              ),
                            ),
                          ),
                          if (isAlreadyAdded)
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(
                                child: Text(
                                  'موجودة',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          if (isSelected)
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: theme.colorScheme.primary,
                                  width: 3,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.25,
                                ),
                              ),
                              child: Align(
                                alignment: Alignment.topRight,
                                child: Container(
                                  margin: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
