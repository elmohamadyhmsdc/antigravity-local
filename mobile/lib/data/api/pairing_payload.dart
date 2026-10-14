import 'lan_host.dart';

/// What the PC's pairing QR (or an `agmobile://pair?...` link) carries:
///
///     agmobile://pair?h=<host>&p=<port>&fp=<cert sha256>&c=<one-time code>
///
/// `fp` is the SHA-256 of the PC's self-signed certificate; the phone pins it.
class PairingPayload {
  const PairingPayload({
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.code,
  });

  final String host;
  final int port;
  final String fingerprint; // 64 lowercase hex chars
  final String code;

  static const scheme = 'agmobile';

  /// Returns null for anything that is not a well-formed pairing link.
  static PairingPayload? tryParse(String? text) {
    if (text == null) return null;
    final uri = Uri.tryParse(text.trim());
    if (uri == null || uri.scheme != scheme || uri.host != 'pair') return null;
    final q = uri.queryParameters;
    final host = q['h']?.trim();
    final port = int.tryParse(q['p'] ?? '');
    final fp = normalizeFingerprint(q['fp']);
    final code = normalizeCode(q['c']);
    if (host == null ||
        !isValidHost(host) ||
        !isLanHost(host) ||
        port == null ||
        port < 1 ||
        port > 65535 ||
        fp == null ||
        code.isEmpty) {
      return null;
    }
    return PairingPayload(host: host, port: port, fingerprint: fp, code: code);
  }

  /// Host names and IPv4/IPv6 literals; nothing that could smuggle a path or credentials.
  static bool isValidHost(String host) =>
      host.isNotEmpty &&
      host.length <= 253 &&
      RegExp(r'^[A-Za-z0-9.\-:]+$').hasMatch(host);

  /// Accepts `AB:CD:..`, `ab cd ..` or plain hex; returns 64 lowercase hex chars or null.
  static String? normalizeFingerprint(String? text) {
    if (text == null) return null;
    final hex = text.replaceAll(RegExp(r'[\s:\-]'), '').toLowerCase();
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(hex) ? hex : null;
  }

  /// `k7qm 3xrd` -> `K7QM-3XRD`; the server ignores case and separators too.
  static String normalizeCode(String? text) {
    final raw = (text ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return raw.length == 8 ? '${raw.substring(0, 4)}-${raw.substring(4)}' : raw;
  }

  @override
  String toString() =>
      'PairingPayload($host:$port, fp ${fingerprint.substring(0, 8)}…)';
}

/// "AB12 CD34 ..." for showing a fingerprint to the user.
String formatFingerprint(String hex, {int group = 4}) {
  final parts = <String>[];
  for (var i = 0; i < hex.length; i += group) {
    parts.add(
      hex
          .substring(i, i + group > hex.length ? hex.length : i + group)
          .toUpperCase(),
    );
  }
  return parts.join(' ');
}
