import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../scaffolds/sheet_scaffold.dart';

/// Bottom sheet for password entry and confirmation in backup export/import.
class PasswordSheet extends StatefulWidget {
  const PasswordSheet({super.key, required this.creating});

  final bool creating;

  static Future<String?> show(BuildContext context, {required bool creating}) {
    return SheetScaffold.show<String>(
      context: context,
      builder: (_) => PasswordSheet(creating: creating),
    );
  }

  @override
  State<PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<PasswordSheet> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _visible = false;

  @override
  void dispose() {
    _password.clear();
    _confirmation.clear();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return SheetScaffold(
      title: widget.creating ? l.backupPasswordCreate : l.backupPasswordEnter,
      subtitle: widget.creating ? l.backupPasswordReminder : null,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('backup-password-submit'),
          onPressed: _submit,
          child: Text(widget.creating ? l.next : l.backupUnlock),
        ),
      ],
      child: Form(
        key: _form,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('backup-password'),
                controller: _password,
                autofocus: true,
                obscureText: !_visible,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 1024,
                decoration: InputDecoration(
                  labelText: l.backupPassword,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: l.backupPasswordVisibility,
                    onPressed: () => setState(() => _visible = !_visible),
                    icon: Icon(
                      _visible ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
                validator: (v) => v == null || v.length < 12 || v.length > 1024
                    ? l.backupPasswordLength
                    : null,
                onFieldSubmitted: (_) {
                  if (!widget.creating) _submit();
                },
              ),
              if (widget.creating) ...[
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('backup-password-confirm'),
                  controller: _confirmation,
                  obscureText: !_visible,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 1024,
                  decoration: InputDecoration(
                    labelText: l.backupPasswordConfirm,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v != _password.text ? l.backupPasswordMismatch : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
