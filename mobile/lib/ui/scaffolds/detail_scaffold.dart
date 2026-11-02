import 'package:flutter/material.dart';

class DetailScaffold extends StatelessWidget {
  const DetailScaffold({
    super.key,
    required this.title,
    required this.body,
    this.header,
    this.actions,
    this.bottomBar,
    this.bottom,
    this.floatingActionButton,
  });

  final Widget title;
  final Widget body;
  final Widget? header;
  final List<Widget>? actions;
  final Widget? bottomBar;
  final PreferredSizeWidget? bottom;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: title, actions: actions, bottom: bottom),
      body: Column(
        children: [
          ?header,
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: bottomBar,
      floatingActionButton: floatingActionButton,
    );
  }
}
