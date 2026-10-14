import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'dtos/analyze.dart';
import 'dtos/grouping.dart';
import 'dtos/system.dart';
import 'pinned_http.dart';

/// The PC a phone is paired with, and the secret that proves it.
class ServerSession {
  const ServerSession({
    required this.serverId,
    required this.name,
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.token,
  });

  final String serverId;
  final String name;
  final String host;
  final int port;
  final String fingerprint;
  final String token;

  ServerSession copyWith({String? name, String? host, int? port}) =>
      ServerSession(
        serverId: serverId,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        fingerprint: fingerprint,
        token: token,
      );
}

/// Calls the paired PC needs (all authenticated except [health]).
abstract interface class MobileApi {
  Future<Health> health();
  Future<Capabilities> capabilities();
  Future<AnalyzeImageResponse> analyzeImage(
    Uint8List jpegBytes, {
    String filename = 'photo.jpg',
    AnalyzeOptions options = const AnalyzeOptions(),
  });

  /// POST /v1/grouping/plan - a pure function on the PC (nothing is stored there).
  Future<GroupingPlanResponse> groupingPlan(GroupingPlanRequest request);
}

/// The calls made before a token exists.
abstract interface class PairingApi {
  /// The fingerprint of whatever certificate [host]:[port] presents (to be confirmed by the user).
  Future<String> probeFingerprint(String host, int port);

  Future<PairResponse> completePairing({
    required String host,
    required int port,
    required String fingerprint,
    required String code,
    required String deviceName,
  });
}

ApiException _toApiException(Object error) {
  if (error is ApiException) return error;
  if (error is DioException) {
    final response = error.response;
    if (response != null) {
      final retryAfter = int.tryParse(
        response.headers.value('retry-after') ?? '',
      );
      return ApiException.fromEnvelope(
        response.statusCode ?? 500,
        response.data,
        retryAfter: retryAfter == null ? null : Duration(seconds: retryAfter),
      );
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException.timeout();
      case DioExceptionType.badCertificate:
        return ApiException.certificate();
      default:
        break;
    }
    final inner = error.error;
    if (inner is HandshakeException || inner is TlsException) {
      return ApiException.certificate();
    }
    if (inner is SocketException) {
      return ApiException.network(
        'Could not reach the PC. Is the server running and is this phone on the same Wi-Fi? (${inner.osError?.message ?? inner.message})',
      );
    }
    return ApiException.network(error.message ?? 'Network error');
  }
  if (error is FormatException) return ApiException.badResponse(error.message);
  return ApiException.network('$error');
}

/// A pooled keep-alive connection the PC already closed (it idles connections out): dart:io only
/// notices when the next request fails before any response byte. Nothing reached the server, so
/// every call below (all stateless or idempotent) is safe to repeat once on a fresh connection.
bool isStaleConnectionError(Object error) {
  if (error is! DioException) return false;
  final inner = error.error;
  return inner is HttpException &&
      inner.message.contains(
        'Connection closed before full header was received',
      );
}

Future<T> _guard<T>(Future<T> Function() call) async {
  try {
    try {
      return await call();
    } catch (e) {
      if (!isStaleConnectionError(e)) rethrow;
      return await call();
    }
  } catch (e) {
    throw _toApiException(e);
  }
}

Map<String, dynamic> _json(Response<dynamic> response) {
  final data = response.data;
  if (data is Map<String, dynamic>) return data;
  throw ApiException.badResponse('expected a JSON object');
}

class HttpMobileApi implements MobileApi {
  HttpMobileApi(this.session, {Dio? dio})
    : _dio =
          dio ??
          createPinnedDio(
            host: session.host,
            port: session.port,
            fingerprint: session.fingerprint,
            token: session.token,
          );

  final ServerSession session;
  final Dio _dio;

  @override
  Future<Health> health() =>
      _guard(() async => Health.fromJson(_json(await _dio.get('/v1/health'))));

  @override
  Future<Capabilities> capabilities() => _guard(
    () async =>
        Capabilities.fromJson(_json(await _dio.get('/v1/capabilities'))),
  );

  @override
  Future<AnalyzeImageResponse> analyzeImage(
    Uint8List jpegBytes, {
    String filename = 'photo.jpg',
    AnalyzeOptions options = const AnalyzeOptions(),
  }) {
    return _guard(() async {
      final form = FormData.fromMap({
        'image': MultipartFile.fromBytes(
          jpegBytes,
          filename: filename,
          contentType: DioMediaType('image', 'jpeg'),
        ),
        'options': jsonEncode(options.toJson()),
      });
      final response = await _dio.post('/v1/analyze/image', data: form);
      return AnalyzeImageResponse.fromJson(_json(response));
    });
  }

  @override
  Future<GroupingPlanResponse> groupingPlan(GroupingPlanRequest request) async {
    // base64 + JSON + gzip of a few thousand embeddings is real work: keep it off the UI isolate
    final body = await Isolate.run(request.encodeGzip);
    return _guard(() async {
      final response = await _dio.post(
        '/v1/grouping/plan',
        data: body,
        options: Options(
          contentType: 'application/json',
          headers: {'Content-Encoding': 'gzip'},
          receiveTimeout: const Duration(minutes: 10),
        ),
      );
      return GroupingPlanResponse.fromJson(_json(response));
    });
  }
}

class HttpPairingApi implements PairingApi {
  const HttpPairingApi();

  @override
  Future<String> probeFingerprint(String host, int port) =>
      _guard(() => probeCertificateFingerprint(host, port));

  @override
  Future<PairResponse> completePairing({
    required String host,
    required int port,
    required String fingerprint,
    required String code,
    required String deviceName,
  }) {
    return _guard(() async {
      final dio = createPinnedDio(
        host: host,
        port: port,
        fingerprint: fingerprint,
      );
      final response = await dio.post(
        '/v1/pair/complete',
        data: PairRequest(code: code, deviceName: deviceName).toJson(),
      );
      return PairResponse.fromJson(_json(response));
    });
  }
}
