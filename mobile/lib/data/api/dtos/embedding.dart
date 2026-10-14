import 'dart:convert';
import 'dart:typed_data';

/// Face identity vectors are 512 x float32 (InsightFace buffalo_l), unit length.
const embeddingDim = 512;
const embeddingBytes = embeddingDim * 4;

/// openapi.yaml `Embedding`: 512 x float32 little-endian, base64 (always 2732 chars).
Float32List decodeEmbedding(String base64Text) {
  final bytes = base64Decode(base64Text);
  if (bytes.length != embeddingBytes) {
    throw FormatException(
      'An embedding must be $embeddingBytes bytes, got ${bytes.length}',
    );
  }
  final view = ByteData.sublistView(bytes);
  final out = Float32List(embeddingDim);
  for (var i = 0; i < embeddingDim; i++) {
    out[i] = view.getFloat32(i * 4, Endian.little);
  }
  return out;
}

String encodeEmbedding(Float32List vector) {
  if (vector.length != embeddingDim) {
    throw ArgumentError(
      'An embedding has $embeddingDim values, got ${vector.length}',
    );
  }
  final out = ByteData(embeddingBytes);
  for (var i = 0; i < embeddingDim; i++) {
    out.setFloat32(i * 4, vector[i], Endian.little);
  }
  return base64Encode(out.buffer.asUint8List());
}

/// 80-float outfit descriptor (torso + legs histograms) as stored in `bodies.appearance`.
Uint8List packFloat32(List<double> values) {
  final out = ByteData(values.length * 4);
  for (var i = 0; i < values.length; i++) {
    out.setFloat32(i * 4, values[i], Endian.little);
  }
  return out.buffer.asUint8List();
}

/// Embedding vector as the BLOB stored in the local database.
Uint8List embeddingToBlob(Float32List v) => packFloat32(v);

Float32List embeddingFromBlob(Uint8List blob) {
  if (blob.length != embeddingBytes) {
    throw FormatException(
      'Stored embedding must be $embeddingBytes bytes, got ${blob.length}',
    );
  }
  final view = ByteData.sublistView(blob);
  final out = Float32List(embeddingDim);
  for (var i = 0; i < embeddingDim; i++) {
    out[i] = view.getFloat32(i * 4, Endian.little);
  }
  return out;
}
