"""Memory and compatibility regressions; synthetic ONNX, no inference models."""

import io
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import numpy as np
import onnx
from onnx import helper, numpy_helper

from inswapper_loader import LowMemoryINSwapper, read_embedding_map
from reface_engine import RefaceEngine
from reface_engine_v3 import RefaceEngineV3


def varint(value):
    result = bytearray()
    while value > 127:
        result.append((value & 127) | 128)
        value >>= 7
    result.append(value)
    return bytes(result)


class BoundedReader(io.BytesIO):
    """Reject full-file/weight reads and measure actual payload I/O."""

    def __init__(self, payload):
        super().__init__(payload)
        self.bytes_read = 0

    def read(self, size=-1):
        if size < 0 or size > 2 * 1024 * 1024:
            raise AssertionError(f"Unbounded or oversized model read: {size}")
        result = super().read(size)
        self.bytes_read += len(result)
        return result


class EmbeddingMapTests(unittest.TestCase):
    def setUp(self):
        self.emap = np.random.default_rng(19).random((512, 512), dtype=np.float32)

    def model_bytes(self, emap=None):
        tensors = [numpy_helper.from_array(np.zeros(1024 * 1024, np.float32), "large_weight"),
                   numpy_helper.from_array(self.emap if emap is None else emap, "emap")]
        graph = helper.make_graph([], "synthetic", [], [], initializer=tensors)
        return helper.make_model(graph).SerializeToString()

    def test_skips_weights_and_reads_only_embedding_tensor_without_onnx_load(self):
        source = BoundedReader(self.model_bytes())
        with patch("inswapper_loader.open", return_value=source), \
                patch("onnx.load", side_effect=MemoryError("full model must not be read")):
            actual = read_embedding_map("synthetic.onnx")
        np.testing.assert_array_equal(actual, self.emap)
        self.assertLess(source.bytes_read, self.emap.nbytes + 4096)

    def test_handles_unknown_fields_and_multibyte_lengths(self):
        # Unknown varint, fixed64, fixed32 and length-delimited fields before
        # the graph must be skipped just as protobuf deserialization would.
        prefix = (varint(100 << 3) + varint(300) +
                  varint((101 << 3) | 1) + b"12345678" +
                  varint((102 << 3) | 5) + b"1234" +
                  varint((103 << 3) | 2) + varint(300) + b"x" * 300)
        with patch("inswapper_loader.open", return_value=BoundedReader(prefix + self.model_bytes())):
            np.testing.assert_array_equal(read_embedding_map("synthetic.onnx"), self.emap)

    def test_missing_graph_and_initializer_are_explicit_errors(self):
        empty_graph = helper.make_model(helper.make_graph([], "empty", [], []))
        for payload, message in [(b"", "no graph"),
                                 (empty_graph.SerializeToString(), "no embedding map")]:
            with self.subTest(message=message), \
                    patch("inswapper_loader.open", return_value=BoundedReader(payload)), \
                    self.assertRaisesRegex(ValueError, message):
                read_embedding_map("synthetic.onnx")

    def test_truncated_or_invalid_fields_fail_without_large_reads(self):
        for payload in (b"\x3a\x80", b"\x3a\xff\xff\x7f", b"\x00", b"\x3b",
                        b"\x80" * 10, self.model_bytes()[:-12]):
            with self.subTest(prefix=payload[:8]), \
                    patch("inswapper_loader.open", return_value=BoundedReader(payload)), \
                    self.assertRaises(ValueError):
                read_embedding_map("synthetic.onnx")

    def test_rejects_invalid_embedding_matrix(self):
        for emap in (np.zeros((2, 2), np.float32), np.zeros((512, 512), np.int32),
                     np.full((512, 512), np.nan, np.float32)):
            with self.subTest(shape=emap.shape, dtype=emap.dtype), \
                    patch("inswapper_loader.open", return_value=BoundedReader(self.model_bytes(emap))), \
                    self.assertRaisesRegex(ValueError, "512 x 512 float matrix"):
                read_embedding_map("synthetic.onnx")

    def test_oversized_last_tensor_is_rejected_before_reading(self):
        size = 17 * 1024 * 1024
        initializer = b"\x2a" + varint(size) + b"\x00" * size
        payload = b"\x3a" + varint(len(initializer)) + initializer
        with patch("inswapper_loader.open", return_value=BoundedReader(payload)), \
                self.assertRaisesRegex(ValueError, "unexpectedly large"):
            read_embedding_map("synthetic.onnx")

    def test_file_loading_and_inherited_inference_preserve_identity_projection(self):
        calls = []
        inputs = [SimpleNamespace(name="target", shape=[1, 3, 128, 128]),
                  SimpleNamespace(name="source", shape=[1, 512])]
        def run(outputs, feeds):
            calls.append((outputs, feeds))
            return [np.full((1, 3, 128, 128), .5, np.float32)]
        session = SimpleNamespace(get_inputs=lambda: inputs,
                                  get_outputs=lambda: [SimpleNamespace(name="output")], run=run)
        providers = ["CPUExecutionProvider"]
        with tempfile.TemporaryDirectory() as tmp:
            model_path = Path(tmp) / "synthetic.onnx"
            model_path.write_bytes(self.model_bytes())
            with patch("inswapper_loader.ort.InferenceSession", return_value=session) as create, \
                    patch("onnx.load", side_effect=MemoryError):
                swapper = LowMemoryINSwapper(model_path, providers)
            create.assert_called_once_with(str(model_path), providers=providers)
        target = SimpleNamespace(kps=np.array([[40, 45], [85, 45], [64, 65], [46, 85], [82, 85]], np.float32))
        embedding = np.ones(512, np.float32) / np.sqrt(np.float32(512))
        image = np.full((128, 128, 3), 100, np.uint8)
        crop, matrix = swapper.get(image, target, SimpleNamespace(normed_embedding=embedding), paste_back=False)
        expected = embedding.reshape(1, -1) @ self.emap
        expected /= np.linalg.norm(expected)
        np.testing.assert_allclose(calls[0][1]["source"], expected)
        self.assertEqual(calls[0][1]["target"].shape, (1, 3, 128, 128))
        self.assertEqual(crop.shape, (128, 128, 3))
        self.assertEqual(matrix.shape, (2, 3))
        pasted = swapper.get(image, target, SimpleNamespace(normed_embedding=embedding), paste_back=True)
        self.assertEqual(pasted.shape, image.shape)
        self.assertTrue(np.any(pasted != image))


