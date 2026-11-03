import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router.dart';
import '../../domain/curation/auto_dataset_curator.dart';
import '../../features/studio/studio_helpers.dart';
import '../../providers.dart';
import '../../ui/pickers/media_picker.dart';
import 'curation_controller.dart';

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
    final picked = await MediaPicker.pick(context, multiple: true);
    if (picked == null || picked.isEmpty || !mounted) return;

    final currentCat = switch (_activeCategory) {
      'face' => CurationCategory.face,
      'upper' => CurationCategory.upper,
      _ => CurationCategory.body,
    };

    final newCandidates = picked.map((asset) {
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

    ref.read(curationControllerProvider.notifier).addItems(newCandidates, currentCat);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تمت إضافة ${newCandidates.length} صورة بنجاح'),
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
    context.push('${Routes.studioDatasetsNew}?person=${widget.personId}');
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
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text('بدء تدريب الموديل الآن ⚡'),
                  onPressed: state.canSubmit ? _onSubmit : null,
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                                Container(
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: theme.dividerColor,
                                    ),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      c.category == CurationCategory.face
                                          ? Icons.face_rounded
                                          : c.category == CurationCategory.upper
                                              ? Icons.person_rounded
                                              : Icons.accessibility_new_rounded,
                                      size: 36,
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.5),
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
