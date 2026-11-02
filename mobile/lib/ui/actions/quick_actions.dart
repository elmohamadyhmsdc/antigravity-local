import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/actions/action_context.dart';
import '../../domain/actions/action_id.dart';
import '../../domain/actions/action_registry.dart';
import '../../domain/actions/entity_ref.dart';
import 'action_dispatcher.dart';

class QuickActionsBar extends ConsumerWidget {
  const QuickActionsBar({
    super.key,
    required this.entity,
    this.actionContext = ActionContext.defaultContext,
    this.maxActions = 4,
    this.onAction,
  });

  final EntityRef entity;
  final ActionContext actionContext;
  final int maxActions;
  final void Function(ActionId id)? onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quickIds = ActionRegistry.quickActionsFor(
      entity,
      actionContext,
    ).take(maxActions).toList();

    if (quickIds.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (var i = 0; i < quickIds.length; i++) ...[
            _buildButton(context, ref, quickIds[i]),
            if (i < quickIds.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildButton(BuildContext context, WidgetRef ref, ActionId id) {
    final spec = ActionRegistry.spec(id);
    final theme = Theme.of(context);
    final isDanger = spec.isDanger;

    return FilledButton.tonalIcon(
      key: Key('quick-action-${id.name}'),
      style: isDanger
          ? FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
            )
          : null,
      onPressed: () {
        if (onAction != null) {
          onAction!(id);
        } else {
          AppActionDispatcher.dispatch(context, ref, id, entity, actionContext);
        }
      },
      icon: Icon(spec.icon, size: 18),
      label: Text(spec.labelEn),
    );
  }
}
