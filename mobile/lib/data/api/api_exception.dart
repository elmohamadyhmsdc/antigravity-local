/// Everything that can go wrong talking to the PC, as one type. `code` is the server's
/// envelope code (`gpu_busy`, `unauthorized`, `invalid_code`, ...) or one of the client-side
/// codes below.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.retryable = false,
    this.statusCode,
    this.retryAfter,
    this.missing = const [],
  });

  /// openapi.yaml `Error` envelope: `{error: {code, message, retryable}}` (+ `missing` for 409 missing_blobs).
  factory ApiException.fromEnvelope(
    int statusCode,
    Object? body, {
    Duration? retryAfter,
  }) {
    if (body is Map && body['error'] is Map) {
      final e = body['error'] as Map;
      return ApiException(
        code: '${e['code'] ?? 'internal'}',
        message: '${e['message'] ?? 'The PC returned an error.'}',
        retryable: e['retryable'] == true,
        statusCode: statusCode,
        retryAfter: retryAfter,
        missing: [for (final m in (body['missing'] as List? ?? const [])) '$m'],
      );
    }
    return ApiException(
      code: 'internal',
      message: 'The PC answered with HTTP $statusCode.',
      retryable: statusCode >= 500,
      statusCode: statusCode,
      retryAfter: retryAfter,
    );
  }

  static const networkCode = 'network';
  static const timeoutCode = 'timeout';
  static const certificateCode = 'certificate_mismatch';
  static const badResponseCode = 'bad_response';

  factory ApiException.network(String message) =>
      ApiException(code: networkCode, message: message, retryable: true);

  factory ApiException.timeout() => const ApiException(
    code: timeoutCode,
    message: 'The PC did not answer in time.',
    retryable: true,
  );

  factory ApiException.certificate() => const ApiException(
    code: certificateCode,
    message:
        'This is not the PC you paired with (its certificate changed). Pair again from the PC.',
  );

  factory ApiException.badResponse(String detail) => ApiException(
    code: badResponseCode,
    message: 'The PC sent something this app does not understand: $detail',
  );

  final String code;
  final String message;
  final bool retryable;
  final int? statusCode;
  final Duration? retryAfter;
  final List<String> missing;

  bool get isGpuBusy => code == 'gpu_busy';
  bool get isUnauthorized => code == 'unauthorized';
  bool get isOffline => code == networkCode || code == timeoutCode;

  @override
  String toString() =>
      'ApiException($code${statusCode == null ? '' : ' / $statusCode'}): $message';
}