class SwapperInitializationTests(unittest.TestCase):
    def init_v3(self, wanted, alternate=None, error=None):
        # Leave the actual base swapper-loading branch intact; stub face
        # analysis, restoration and masks so no inference models are loaded.
        analyzer = SimpleNamespace(prepare=lambda **kwargs: None)
        fallback = object()
        with tempfile.TemporaryDirectory() as tmp, \
                patch("reface_engine.FaceAnalysis", return_value=analyzer), \
                patch.object(RefaceEngine, "_load_inswapper", return_value=fallback) as load_base, \
                patch("reface_engine_v3.resolve_swapper_name", return_value=wanted), \
                patch("reface_engine_v3.load_swapper", return_value=alternate, side_effect=error) as load_alt, \
                patch("reface_engine_v3.FaceRestorer", return_value=SimpleNamespace(available=False)), \
                patch("reface_engine_v3.FaceMasker"), \
                patch("reface_engine_v3.FaceCompositor"):
            engine = RefaceEngineV3(output_dir=tmp, restorer="none", swapper=wanted)
        return engine, load_base, load_alt, fallback

    def test_selected_alternative_never_loads_inswapper(self):
        alternate = object()
        engine, load_base, load_alt, _ = self.init_v3("hyperswap_1b_256", alternate=alternate)
        load_base.assert_not_called()
        load_alt.assert_called_once()
        self.assertIs(engine.swapper, alternate)
        self.assertEqual(engine.swapper_name, "hyperswap_1b_256")

    def test_failed_or_missing_alternative_loads_inswapper_once(self):
        for error in (None, RuntimeError("unavailable")):
            with self.subTest(error=error):
                engine, load_base, _, fallback = self.init_v3("hyperswap_1b_256", error=error)
                load_base.assert_called_once()
                self.assertIs(engine.swapper, fallback)
                self.assertEqual(engine.swapper_name, "inswapper_128")

    def test_explicit_inswapper_does_not_load_alternative(self):
        engine, load_base, load_alt, fallback = self.init_v3("inswapper_128")
        load_base.assert_called_once()
        load_alt.assert_not_called()
        self.assertIs(engine.swapper, fallback)


if __name__ == "__main__":
    unittest.main(verbosity=2)
