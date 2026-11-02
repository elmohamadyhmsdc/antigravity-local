import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/actions/action_context.dart';
import '../../domain/actions/action_id.dart';
import '../../domain/actions/action_registry.dart';
import '../../domain/actions/entity_ref.dart';
import '../actions/action_dispatcher.dart';
import '../scaffolds/sheet_scaffold.dart';

class BulkActionBar extends ConsumerWidget {
  const BulkActionBar({
    super.key,
    required this.selectedEntities,
    this.actionContext = ActionContext.defaultContext,
    this.onActionDispatched,
  });

  final List<EntityRef> selectedEntities;
  final ActionContext actionContext;
  final void Function(ActionId id)? onActionDispatched;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (selectedEntities.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final available = ActionRegistry.bulkActionsFor(
      selectedEntities,
      actionContext,
    );
    if (available.isEmpty) return const SizedBox.shrink();

    final visible = available.take(4).toList();
    final overflow = available.length > 4
        ? available.skip(4).toList()
        : <ActionId>[];

    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final id in visible) ...[
                _buildActionButton(context, ref, id),
              ],
              if (overflow.isNotEmpty)
                IconButton(
                  tooltip: 'More actions',
                  icon: const Icon(Icons.more_horiz),
                  onPressed: () => _showOverflowSheet(context, ref, overflow),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, WidgetRef ref, ActionId id) {
    final spec = ActionRegistry.spec(id);
    final theme = Theme.of(context);
    final color = spec.isDanger ? theme.colorScheme.error : null;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _trigger(context, ref, id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(spec.icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(
              spec.labelEn,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _trigger(BuildContext context, WidgetRef ref, ActionId id) {
    if (onActionDispatched != null) {
      onActionDispatched!(id);
    } else {
      for (final entity in selectedEntities) {
        AppActionDispatcher.dispatch(context, ref, id, entity, actionContext);
      }
    }
  }

  void _showOverflowSheet(
    BuildContext context,
    WidgetRef ref,
    List<ActionId> overflowActions,
  ) {
    SheetScaffold.show(
      context: context,
      builder: (ctx) => SheetScaffold(
        title: 'Actions',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final id in overflowActions) ...[
              Builder(
                builder: (tileCtx) {
                  final spec = ActionRegistry.spec(id);
                  return ListTile(
                    leading: Icon(
                      spec.icon,
                      color: spec.isDanger
                          ? Theme.of(tileCtx).colorScheme.error
                          : null,
                    ),
                    title: Text(
                      spec.labelEn,
                      style: TextStyle(
                        color: spec.isDanger
                            ? Theme.of(tileCtx).colorScheme.error
                            : null,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _trigger(context, ref, id);
                    },
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
