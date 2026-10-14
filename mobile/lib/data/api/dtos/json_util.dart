// Tiny helpers for the hand-written DTOs. They throw FormatException with the field
// name so a contract drift shows up as "faces[0].bbox.x: expected a number" rather
// than a bare cast error.

T field<T>(Map<String, dynamic> json, String key, [String path = '']) {
  final value = json[key];
  if (value is T) return value;
  throw FormatException(
    '${path.isEmpty ? '' : '$path.'}$key: expected $T, got ${value.runtimeType}',
  );
}

double number(Map<String, dynamic> json, String key, [String path = '']) {
  final value = json[key];
  if (value is num) return value.toDouble();
  throw FormatException(
    '${path.isEmpty ? '' : '$path.'}$key: expected a number, got ${value.runtimeType}',
  );
}

double? optionalNumber(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  throw FormatException(
    '$key: expected a number or null, got ${value.runtimeType}',
  );
}

int integer(Map<String, dynamic> json, String key, [String path = '']) {
  final value = json[key];
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  throw FormatException(
    '${path.isEmpty ? '' : '$path.'}$key: expected an integer, got ${value.runtimeType}',
  );
}

Map<String, dynamic> map(Object? value, String path) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('$path: expected an object, got ${value.runtimeType}');
}

List<dynamic> list(Object? value, String path) {
  if (value is List<dynamic>) return value;
  throw FormatException('$path: expected a list, got ${value.runtimeType}');
}

List<double> numbers(Object? value, String path) => list(value, path)
    .map(
      (e) => e is num
          ? e.toDouble()
          : throw FormatException('$path: expected numbers'),
    )
    .toList();
