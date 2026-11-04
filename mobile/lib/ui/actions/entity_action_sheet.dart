import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/actions/action_context.dart';
import '../../domain/actions/action_id.dart';
import '../../domain/actions/action_registry.dart';
import '../../domain/actions/entity_ref.dart';
import '../scaffolds/sheet_scaffold.dart';
import 'action_dispatcher.dart';
import 'action_section.dart';

class EntityActionSheet extends ConsumerWidget {
  const EntityActionSheet({
    super.key,
    required this.entity,
    this.title = 'Actions',
    this.subtitle,
    this.actionContext = ActionContext.defaultContext,
    this.onActionSelected,
    this.supportedActions,
  });

  final EntityRef entity;
  final String title;
  final String? subtitle;
  final ActionContext actionContext;
  final void Function(ActionId id)? onActionSelected;
  final Set<ActionId>? supportedActions;

  static Future<void> show({
    required BuildContext context,
    required EntityRef entity,
    String title = 'Actions',
    String? subtitle,
    ActionContext actionContext = ActionContext.defaultContext,
    void Function(ActionId id)? onActionSelected,
    Set<ActionId>? supportedActions,
  }) {
    return SheetScaffold.show(
      context: context,
      builder: (_) => EntityActionSheet(
        entity: entity,
        title: title,
        subtitle: subtitle,
        actionContext: actionContext,
        onActionSelected: onActionSelected,
        supportedActions: supportedActions,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ActionRegistry.specsFor(
      entity,
      actionContext,
    ).where((spec) => supportedActions?.contains(spec.id) ?? true).toList();
    final quickIds = ActionRegistry.quickActionsFor(
      entity,
      actionContext,
    ).where((id) => available.any((spec) => spec.id == id)).take(3).toSet();
    final quick = available
        .where((spec) => quickIds.contains(spec.id))
        .toList();

    // Keep the primary shortcuts visible; disclose the related secondary actions.
    final groups = <ActionGroup, List<ActionSpec>>{};
    for (final spec in available) {
      if (quickIds.contains(spec.id)) continue;
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
          for (final spec in quick) _tile(context, ref, spec),
          if (quick.isNotEmpty) const Divider(height: 16),
          for (final group in groupOrder) ...[
            if (groups.containsKey(group)) ...[
              ActionSection(
                key: Key('action-section-${group.name}'),
                title: switch (group) {
                  ActionGroup.view => 'View & details',
                  ActionGroup.identity => 'Identity & corrections',
                  ActionGroup.search => 'Find similar',
                  ActionGroup.create => 'Create with this',
                  ActionGroup.manage => 'Organize & export',
                  ActionGroup.danger => 'Remove',
                },
                icon: switch (group) {
                  ActionGroup.view => Icons.visibility_outlined,
                  ActionGroup.identity => Icons.person_outline,
                  ActionGroup.search => Icons.search,
                  ActionGroup.create => Icons.auto_awesome_outlined,
                  ActionGroup.manage => Icons.folder_outlined,
                  ActionGroup.danger => Icons.delete_outline,
                },
                danger: group == ActionGroup.danger,
                children: [
                  for (final spec in groups[group]!) _tile(context, ref, spec),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, ActionSpec spec) {
    final theme = Theme.of(context);
    return Builder(
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
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
    );
  }
}
