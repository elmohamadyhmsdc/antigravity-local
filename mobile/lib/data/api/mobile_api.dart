import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'bulk_transfer.dart';
import 'dtos/analyze.dart';
import 'dtos/grouping.dart';
import 'dtos/system.dart';
import 'pinned_http.dart';
import 'dtos/jobs.dart';
import 'video_api.dart';
import 'studio_api.dart';
import 'resource_api.dart';
import 'dtos/resources.dart';

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

class HttpMobileApi implements MobileApi, VideoApi, StudioApi, ResourceApi {
  HttpMobileApi(
    this.session, {
    Dio? dio,
    Duration connectTimeout = const Duration(seconds: 8),
  }) : _dio =
           dio ??
           createPinnedDio(
             host: session.host,
             port: session.port,
             fingerprint: session.fingerprint,
             token: session.token,
             connectTimeout: connectTimeout,
           );

  ServerSession session;
  final Dio _dio;

  void close() => _dio.close(force: false);

  @override
  Future<ResourceSnapshot> resources() => _guard(() async {
    final response = await _dio.get('/v1/resources');
    return ResourceSnapshot.fromJson(_json(response));
  });

  void resetTransport() {
    final old = _dio.httpClientAdapter;
    _dio.httpClientAdapter = pinnedHttpAdapter(session.fingerprint);
    old.close(force: false);
  }

  void relocate(ServerSession next) {
    if (next.serverId != session.serverId ||
        next.token != session.token ||
        next.fingerprint.toLowerCase() != session.fingerprint.toLowerCase()) {
      throw StateError('Reconnection cannot change a paired PC identity.');
    }
    session = next;
    _dio.options.baseUrl = baseUrl(next.host, next.port);
    resetTransport();
  }

  @override
  String get serverId => session.serverId;

  @override
  Future<({bool exists, int offset})> blobOffset(String sha256) =>
      _guard(() async {
        final r = await _dio.head(
          '/v1/blobs/$sha256',
          options: Options(validateStatus: (s) => s == 200 || s == 404),
        );
        final exists = r.statusCode == 200;
        final offset = int.tryParse(
          r.headers.value(exists ? 'content-length' : 'upload-offset') ?? '',
        );
        if (offset == null || offset < 0) {
          throw const FormatException('Invalid upload offset');
        }
        return (exists: exists, offset: offset);
      });

  @override
  Future<int> uploadChunk(
    String sha256,
    Uint8List bytes,
    int offset,
    int total,
  ) => _guard(() async {
    final r = await _dio.put(
      '/v1/blobs/$sha256',
      data: binaryUploadBody(bytes),
      options: Options(
        contentType: 'application/octet-stream',
        headers: {
          Headers.contentLengthHeader: bytes.length,
          'Content-Range': 'bytes $offset-${offset + bytes.length - 1}/$total',
        },
        validateStatus: (s) => s == 201 || s == 202 || s == 204 || s == 409,
      ),
    );
    if (r.statusCode == 204 || r.statusCode == 201) return total;
    final next = int.tryParse(r.headers.value('upload-offset') ?? '');
    if (next == null || next < 0 || next > total) {
      throw const FormatException('Invalid upload offset');
    }
    return next;
  });

  @override
  Future<VideoJobStatus> createVideoJob(Map<String, dynamic> request) => _guard(
    () async => VideoJobStatus.fromJson(
      _json(await _dio.post('/v1/jobs', data: request)),
    ),
  );

  @override
  Future<VideoJobStatus> videoJob(String id) => _guard(
    () async => VideoJobStatus.fromJson(
      _json(await _dio.get('/v1/jobs/${Uri.encodeComponent(id)}')),
    ),
  );

  @override
  Future<VideoJobStatus> controlVideoJob(
    String id, {
    required bool resume,
  }) => _guard(
    () async => VideoJobStatus.fromJson(
      _json(
        await _dio.post(
          '/v1/jobs/${Uri.encodeComponent(id)}/${resume ? 'resume' : 'stop'}',
        ),
      ),
    ),
  );

