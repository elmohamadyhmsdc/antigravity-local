import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/router.dart';
import '../../data/api/pairing_payload.dart';
import '../../l10n/app_localizations.dart';
import 'pairing_controller.dart';
import 'pairing_scope.dart';

typedef QrCodeCallback = void Function(String rawValue);
typedef QrScannerBuilder =
    Widget Function(BuildContext context, QrCodeCallback onCode);

/// The camera view. A provider so widget tests can replace the platform view.
final qrScannerBuilderProvider = Provider<QrScannerBuilder>(
  (ref) =>
      (context, onCode) => _CameraScanner(onCode: onCode),
);

class _CameraScanner extends StatefulWidget {
  const _CameraScanner({required this.onCode});

  final QrCodeCallback onCode;

  @override
  State<_CameraScanner> createState() => _CameraScannerState();
}

class _CameraScannerState extends State<_CameraScanner> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MobileScanner(
      controller: _controller,
      onDetect: (capture) {
        for (final barcode in capture.barcodes) {
          final value = barcode.rawValue;
          if (value != null) {
            widget.onCode(value);
            return;
          }
        }
      },
      errorBuilder: (context, error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(l10n.scanCameraDenied, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// Pairing by QR: the code carries the address, the pinned certificate fingerprint and the one-time code.
class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  String? _lastRejected;

  void _onCode(String raw) {
    final state = ref.read(pairingControllerProvider);
    if (state is! PairingIdle && state is! PairingFailed) return;
    final payload = PairingPayload.tryParse(raw);
    if (payload == null) {
      if (_lastRejected != raw) {
        _lastRejected = raw;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scanner = ref.watch(qrScannerBuilderProvider);
    return PairingScope(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.scanTitle)),
        body: Column(
          children: [
            Expanded(child: scanner(context, _onCode)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.scanHint, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.pushReplacement(Routes.manual),
                    child: Text(l10n.scanEnterManually),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
