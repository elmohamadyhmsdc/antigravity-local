import 'package:flutter/material.dart' hide ActionDispatcher;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/actions/action_context.dart';
import '../../domain/actions/action_id.dart';
import '../../domain/actions/entity_ref.dart';

typedef ActionHandler =
    Future<void> Function(
      BuildContext context,
      WidgetRef ref,
      EntityRef entity,
      ActionContext actionContext,
    );

class AppActionDispatcher {
  AppActionDispatcher._();

  static final Map<ActionId, ActionHandler> _handlers = {};

  static void register(ActionId id, ActionHandler handler) {
    _handlers[id] = handler;
  }

  static void unregister(ActionId id) {
    _handlers.remove(id);
  }

  static bool hasHandler(ActionId id) => _handlers.containsKey(id);

  static Future<void> dispatch(
    BuildContext context,
    WidgetRef ref,
    ActionId id,
    EntityRef entity, [
    ActionContext actionContext = ActionContext.defaultContext,
  ]) async {
    final handler = _handlers[id];
    if (handler != null) {
      await handler(context, ref, entity, actionContext);
    } else {
      debugPrint('No handler registered for action $id');
    }
  }

  @visibleForTesting
  static void clearHandlers() {
    _handlers.clear();
  }
}