  @override
  Future<VideoResultFile> videoResult(String id) => _guard(() async {
    final json = _json(
      await _dio.get('/v1/jobs/${Uri.encodeComponent(id)}/result'),
    );
    final files = json['files'];
    if (files is! List || files.length != 1) {
      throw const FormatException('Expected one video result');
    }
    return VideoResultFile.fromJson(
      Map<String, dynamic>.from(files.single as Map),
    );
  });

  @override
  Future<void> downloadVideoResult(String id, File target) => _guard(() async {
    await downloadResumableFile(
      _dio,
      '/v1/jobs/${Uri.encodeComponent(id)}/result/detections.ndjson',
      target,
    );
  });

  @override
  Future<void> deleteVideoJob(String id) => _guard(() async {
    await _dio.delete('/v1/jobs/${Uri.encodeComponent(id)}');
  });

  @override
  Future<StudioJobStatus> createStudioJob(Map<String, dynamic> request) =>
      _guard(
        () async => StudioJobStatus.fromJson(
          _json(await _dio.post('/v1/jobs', data: request)),
        ),
      );

  @override
  Future<StudioJobStatus> studioJob(String id) => _guard(
    () async => StudioJobStatus.fromJson(
      _json(await _dio.get('/v1/jobs/${Uri.encodeComponent(id)}')),
    ),
  );

  @override
  Future<StudioJobStatus> controlStudioJob(
    String id, {
    required bool resume,
  }) => _guard(
    () async => StudioJobStatus.fromJson(
      _json(
        await _dio.post(
          '/v1/jobs/${Uri.encodeComponent(id)}/${resume ? 'resume' : 'stop'}',
        ),
      ),
    ),
  );

  @override
  Stream<StudioJobStatus> studioEvents(String id) async* {
    final cancel = CancelToken();
    try {
      final response = await _guard(
        () => _dio.get<ResponseBody>(
          '/v1/jobs/${Uri.encodeComponent(id)}/events',
          cancelToken: cancel,
          options: Options(
            responseType: ResponseType.stream,
            receiveTimeout: const Duration(seconds: 45),
          ),
        ),
      );
      final lines = response.data!.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (line.startsWith('data: ')) {
          yield StudioJobStatus.fromJson(
            jsonDecode(line.substring(6)) as Map<String, dynamic>,
          );
        }
      }
    } catch (e) {
      throw _toApiException(e);
    } finally {
      cancel.cancel();
    }
  }

  @override
  Future<StudioResultFile> studioResult(String id) => _guard(() async {
    final json = _json(
      await _dio.get('/v1/jobs/${Uri.encodeComponent(id)}/result'),
    );
    final files = json['files'];
    if (files is! List || files.length != 1 || files.single is! Map) {
      throw const FormatException('Expected one Studio result');
    }
    return StudioResultFile.fromJson(
      Map<String, dynamic>.from(files.single as Map),
    );
  });

  @override
  Future<void> downloadStudioResult(
    String id,
    String name,
    File target,
  ) => _guard(() async {
    await downloadResumableFile(
      _dio,
      '/v1/jobs/${Uri.encodeComponent(id)}/result/${Uri.encodeComponent(name)}',
      target,
    );
  });

  @override
  Future<Health> health() => _guard(
    () async => Health.fromJson(
      _json(
        await _dio.get(
          '/v1/health',
          options: Options(
            headers: {'Authorization': null},
            receiveTimeout: const Duration(seconds: 5),
          ),
        ),
      ),
    ),
  );

  @override
  Future<Capabilities> capabilities() => _guard(
    () async => Capabilities.fromJson(
      _json(
        await _dio.get(
          '/v1/capabilities',
          options: Options(receiveTimeout: const Duration(seconds: 6)),
        ),
      ),
    ),
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
