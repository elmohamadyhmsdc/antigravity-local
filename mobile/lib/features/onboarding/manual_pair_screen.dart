import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/pairing_payload.dart';
import '../../l10n/app_localizations.dart';
import 'pairing_controller.dart';
import 'pairing_scope.dart';

String? _message(AppLocalizations l10n, InputProblem? problem) =>
    switch (problem) {
      null => null,
      InputProblem.hostEmpty => l10n.errHostEmpty,
      InputProblem.hostInvalid => l10n.errHostInvalid,
      InputProblem.hostNotLan => l10n.errHostNotLan,
      InputProblem.portInvalid => l10n.errPortInvalid,
      InputProblem.codeInvalid => l10n.errCodeInvalid,
    };

/// Pairing by typing the PC's address - for routers that block QR-free discovery, or no camera.
class ManualPairScreen extends ConsumerStatefulWidget {
  const ManualPairScreen({super.key, this.initialHost, this.initialPort});
  final String? initialHost;
  final int? initialPort;

  @override
  ConsumerState<ManualPairScreen> createState() => _ManualPairScreenState();
}

class _ManualPairScreenState extends ConsumerState<ManualPairScreen> {
  final _formKey = GlobalKey<FormState>();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '8443');
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _host.text = widget.initialHost ?? '';
    _port.text = '${widget.initialPort ?? 8443}';
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ref
        .read(pairingControllerProvider.notifier)
        .probe(
          host: _host.text.trim(),
          port: int.parse(_port.text.trim()),
          code: _code.text,
        );
  }

  Future<void> _confirmFingerprint(PairingNeedsConfirmation pending) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.confirmFingerprintTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.confirmFingerprintBody),
            const SizedBox(height: 16),
            SelectableText(
              formatFingerprint(pending.fingerprint),
              key: const Key('fingerprint'),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.confirmFingerprintYes),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final controller = ref.read(pairingControllerProvider.notifier);
    ok == true ? await controller.confirm() : controller.reset();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen<PairingState>(pairingControllerProvider, (previous, next) {
      if (next is PairingNeedsConfirmation) _confirmFingerprint(next);
    });
    return PairingScope(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.manualTitle)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(l10n.manualIntro),
              const SizedBox(height: 20),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      key: const Key('host'),
                      controller: _host,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: l10n.manualHostLabel,
                        hintText: l10n.manualHostHint,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) => _message(l10n, validateHost(v ?? '')),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('port'),
                      controller: _port,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: l10n.manualPortLabel,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) => _message(l10n, validatePort(v ?? '')),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('code'),
                      controller: _code,
                      autocorrect: false,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: l10n.manualCodeLabel,
                        hintText: l10n.manualCodeHint,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) => _message(l10n, validateCode(v ?? '')),
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('connect'),
                onPressed: _submit,
                child: Text(l10n.manualConnect),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
