import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/curation_queries.dart';
import '../../domain/curation/auto_dataset_curator.dart';

class CurationState {
  const CurationState({
    required this.personId,
    required this.personName,
    this.faces = const [],
    this.upper = const [],
    this.body = const [],
    this.triggerWord = '',
    this.faceDetailerEnabled = true,
    this.resolutionMode = '512x768',
    this.isLoading = false,
    this.error,
    this.lastRemoved,
    this.lastRemovedCategory,
  });

  final int personId;
  final String personName;
  final List<CurationCandidate> faces;
  final List<CurationCandidate> upper;
  final List<CurationCandidate> body;
  final String triggerWord;
  final bool faceDetailerEnabled;
  final String resolutionMode;
  final bool isLoading;
  final String? error;
  final CurationCandidate? lastRemoved;
  final CurationCategory? lastRemovedCategory;

  int get totalCount => faces.length + upper.length + body.length;
  bool get canUndo => lastRemoved != null && lastRemovedCategory != null;
  bool get isReady => totalCount >= 15 && totalCount <= 35;
  bool get canSubmit => totalCount >= 5;

  List<CurationCandidate> get all => [...faces, ...upper, ...body];

  CurationState copyWith({
    int? personId,
    String? personName,
    List<CurationCandidate>? faces,
    List<CurationCandidate>? upper,
    List<CurationCandidate>? body,
    String? triggerWord,
    bool? faceDetailerEnabled,
    String? resolutionMode,
    bool? isLoading,
    String? error,
    CurationCandidate? lastRemoved,
    CurationCategory? lastRemovedCategory,
    bool clearUndo = false,
  }) {
    return CurationState(
      personId: personId ?? this.personId,
      personName: personName ?? this.personName,
      faces: faces ?? this.faces,
      upper: upper ?? this.upper,
      body: body ?? this.body,
      triggerWord: triggerWord ?? this.triggerWord,
      faceDetailerEnabled: faceDetailerEnabled ?? this.faceDetailerEnabled,
      resolutionMode: resolutionMode ?? this.resolutionMode,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      lastRemoved: clearUndo ? null : (lastRemoved ?? this.lastRemoved),
      lastRemovedCategory: clearUndo
          ? null
          : (lastRemovedCategory ?? this.lastRemovedCategory),
    );
  }
}

class CurationNotifier extends Notifier<CurationState> {
  CurationNotifier({
    CurationQueries? queries,
    AutoDatasetCurator? curator,
    this.initialState,
  })  : _queriesOverride = queries,
        _curatorOverride = curator;

  final CurationQueries? _queriesOverride;
  final AutoDatasetCurator? _curatorOverride;
  final CurationState? initialState;
  CurationState? _localState;

  @override
  CurationState build() =>
      initialState ?? const CurationState(personId: 0, personName: '');

  @override
  CurationState get state {
    if (_localState != null) return _localState!;
    try {
      return super.state;
    } catch (_) {
      return initialState ?? const CurationState(personId: 0, personName: '');
    }
  }

  @override
  set state(CurationState value) {
    _localState = value;
    try {
      super.state = value;
    } catch (_) {}
  }

  AutoDatasetCurator get _curator =>
      _curatorOverride ?? const AutoDatasetCurator();

  CurationQueries? get _queries {
    if (_queriesOverride != null) return _queriesOverride;
    try {
      return ref.read(curationQueriesProvider);
    } catch (_) {
      return null;
    }
  }

  Future<void> load(int personId, String personName) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final safeName = personName.trim().isEmpty ? 'person' : personName.trim();
      final trigger =
          'sks_${safeName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_')}';

      final q = _queries;
      if (q == null) {
        state = state.copyWith(
          personId: personId,
          personName: safeName,
          triggerWord: trigger,
          isLoading: false,
        );
        return;
      }

      final candidates = await q.loadCandidatesForPerson(personId);
      final curated = _curator.curate(candidates);

      state = state.copyWith(
        personId: personId,
        personName: safeName,
        faces: curated.faces,
        upper: curated.upper,
        body: curated.body,
        triggerWord: trigger,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '$e');
    }
  }

  void removeItem(CurationCandidate item) {
    switch (item.category) {
      case CurationCategory.face:
        final next =
            state.faces.where((c) => c.detectionId != item.detectionId).toList();
        state = state.copyWith(
          faces: next,
          lastRemoved: item,
          lastRemovedCategory: CurationCategory.face,
        );
        break;
      case CurationCategory.upper:
        final next =
            state.upper.where((c) => c.detectionId != item.detectionId).toList();
        state = state.copyWith(
          upper: next,
          lastRemoved: item,
          lastRemovedCategory: CurationCategory.upper,
        );
        break;
      case CurationCategory.body:
        final next =
            state.body.where((c) => c.detectionId != item.detectionId).toList();
        state = state.copyWith(
          body: next,
          lastRemoved: item,
          lastRemovedCategory: CurationCategory.body,
        );
        break;
    }
  }

  bool undoLastRemoval() {
    final item = state.lastRemoved;
    final cat = state.lastRemovedCategory;
    if (item == null || cat == null) return false;

    switch (cat) {
      case CurationCategory.face:
        state = state.copyWith(
          faces: [...state.faces, item],
          clearUndo: true,
        );
        break;
      case CurationCategory.upper:
        state = state.copyWith(
          upper: [...state.upper, item],
          clearUndo: true,
        );
        break;
      case CurationCategory.body:
        state = state.copyWith(
          body: [...state.body, item],
          clearUndo: true,
        );
        break;
    }
    return true;
  }

  void addItems(List<CurationCandidate> items, CurationCategory category) {
    final existingIds = state.all.map((c) => c.detectionId).toSet();
    final toAdd = <CurationCandidate>[];
    for (final item in items) {
      if (!existingIds.contains(item.detectionId)) {
        existingIds.add(item.detectionId);
        toAdd.add(item);
      }
    }
    if (toAdd.isEmpty) return;

    switch (category) {
      case CurationCategory.face:
        state = state.copyWith(faces: [...state.faces, ...toAdd]);
        break;
      case CurationCategory.upper:
        state = state.copyWith(upper: [...state.upper, ...toAdd]);
        break;
      case CurationCategory.body:
        state = state.copyWith(body: [...state.body, ...toAdd]);
        break;
    }
  }

  void setTriggerWord(String val) {
    state = state.copyWith(triggerWord: val.trim());
  }

  void toggleFaceDetailer() {
    state = state.copyWith(faceDetailerEnabled: !state.faceDetailerEnabled);
  }

  void setResolutionMode(String mode) {
    state = state.copyWith(resolutionMode: mode);
  }
}

final curationControllerProvider =
    NotifierProvider.autoDispose<CurationNotifier, CurationState>(
  CurationNotifier.new,
);
