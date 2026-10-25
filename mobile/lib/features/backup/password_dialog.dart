import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

Future<String?> backupPassword(
  BuildContext context, {
  required bool creating,
}) => showDialog<String>(
  context: context,
  builder: (_) => _PasswordDialog(creating: creating),
);

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.creating});
  final bool creating;
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController(),
      _confirmation = TextEditingController();
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
    if (_form.currentState!.validate()) Navigator.pop(context, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        widget.creating ? l.backupPasswordCreate : l.backupPasswordEnter,
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.creating) Text(l.backupPasswordReminder),
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
              if (widget.creating)
                TextFormField(
                  key: const Key('backup-password-confirm'),
                  controller: _confirmation,
                  obscureText: !_visible,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 1024,
                  decoration: InputDecoration(
                    labelText: l.backupPasswordConfirm,
                  ),
                  validator: (v) =>
                      v != _password.text ? l.backupPasswordMismatch : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
            ],
          ),
        ),
      ),
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
    );
  }
}
