import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/domain/curation/auto_dataset_curator.dart';
import 'package:antigravity_mobile/features/lora/curation_controller.dart';

void main() {
  group('CurationController', () {
    test('removeItem removes candidate and enables undo restoration', () {
      const cFace = CurationCandidate(
        detectionId: 1,
        mediaId: 10,
        assetId: 'a1',
        isVideo: false,
        category: CurationCategory.face,
      );
      const cUpper = CurationCandidate(
        detectionId: 2,
        mediaId: 20,
        assetId: 'a2',
        isVideo: false,
        category: CurationCategory.upper,
      );
      const cBody = CurationCandidate(
        detectionId: 3,
        mediaId: 30,
        assetId: 'a3',
        isVideo: false,
        category: CurationCategory.body,
        hasExposedRegion: true,
      );

      final state = CurationState(
        personId: 1,
        personName: 'Sara',
        faces: [cFace],
        upper: [cUpper],
        body: [cBody],
        triggerWord: 'sks_sara',
      );

      final controller = CurationNotifier(initialState: state);

      expect(controller.state.totalCount, 3);
      expect(controller.state.body.length, 1);

      // Remove body item
      controller.removeItem(cBody);

      expect(controller.state.totalCount, 2);
      expect(controller.state.body.isEmpty, isTrue);
      expect(controller.state.lastRemoved, equals(cBody));
      expect(controller.state.canUndo, isTrue);

      // Undo removal
      final restored = controller.undoLastRemoval();

      expect(restored, isTrue);
      expect(controller.state.totalCount, 3);
      expect(controller.state.body.length, 1);
      expect(controller.state.body.first.detectionId, 3);
      expect(controller.state.canUndo, isFalse);
    });

    test('addItems appends unique candidates to target category', () {
      final state = CurationState(
        personId: 1,
        personName: 'Sara',
        faces: [],
        upper: [],
        body: [],
        triggerWord: 'sks_sara',
      );

      final controller = CurationNotifier(initialState: state);

      const candidate = CurationCandidate(
        detectionId: 15,
        mediaId: 40,
        assetId: 'a4',
        isVideo: false,
        category: CurationCategory.face,
      );

      controller.addItems([candidate, candidate], CurationCategory.face);

      expect(controller.state.faces.length, 1); // Deduplicated by detectionId
      expect(controller.state.faces.first.detectionId, 15);
    });

    test('trigger word updates correctly', () {
      final state = CurationState(
        personId: 1,
        personName: 'Sara',
        faces: [],
        upper: [],
        body: [],
        triggerWord: 'sks_sara',
      );

      final controller = CurationNotifier(initialState: state);
      controller.setTriggerWord('sks_new');
      expect(controller.state.triggerWord, 'sks_new');
    });
  });
}
