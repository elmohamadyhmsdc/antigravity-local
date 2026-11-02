import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class TabRootScaffold extends StatelessWidget {
  const TabRootScaffold({
    super.key,
    required this.title,
    required this.body,
    this.primaryAction,
    this.bottom,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.onSettingsTap,
  });

  final Widget title;
  final Widget body;
  final Widget? primaryAction;
  final PreferredSizeWidget? bottom;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final VoidCallback? onSettingsTap;

  @override
  Widget build(BuildContext context) {
    assert(() {
      if (primaryAction is PopupMenuButton) {
        throw FlutterError(
          'TabRootScaffold prohibits overflow menus (⋮). Use in-context sheets instead.',
        );
      }
      return true;
    }(), 'TabRootScaffold assertion');

    return Scaffold(
      appBar: AppBar(
        title: title,
        actions: [
          ?primaryAction,
          IconButton(
            key: const Key('tab-root-settings'),
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: onSettingsTap ?? () => context.push('/settings'),
          ),
        ],
        bottom: bottom,
      ),
      body: body,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}
