import 'package:flutter/material.dart';

enum SettingTileType { nav, toggle, value, action, danger }

class SettingTile extends StatelessWidget {
  const SettingTile.nav({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.onTap,
    this.trailing,
  }) : type = SettingTileType.nav,
       value = null,
       boolValue = null,
       onChanged = null;

  const SettingTile.toggle({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.boolValue,
    required this.onChanged,
  }) : type = SettingTileType.toggle,
       value = null,
       trailing = null,
       onTap = null;

  const SettingTile.value({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.value,
    this.onTap,
  }) : type = SettingTileType.value,
       boolValue = null,
       onChanged = null,
       trailing = null;

  const SettingTile.action({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.onTap,
  }) : type = SettingTileType.action,
       value = null,
       boolValue = null,
       onChanged = null,
       trailing = null;

  const SettingTile.danger({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.onTap,
  }) : type = SettingTileType.danger,
       value = null,
       boolValue = null,
       onChanged = null,
       trailing = null;

  final String title;
  final String? subtitle;
  final Widget? leading;
  final SettingTileType type;
  final String? value;
  final bool? boolValue;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDanger = type == SettingTileType.danger;

    final titleStyle = theme.textTheme.bodyLarge?.copyWith(
      color: isDanger ? theme.colorScheme.error : null,
      fontWeight: isDanger ? FontWeight.w600 : FontWeight.w500,
    );

    final iconColor = isDanger
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    Widget? effectiveTrailing;
    switch (type) {
      case SettingTileType.nav:
        effectiveTrailing =
            trailing ??
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              size: 22,
            );
        break;
      case SettingTileType.toggle:
        effectiveTrailing = Switch(
          value: boolValue ?? false,
          onChanged: onChanged,
        );
        break;
      case SettingTileType.value:
        effectiveTrailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value != null)
              Text(
                value!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              size: 22,
            ),
          ],
        );
        break;
      case SettingTileType.action:
      case SettingTileType.danger:
        effectiveTrailing = trailing;
        break;
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: leading != null
          ? Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDanger
                    ? theme.colorScheme.error.withValues(alpha: 0.12)
                    : theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: IconTheme(
                data: IconThemeData(color: iconColor, size: 20),
                child: leading!,
              ),
            )
          : null,
      title: Text(title, style: titleStyle),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: isDanger
                  ? theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error.withValues(alpha: 0.8),
                    )
                  : theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
            )
          : null,
      trailing: effectiveTrailing,
      onTap: type == SettingTileType.toggle
          ? () => onChanged?.call(!(boolValue ?? false))
          : onTap,
    );
  }
}
