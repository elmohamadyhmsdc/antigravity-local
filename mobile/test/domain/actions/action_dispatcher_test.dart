import 'package:flutter/material.dart' hide ActionDispatcher;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:antigravity_mobile/domain/actions/action_id.dart';
import 'package:antigravity_mobile/domain/actions/entity_ref.dart';
import 'package:antigravity_mobile/ui/actions/action_dispatcher.dart';

void main() {
  setUp(() {
    AppActionDispatcher.clearHandlers();
  });

  tearDown(() {
    AppActionDispatcher.clearHandlers();
  });

  testWidgets(
    'AppActionDispatcher registers and dispatches actions correctly',
    (tester) async {
      ActionId? dispatchedAction;
      EntityRef? dispatchedEntity;

      AppActionDispatcher.register(ActionId.open, (
        context,
        ref,
        entity,
        actCtx,
      ) async {
        dispatchedAction = ActionId.open;
        dispatchedEntity = entity;
      });

      expect(AppActionDispatcher.hasHandler(ActionId.open), isTrue);
      expect(AppActionDispatcher.hasHandler(ActionId.delete), isFalse);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                return ElevatedButton(
                  onPressed: () {
                    AppActionDispatcher.dispatch(
                      context,
                      ref,
                      ActionId.open,
                      const MediaEntityRef(42),
                    );
                  },
                  child: const Text('Dispatch'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Dispatch'));
      await tester.pump();

      expect(dispatchedAction, equals(ActionId.open));
      expect(dispatchedEntity, equals(const MediaEntityRef(42)));

      AppActionDispatcher.unregister(ActionId.open);
      expect(AppActionDispatcher.hasHandler(ActionId.open), isFalse);
    },
  );
}
