import 'package:flutter/material.dart';

class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.children,
    this.actions,
    this.bottomBar,
  });

  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: ListView(children: [...children, const SizedBox(height: 32)]),
      bottomNavigationBar: bottomBar,
    );
  }
}
