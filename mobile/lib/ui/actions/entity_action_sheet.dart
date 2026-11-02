import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/actions/action_context.dart';
import '../../domain/actions/action_id.dart';
import '../../domain/actions/action_registry.dart';
import '../../domain/actions/entity_ref.dart';
import '../scaffolds/sheet_scaffold.dart';
import 'action_dispatcher.dart';

class EntityActionSheet extends ConsumerWidget {
  const EntityActionSheet({
    super.key,
    required this.entity,
    this.title = 'Actions',
    this.subtitle,
    this.actionContext = ActionContext.defaultContext,
    this.onActionSelected,
  });

  final EntityRef entity;
  final String title;
  final String? subtitle;
  final ActionContext actionContext;
  final void Function(ActionId id)? onActionSelected;

  static Future<void> show({
    required BuildContext context,
    required EntityRef entity,
    String title = 'Actions',
    String? subtitle,
    ActionContext actionContext = ActionContext.defaultContext,
    void Function(ActionId id)? onActionSelected,
  }) {
    return SheetScaffold.show(
      context: context,
      builder: (_) => EntityActionSheet(
        entity: entity,
        title: title,
        subtitle: subtitle,
        actionContext: actionContext,
        onActionSelected: onActionSelected,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final available = ActionRegistry.specsFor(entity, actionContext);

    // Group specs by group in strict order: view -> identity -> search -> create -> manage -> danger
    final groups = <ActionGroup, List<ActionSpec>>{};
    for (final spec in available) {
      groups.putIfAbsent(spec.group, () => []).add(spec);
    }

    const groupOrder = [
      ActionGroup.search,
      ActionGroup.identity,
      ActionGroup.view,
      ActionGroup.create,
      ActionGroup.manage,
      ActionGroup.danger,
    ];

    return SheetScaffold(
      title: title,
      subtitle: subtitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final group in groupOrder) ...[
            if (groups.containsKey(group)) ...[
              for (final spec in groups[group]!) ...[
                Builder(
                  builder: (context) {
                    final legacyKey = switch (spec.id) {
                      ActionId.assignPerson => 'box-assign',
                      ActionId.notThisPerson => 'box-reject',
                      ActionId.changeKind => 'box-kind',
                      ActionId.nameGroupPose => 'box-name-group-pose',
                      ActionId.boxEquipment => 'box-equipment',
                      ActionId.similarPose => 'box-similar-pose',
                      ActionId.similarColours => 'box-similar-colours',
                      ActionId.namePose => 'box-name-pose',
                      ActionId.markTattoo => 'box-mark-tattoo',
                      ActionId.nameOutfit => 'box-name-outfit',
                      ActionId.delete => 'box-delete',
                      ActionId.open => 'box-open-person',
                      _ => null,
                    };
                    final tile = ListTile(
                      key: Key('action-sheet-${spec.id.name}'),
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      leading: Icon(
                        spec.icon,
                        color: spec.isDanger ? theme.colorScheme.error : null,
                      ),
                      title: Text(
                        spec.labelEn,
                        style: TextStyle(
                          color: spec.isDanger ? theme.colorScheme.error : null,
                          fontWeight: spec.isDanger ? FontWeight.w600 : null,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        if (onActionSelected != null) {
                          onActionSelected!(spec.id);
                        } else {
                          AppActionDispatcher.dispatch(
                            context,
                            ref,
                            spec.id,
                            entity,
                            actionContext,
                          );
                        }
                      },
                    );
                    if (legacyKey != null) {
                      return KeyedSubtree(key: Key(legacyKey), child: tile);
                    }
                    return tile;
                  },
                ),
              ],
              if (group != groupOrder.last && groups.containsKey(group))
                Divider(
                  height: 1,
                  indent: 56,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}
