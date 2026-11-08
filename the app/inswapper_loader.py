"""Load INSwapper without deserializing a second copy of all its weights.

InsightFace's constructor calls onnx.load after creating the ORT session just
to read graph.initializer[-1] (the 512 x 512 embedding map). Seek past the
other protobuf fields and deserialize only that tensor, then use InsightFace's
unchanged inference and paste-back methods.
"""

from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
from onnx import numpy_helper
from insightface.model_zoo.inswapper import INSwapper


def _varint(source, end):
    value = 0
    for shift in range(0, 70, 7):
        if source.tell() >= end:
            raise ValueError("Truncated ONNX protobuf varint")
        byte = source.read(1)
        if not byte:
            raise ValueError("Truncated ONNX protobuf varint")
        value |= (byte[0] & 0x7f) << shift
        if byte[0] < 0x80:
            return value
    raise ValueError("Invalid ONNX protobuf varint")


def _message_fields(source, start, end):
    """Yield length-delimited field spans; skip payloads without reading them.

    ONNX uses protobuf wire types 0, 1, 2 and 5 (no legacy groups).
    Bounds are checked before seeking so truncated files fail explicitly.
    """
    source.seek(start)
    while source.tell() < end:
        tag = _varint(source, end)
        number, wire = tag >> 3, tag & 7
        if number == 0:
            raise ValueError("Invalid ONNX protobuf field number")
        if wire == 0:
            _varint(source, end)
            continue
        if wire == 2:
            length = _varint(source, end)
        elif wire in (1, 5):
            length = 8 if wire == 1 else 4
        else:
            raise ValueError(f"Unsupported ONNX protobuf wire type: {wire}")
        offset = source.tell()
        if offset + length > end:
            raise ValueError("Truncated ONNX protobuf field")
        if wire == 2:
            yield number, offset, length
        source.seek(offset + length)


def read_embedding_map(model_path):
    """Read the same last initializer as InsightFace, using about 1 MB of I/O."""
    graph_field = onnx.ModelProto.DESCRIPTOR.fields_by_name["graph"].number
    initializer_field = onnx.GraphProto.DESCRIPTOR.fields_by_name["initializer"].number
    with open(model_path, "rb") as source:
        end = source.seek(0, 2)
        graph = next(((offset, length) for number, offset, length in
                      _message_fields(source, 0, end) if number == graph_field), None)
        if graph is None:
            raise ValueError("INSwapper ONNX model has no graph")
        start, length = graph
        last = None
        for number, offset, size in _message_fields(source, start, start + length):
            if number == initializer_field:
                last = (offset, size)
        if last is None:
            raise ValueError("INSwapper ONNX model has no embedding map")
        offset, size = last
        # The map is 1 MiB. Refuse an unexpected large weight tensor rather
        # than recreating the full-model allocation this loader avoids.
        if size > 16 * 1024 * 1024:
            raise ValueError("INSwapper embedding map is unexpectedly large")
        source.seek(offset)
        tensor = onnx.TensorProto()
        tensor.ParseFromString(source.read(size))
    emap = numpy_helper.to_array(tensor, base_dir=str(Path(model_path).parent))
    if emap.shape != (512, 512) or emap.dtype.kind != "f" or not np.isfinite(emap).all():
        raise ValueError("INSwapper embedding map must be a finite 512 x 512 float matrix")
    return emap


class LowMemoryINSwapper(INSwapper):
    """InsightFace inference with a bounded-memory constructor."""

    def __init__(self, model_path, providers=None):
        self.model_file = str(model_path)
        self.emap = read_embedding_map(model_path)
        self.input_mean, self.input_std = 0.0, 255.0
        self.session = ort.InferenceSession(self.model_file, providers=providers)
        inputs, outputs = self.session.get_inputs(), self.session.get_outputs()
        if (len(inputs) != 2 or len(outputs) != 1 or
                len(inputs[0].shape) != 4 or list(inputs[0].shape[2:]) != [128, 128]):
            raise ValueError("Unexpected INSwapper model inputs or outputs")
        self.input_names = [item.name for item in inputs]
        self.output_names = [item.name for item in outputs]
        self.input_shape = inputs[0].shape
        self.input_size = tuple(self.input_shape[2:4][::-1])
        print(f"[SWAP] INSwapper loaded with streamed embedding map: {self.input_shape}")
