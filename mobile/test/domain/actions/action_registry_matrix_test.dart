import 'package:flutter_test/flutter_test.dart';

import 'package:antigravity_mobile/domain/actions/action_id.dart';
import 'package:antigravity_mobile/domain/actions/action_registry.dart';
import 'package:antigravity_mobile/domain/actions/entity_ref.dart';

void main() {
  group('ActionRegistry Matrix Verification', () {
    test('MediaEntityRef has expected actions and quick actions', () {
      const media = MediaEntityRef(1, isVideo: false);
      final actions = ActionRegistry.actionsFor(media);
      final quick = ActionRegistry.quickActionsFor(media);

      expect(actions.contains(ActionId.open), isTrue);
      expect(actions.contains(ActionId.info), isTrue);
      expect(actions.contains(ActionId.expand), isTrue);
      expect(actions.contains(ActionId.refaceThis), isTrue);
      expect(actions.contains(ActionId.restyleThis), isTrue);
      expect(actions.contains(ActionId.addToDataset), isTrue);
      expect(actions.contains(ActionId.share), isTrue);
      expect(actions.contains(ActionId.analyzeNow), isTrue);
      expect(actions.contains(ActionId.redetect), isTrue);

      expect(quick, containsAll([ActionId.info, ActionId.share]));
    });

    test('Video MediaEntityRef exposes openNativePlayer', () {
      const video = MediaEntityRef(2, isVideo: true);
      final actions = ActionRegistry.actionsFor(video);

      expect(actions.contains(ActionId.openNativePlayer), isTrue);
    });

    test('FaceEntityRef has expected actions and quick actions', () {
      const face = FaceEntityRef(10, personId: 5);
      final actions = ActionRegistry.actionsFor(face);
      final quick = ActionRegistry.quickActionsFor(face);

      expect(actions.contains(ActionId.open), isTrue);
      expect(actions.contains(ActionId.info), isTrue);
      expect(actions.contains(ActionId.expand), isTrue);
      expect(actions.contains(ActionId.openPhoto), isTrue);
      expect(actions.contains(ActionId.assignPerson), isTrue);
      expect(actions.contains(ActionId.notThisPerson), isTrue);
      expect(actions.contains(ActionId.setCover), isTrue);
      expect(actions.contains(ActionId.similarFaces), isTrue);
      expect(actions.contains(ActionId.refaceThis), isTrue);
      expect(actions.contains(ActionId.addToDataset), isTrue);
      expect(actions.contains(ActionId.remove), isTrue);
      expect(actions.contains(ActionId.delete), isTrue);

      expect(quick, containsAll([ActionId.assignPerson, ActionId.refaceThis]));
    });

    test('BodyEntityRef has expected actions and quick actions', () {
      const body = BodyEntityRef(20);
      final actions = ActionRegistry.actionsFor(body);
      final quick = ActionRegistry.quickActionsFor(body);

      expect(actions.contains(ActionId.open), isTrue);
      expect(actions.contains(ActionId.info), isTrue);
      expect(actions.contains(ActionId.expand), isTrue);
      expect(actions.contains(ActionId.openPhoto), isTrue);
      expect(actions.contains(ActionId.assignPerson), isTrue);
      expect(actions.contains(ActionId.markTattoo), isTrue);
      expect(actions.contains(ActionId.namePose), isTrue);
      expect(actions.contains(ActionId.similarPose), isTrue);
      expect(actions.contains(ActionId.similarColours), isTrue);
      expect(actions.contains(ActionId.refaceThis), isTrue);
      expect(actions.contains(ActionId.restyleThis), isTrue);

      expect(
        quick,
        containsAll([
          ActionId.openPhoto,
          ActionId.similarPose,
          ActionId.similarColours,
          ActionId.markTattoo,
          ActionId.namePose,
          ActionId.restyleThis,
        ]),
      );
    });

    test(
      'PersonEntityRef respects character vs real person for studio actions',
      () {
        const realPerson = PersonEntityRef(1, isCharacter: false);
        const character = PersonEntityRef(2, isCharacter: true);

        final realActions = ActionRegistry.actionsFor(realPerson);
        final charActions = ActionRegistry.actionsFor(character);

        expect(realActions.contains(ActionId.refaceWith), isTrue);
        expect(realActions.contains(ActionId.trainModel), isTrue);
        expect(charActions.contains(ActionId.refaceWith), isFalse);
        expect(charActions.contains(ActionId.trainModel), isFalse);

        final realQuick = ActionRegistry.quickActionsFor(realPerson);
        final charQuick = ActionRegistry.quickActionsFor(character);
        expect(realQuick.contains(ActionId.refaceWith), isTrue);
        expect(charQuick.contains(ActionId.refaceWith), isFalse);
      },
    );

    test('Bulk actions computes intersection across multiple entities', () {
      const face = FaceEntityRef(1);
      const body = BodyEntityRef(2);
      const media = MediaEntityRef(3);

      final common = ActionRegistry.bulkActionsFor([face, body, media]);
      // Actions common to face, body, and media: open, info, expand, refaceThis
      expect(common.contains(ActionId.open), isTrue);
      expect(common.contains(ActionId.info), isTrue);
      expect(common.contains(ActionId.expand), isTrue);
      expect(common.contains(ActionId.refaceThis), isTrue);

      // markTattoo is only for body, so it should not be in intersection
      expect(common.contains(ActionId.markTattoo), isFalse);
    });
  });
}
