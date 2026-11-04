import 'package:flutter/material.dart';

/// Related secondary actions stay discoverable without a wall of buttons.
class ActionSection extends StatelessWidget {
  const ActionSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.initiallyExpanded = false,
    this.danger = false,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> children;
  final bool initiallyExpanded, danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      leading: Icon(icon, color: danger ? scheme.error : scheme.primary),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      shape: const Border(),
      collapsedShape: const Border(),
      children: children,
    );
  }
}
