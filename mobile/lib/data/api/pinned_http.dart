import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'api_exception.dart';

/// SHA-256 of a certificate's DER bytes, lowercase hex - the same value the PC prints and
/// puts in the pairing QR (`tls.fingerprint_of_cert`).
String certificateFingerprint(X509Certificate cert) =>
    sha256.convert(cert.der).toString();

bool _sameFingerprint(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// A Dio adapter that trusts exactly ONE certificate: the one whose SHA-256 is [fingerprint].
///
/// No system CA is trusted (`withTrustedRoots: false`), so the TLS handshake always ends in
/// `badCertificateCallback`, which accepts the server only when the certificate it presents has
/// the pinned fingerprint. Host names are deliberately not checked: the PC's address changes
/// (DHCP), the pin is what proves identity. A mismatch aborts the handshake before a single
/// byte of the request - including the bearer token - is sent.
HttpClientAdapter pinnedHttpAdapter(String fingerprint) {
  final pinned = fingerprint.toLowerCase();
  return IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient(
        context: SecurityContext(withTrustedRoots: false),
      );
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) =>
              _sameFingerprint(certificateFingerprint(cert), pinned);
      return client;
    },
  );
}

/// Connects once, takes whatever certificate the server offers and returns its fingerprint.
/// Used when pairing by typing an address: the user must compare it with the PC's screen
/// before the code is sent (trust on first use, confirmed by a human).
Future<String> probeCertificateFingerprint(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  SecureSocket? socket;
  try {
    socket = await SecureSocket.connect(
      host,
      port,
      context: SecurityContext(withTrustedRoots: false),
      onBadCertificate: (_) => true,
      timeout: timeout,
    );
    final cert = socket.peerCertificate;
    if (cert == null) {
      throw ApiException.badResponse('the PC did not present a certificate');
    }
    return certificateFingerprint(cert);
  } on TimeoutException {
    throw ApiException.timeout();
  } on SocketException catch (e) {
    throw ApiException.network(_explain(e, host, port));
  } on HandshakeException {
    throw ApiException.badResponse(
      '$host:$port is not an Antigravity server (TLS handshake failed)',
    );
  } finally {
    socket?.destroy();
  }
}

String _explain(SocketException e, String host, int port) =>
    'Could not reach $host:$port. Is the PC server running and is this phone on the same Wi-Fi? (${e.osError?.message ?? e.message})';

String baseUrl(String host, int port) =>
    'https://${host.contains(':') ? '[$host]' : host}:$port';

/// A Dio client for one paired PC. The token (when given) is sent as `Authorization: Bearer`.
Dio createPinnedDio({
  required String host,
  required int port,
  required String fingerprint,
  String? token,
  Duration connectTimeout = const Duration(seconds: 8),
  Duration receiveTimeout = const Duration(seconds: 90),
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl(host, port),
      connectTimeout: connectTimeout,
      sendTimeout: const Duration(minutes: 5),
      receiveTimeout: receiveTimeout,
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
    ),
  );
  dio.httpClientAdapter = pinnedHttpAdapter(fingerprint);
  return dio;
}
