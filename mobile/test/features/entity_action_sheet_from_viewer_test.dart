import 'package:antigravity_mobile/domain/actions/action_context.dart';
import 'package:antigravity_mobile/domain/actions/entity_ref.dart';
import 'package:antigravity_mobile/ui/actions/entity_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/harness.dart';

void main() {
  group('EntityActionSheet from Viewer', () {
    testWidgets('displays all expected face actions', (tester) async {
      const faceRef = FaceEntityRef(10, mediaId: 1, personId: 2);

      const actionContext = ActionContext(
        isMultiSelect: false,
        isVideo: false,
        hasPerson: true,
        isPcConnected: true,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EntityActionSheet(
              entity: faceRef,
              actionContext: actionContext,
            ),
          ),
        ),
      );

      await expandActionSections(tester);
      expect(find.byKey(const Key('action-sheet-open')), findsOneWidget);
      expect(
        find.byKey(const Key('action-sheet-assignPerson')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('action-sheet-notThisPerson')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('action-sheet-changeKind')), findsOneWidget);
      expect(find.byKey(const Key('action-sheet-refaceThis')), findsOneWidget);
      expect(find.byKey(const Key('action-sheet-delete')), findsOneWidget);
    });

    testWidgets('displays all expected body actions', (tester) async {
      const bodyRef = BodyEntityRef(20, mediaId: 1, personId: 2);

      const actionContext = ActionContext(
        isMultiSelect: false,
        isVideo: false,
        hasPerson: true,
        isPcConnected: true,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EntityActionSheet(
              entity: bodyRef,
              actionContext: actionContext,
            ),
          ),
        ),
      );

      await expandActionSections(tester);
      expect(
        find.byKey(const Key('action-sheet-assignPerson')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('action-sheet-notThisPerson')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('action-sheet-similarPose')), findsOneWidget);
      expect(
        find.byKey(const Key('action-sheet-similarColours')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('action-sheet-namePose')), findsOneWidget);
      expect(find.byKey(const Key('action-sheet-nameOutfit')), findsOneWidget);
      expect(
        find.byKey(const Key('action-sheet-nameGroupPose')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('action-sheet-markTattoo')), findsOneWidget);
      expect(find.byKey(const Key('action-sheet-restyleThis')), findsOneWidget);
    });
  });
}
