import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router.dart';
import '../../data/api/pairing_payload.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/collection/segmented_bar.dart';
import '../shared/screen_layout.dart';
import 'pairing_controller.dart';
import 'pairing_scope.dart';
import 'qr_scan_screen.dart';

String? _message(AppLocalizations l10n, InputProblem? problem) =>
    switch (problem) {
      null => null,
      InputProblem.hostEmpty => l10n.errHostEmpty,
      InputProblem.hostInvalid => l10n.errHostInvalid,
      InputProblem.hostNotLan => l10n.errHostNotLan,
      InputProblem.portInvalid => l10n.errPortInvalid,
      InputProblem.codeInvalid => l10n.errCodeInvalid,
    };

/// O2 — Unified Pairing Screen with SegmentedBar (QR Scan || Manual Entry).
class PairScreen extends ConsumerStatefulWidget {
  const PairScreen({
    super.key,
    this.initialTab = 0,
    this.initialHost,
    this.initialPort,
  });

  final int initialTab; // 0 = QR, 1 = Manual
  final String? initialHost;
  final int? initialPort;

  @override
  ConsumerState<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends ConsumerState<PairScreen> {
  late int _selectedTab;
  final _formKey = GlobalKey<FormState>();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '8443');
  final _code = TextEditingController();
  String? _lastRejectedQr;

  @override
  void initState() {
    super.initState();
    _selectedTab = (widget.initialHost != null || widget.initialTab == 1)
        ? 1
        : 0;
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

  void _onQrCode(String raw) {
    final state = ref.read(pairingControllerProvider);
    if (state is! PairingIdle && state is! PairingFailed) return;
    final payload = PairingPayload.tryParse(raw);
    if (payload == null) {
      if (_lastRejectedQr != raw) {
        _lastRejectedQr = raw;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).scanNotPairingCode),
            ),
          );
      }
      return;
    }
    ref.read(pairingControllerProvider.notifier).pairFromPayload(payload);
  }

  void _submitManual() {
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
        scrollable: true,
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

    final state = ref.watch(pairingControllerProvider);
    final busy = state is PairingBusy;

    return PairingScope(
      child: Scaffold(
        appBar: AppBar(
          title: Text(_selectedTab == 0 ? l10n.scanTitle : l10n.manualTitle),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => leave(context, Routes.welcome),
          ),
        ),
        bottomNavigationBar: _selectedTab == 1
            ? StickyActionBar(
                child: FilledButton(
                  key: const Key('connect'),
                  onPressed: busy ? null : _submitManual,
                  child: busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.manualConnect),
                ),
              )
            : null,
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedBar<int>(
                segments: [
                  SegmentItem(
                    value: 0,
                    label: l10n.welcomeScan,
                    icon: Icons.qr_code_scanner,
                  ),
                  SegmentItem(
                    value: 1,
                    label: l10n.welcomeManual,
                    icon: Icons.keyboard_outlined,
                  ),
                ],
                selected: _selectedTab,
                onSelected: (i) => setState(() => _selectedTab = i),
              ),
            ),
            Expanded(
              child: _selectedTab == 0
                  ? _buildQrView(context, busy)
                  : _buildManualView(context, busy),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrView(BuildContext context, bool busy) {
    final l10n = AppLocalizations.of(context);
    final scanner = ref.watch(qrScannerBuilderProvider);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: scanner(context, _onQrCode),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(l10n.scanHint, textAlign: TextAlign.center),
        ),
      ],
    );
  }

  Widget _buildManualView(BuildContext context, bool busy) {
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ScreenIntro(title: l10n.manualHeadline, body: l10n.manualIntro),
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
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('port'),
                  controller: _port,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.manualPortLabel,
                    hintText: '8443',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) => _message(l10n, validatePort(v ?? '')),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('code'),
                  controller: _code,
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: l10n.manualCodeLabel,
                    hintText: l10n.manualCodeHint,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) => _message(l10n, validateCode(v ?? '')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
