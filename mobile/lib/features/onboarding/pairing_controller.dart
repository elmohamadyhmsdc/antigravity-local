import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_exception.dart';
import '../../data/api/lan_host.dart';
import '../../data/api/mobile_api.dart';
import '../../data/api/pairing_payload.dart';
import '../../providers.dart';

sealed class PairingState {
  const PairingState();
}

class PairingIdle extends PairingState {
  const PairingIdle();
}

class PairingBusy extends PairingState {
  const PairingBusy(this.host);
  final String host;
}

/// Typed-address pairing: the PC presented this certificate; the user must compare it with the PC's screen.
class PairingNeedsConfirmation extends PairingState {
  const PairingNeedsConfirmation({
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.code,
  });
  final String host;
  final int port;
  final String fingerprint;
  final String code;
}

class PairingFailed extends PairingState {
  const PairingFailed(this.error);
  final ApiException error;
}

class PairingDone extends PairingState {
  const PairingDone(this.session);
  final ServerSession session;
}

enum InputProblem {
  hostEmpty,
  hostInvalid,
  hostNotLan,
  portInvalid,
  codeInvalid,
}

InputProblem? validateHost(String text) {
  final host = text.trim();
  if (host.isEmpty) return InputProblem.hostEmpty;
  if (!PairingPayload.isValidHost(host)) return InputProblem.hostInvalid;
  if (!isLanHost(host)) return InputProblem.hostNotLan;
  return null;
}

InputProblem? validatePort(String text) {
  final port = int.tryParse(text.trim());
  return port == null || port < 1 || port > 65535
      ? InputProblem.portInvalid
      : null;
}

InputProblem? validateCode(String text) =>
    PairingPayload.normalizeCode(text).length == 9
    ? null
    : InputProblem.codeInvalid;

class PairingController extends Notifier<PairingState> {
  @override
  PairingState build() => const PairingIdle();

  void reset() => state = const PairingIdle();

  /// QR code / link: the fingerprint is already known and pinned from the start.
  Future<void> pairFromPayload(PairingPayload payload) async {
    if (state is PairingBusy) return;
    state = PairingBusy(payload.host);
    await _complete(
      host: payload.host,
      port: payload.port,
      fingerprint: payload.fingerprint,
      code: payload.code,
    );
  }

  /// Typed address: look at the certificate first and ask the user to confirm it.
  Future<void> probe({
    required String host,
    required int port,
    required String code,
  }) async {
    if (state is PairingBusy) return;
    state = PairingBusy(host);
    try {
      final fingerprint = await ref
          .read(pairingApiProvider)
          .probeFingerprint(host, port);
      state = PairingNeedsConfirmation(
        host: host,
        port: port,
        fingerprint: fingerprint,
        code: PairingPayload.normalizeCode(code),
      );
    } on ApiException catch (e) {
      state = PairingFailed(e);
    }
  }

  /// The user compared the fingerprint with the PC and said it matches.
  Future<void> confirm() async {
    final pending = state;
    if (pending is! PairingNeedsConfirmation) return;
    state = PairingBusy(pending.host);
    await _complete(
      host: pending.host,
      port: pending.port,
      fingerprint: pending.fingerprint,
      code: pending.code,
    );
  }

  Future<void> _complete({
    required String host,
    required int port,
    required String fingerprint,
    required String code,
  }) async {
    try {
      final deviceName = await ref.read(deviceNameProvider.future);
      final response = await ref
          .read(pairingApiProvider)
          .completePairing(
            host: host,
            port: port,
            fingerprint: fingerprint,
            code: code,
            deviceName: deviceName,
          );
      final session = ServerSession(
        serverId: response.serverId,
        name: response.serverName,
        host: host,
        port: port,
        fingerprint: fingerprint,
        token: response.token,
      );
      await ref.read(sessionProvider.notifier).pair(session);
      state = PairingDone(session);
    } on ApiException catch (e) {
      state = PairingFailed(e);
    }
  }
}

final pairingControllerProvider =
    NotifierProvider.autoDispose<PairingController, PairingState>(
      PairingController.new,
    );
