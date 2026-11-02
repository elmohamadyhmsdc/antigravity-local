import 'package:flutter/material.dart';

import '../scaffolds/sheet_scaffold.dart';

class NameSheet extends StatefulWidget {
  const NameSheet({
    super.key,
    required this.title,
    this.initialValue,
    this.hintText,
    this.confirmLabel = 'Save',
  });

  final String title;
  final String? initialValue;
  final String? hintText;
  final String confirmLabel;

  static Future<String?> show({
    required BuildContext context,
    required String title,
    String? initialValue,
    String? hintText,
    String confirmLabel = 'Save',
  }) {
    return SheetScaffold.show<String>(
      context: context,
      builder: (_) => NameSheet(
        title: title,
        initialValue: initialValue,
        hintText: hintText,
        confirmLabel: confirmLabel,
      ),
    );
  }

  @override
  State<NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<NameSheet> {
  late final TextEditingController _controller;
  bool _canSave = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
    _canSave = _controller.text.trim().isNotEmpty;
    _controller.addListener(_updateCanSave);
  }

  void _updateCanSave() {
    final next = _controller.text.trim().isNotEmpty;
    if (next != _canSave) {
      setState(() => _canSave = next);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_updateCanSave);
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      Navigator.of(context).pop(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: widget.title,
      scrollable: false,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const Key('name-sheet-save'),
          onPressed: _canSave ? _submit : null,
          child: Text(widget.confirmLabel),
        ),
      ],
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: TextField(
          key: const Key('name-sheet-input'),
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: widget.hintText ?? 'Enter name',
            border: const OutlineInputBorder(),
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => _controller.clear(),
                  )
                : null,
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
    );
  }
}
