"""CPU regressions only: no model loading, GPU, server, or personal media."""
import base64
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import cv2
import numpy as np
from PIL import Image

from mobile_api import reference_reface as rr
from mobile_api.errors import ApiError
from mobile_api.studio_jobs import validate_reface


BOX = dict(x=.25, y=.2, w=.4, h=.5)
CAPS = {"engines": {"reface_reference": True}}


def identity(model="buffalo_l@1", at=0):
    vector = np.zeros(rr.IDENTITY_DIMS[model], dtype="<f4")
    vector[at] = 1
    return dict(model_id=model, embedding=base64.b64encode(vector.tobytes()).decode("ascii"))


def candidate(score=1.0, model="buffalo_l@1", box=None):
    vector = np.zeros(rr.IDENTITY_DIMS[model], dtype=np.float32)
    vector[0], vector[1] = score, np.sqrt(max(0, 1-score*score))
    return dict(model_id=model, embedding=vector, box=box or BOX)


def request(video=False):
    params = dict(experimental_acknowledged=True, source_kind="character", target_kind="character", target_regions=[dict(frame=0, boxes=[BOX])])
    if video:
        params = dict(experimental_acknowledged=True, source_kind="character", target_kind="character", target_identity=identity("ccip-caformer24@1"))
    return dict(type="reface_video_reference" if video else "reface_image_reference",
                params=params, inputs=dict(target="a"*64, source_reference="b"*64))


def make_video(directory, count=3):
    path = Path(directory)/"input.target"
    # VideoWriter uses the extension to choose a container; rename after closing,
    # matching the endpoint's extension-free content-addressed input filename.
    temporary = Path(directory)/"fixture.avi"
    writer = cv2.VideoWriter(str(temporary), cv2.VideoWriter_fourcc(*"MJPG"), 5, (64, 64))
    if not writer.isOpened():
        raise RuntimeError("The installed CPU OpenCV cannot write the MJPG fixture")
    for i in range(count):
        writer.write(np.full((64, 64, 3), 60+i*20, dtype=np.uint8))
    writer.release()
    temporary.replace(path)
    return path


class ReferenceValidationTests(unittest.TestCase):
    def test_experimental_acknowledgment_must_be_explicit_boolean_true(self):
        body = request()
        del body["params"]["experimental_acknowledged"]
        with self.assertRaises(ApiError):
            validate_reface(body, CAPS)
        for value in (False, None, 0, 1, "true", [], {}):
            with self.subTest(value=value):
                body = request()
                body["params"]["experimental_acknowledged"] = value
                with self.assertRaises(ApiError):
                    validate_reface(body, CAPS)

    def test_both_source_kinds_use_actual_images_in_the_shared_reference_route(self):
        for source in ("person", "character"):
            for target in ("person", "character"):
                body = request()
                body["params"].update(source_kind=source, target_kind=target)
                self.assertIsNone(validate_reface(body, CAPS))

    def test_old_embedding_route_still_rejects_ccip(self):
        body = dict(type="reface_image", inputs=dict(target="a"*64),
                    params=dict(model_id="ccip-caformer24@1", source_faces=[]))
        with self.assertRaises(ApiError) as error:
            validate_reface(body, CAPS)
        self.assertEqual(error.exception.code, "model_mismatch")

    def test_reference_route_does_not_accept_vector_as_source_or_uploaded_weights(self):
        for slot in ("source_faces", "lora", "model_path"):
            body = request()
            body["inputs"][slot] = "c"*64
            with self.assertRaises(ApiError):
                validate_reface(body, CAPS)

    def test_photo_requires_explicit_nonempty_frame_zero_regions(self):
        for regions in ([], [dict(frame=1, boxes=[BOX])], [dict(frame=0, boxes=[])]):
            body = request()
            body["params"]["target_regions"] = regions
            with self.assertRaises(ApiError):
                validate_reface(body, CAPS)

    def test_video_accepts_selected_model_aware_identity(self):
        for target, model in (("person", "buffalo_l@1"), ("character", "ccip-caformer24@1")):
            body = request(True)
            body["params"].update(target_kind=target, target_identity=identity(model))
            self.assertIsNone(validate_reface(body, CAPS))

    def test_model_dimensions_and_kind_cannot_be_mixed(self):
        body = request(True)
        body["params"]["target_identity"] = identity("buffalo_l@1")
        with self.assertRaises(ApiError):
            validate_reface(body, CAPS)
        value = identity("ccip-caformer24@1")
        value["model_id"] = "buffalo_l@1"
        with self.assertRaises(ValueError):
            rr.decode_identity(value)

    def test_regions_and_options_reject_out_of_range_or_nonfinite_values(self):
        for change in (dict(steps=True), dict(strength=float("nan")), dict(seed=-1),
                       dict(source_kind="other"), dict(prompt="unsupported body-edit prompt")):
            body = request()
            body["params"].update(change)
            with self.assertRaises(ApiError):
                validate_reface(body, CAPS)
        for invalid in (dict(x=-.1, y=0, w=.2, h=.2), dict(x=.9, y=0, w=.2, h=.2),
                        dict(x=0, y=0, w=True, h=.2)):
            body = request()
            body["params"]["target_regions"][0]["boxes"] = [invalid]
            with self.assertRaises(ApiError):
                validate_reface(body, CAPS)

    def test_missing_engine_is_not_reported_as_supported(self):
        with self.assertRaises(ApiError) as error:
            validate_reface(request(), {"engines": {"reface_reference": False}})
        self.assertEqual(error.exception.code, "engine_unavailable")


class ReferenceSelectionTests(unittest.TestCase):
    def test_selects_only_requested_identity_in_its_own_model_space(self):
        chosen, status = rr.choose_target(identity(), [candidate(.9), candidate(.4)])
        self.assertEqual(status, "matched")
        self.assertEqual(chosen, [BOX])
        chosen, status = rr.choose_target(identity(), [candidate(1, model="ccip-caformer24@1")])
        self.assertEqual((chosen, status), ([], "absent"))

    def test_ambiguous_or_absent_identity_never_reuses_previous_box(self):
        for candidates, expected in (([candidate(.9), candidate(.88)], "ambiguous"),
                                     ([candidate(.3)], "absent"), ([], "absent")):
            self.assertEqual(rr.choose_target(identity(), candidates), ([], expected))

    def test_character_threshold_uses_ccip_without_arcface_conversion(self):
        model = "ccip-caformer24@1"
        self.assertEqual(rr.choose_target(identity(model), [candidate(.79, model)])[0], [])
        self.assertEqual(rr.choose_target(identity(model), [candidate(.9, model)])[1], "matched")

    def test_zero_and_nonfinite_vectors_are_rejected(self):
        for values in (np.zeros(512, dtype="<f4"), np.full(512, np.nan, dtype="<f4")):
            value = dict(model_id="buffalo_l@1", embedding=base64.b64encode(values.tobytes()).decode("ascii"))
            with self.assertRaises(ValueError):
                rr.decode_identity(value)


class ReferenceMaskAndVideoTests(unittest.TestCase):
    def test_predictor_cannot_change_pixels_outside_the_selected_face_ellipse(self):
        image = Image.fromarray(np.random.default_rng(4).integers(0, 255, (80, 96, 3), dtype=np.uint8))
        original = np.asarray(image).copy()
        source = Image.new("RGB", (32, 32), "blue")
        output = rr.apply_regions(image, source, [BOX], {},
                                  lambda crop, mask, ref, params: Image.new("RGB", crop.size, "red"))
        _, mask, _ = rr._face_mask(image.size, BOX)
        outside = np.asarray(mask) == 0
        np.testing.assert_array_equal(np.asarray(output)[outside], original[outside])
        self.assertTrue(np.any(np.asarray(output)[~outside] != original[~outside]))
        np.testing.assert_array_equal(np.asarray(image), original)

    def test_empty_regions_leave_the_entire_frame_unchanged(self):
        image = Image.new("RGB", (32, 32), "blue")
        def must_not_run(*args):
            raise AssertionError("No target means no generation")
        output = rr.apply_regions(image, image, [], {}, must_not_run)
        np.testing.assert_array_equal(output, image)

    def test_tiny_face_region_is_rejected(self):
        with self.assertRaises(ValueError):
            rr._face_mask((32, 32), dict(x=.1, y=.1, w=.01, h=.01))

    def test_video_matches_fresh_frames_and_checkpoints_without_stale_edits(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as tmp:
            directory = Path(tmp)
            video = make_video(directory)
            params = dict(target_identity=identity(), target_kind="person")
            calls = []
            def detect(frame):
                calls.append(True)
                return [candidate(.9)] if len(calls) != 2 else []
            regions = rr.locate_video(video, directory, params, detector=detect)
            self.assertEqual(len(calls), 3)
            self.assertEqual([r["status"] for r in regions["frames"].values()], ["matched", "absent", "matched"])
            self.assertEqual(regions["frames"]["1"]["boxes"], [])
            rr.locate_video(video, directory, params, detector=lambda frame: self.fail("checkpoint should skip detection"))
            used = []
            def predict(crop, mask, source, _params):
                used.append(True)
                return Image.new("RGB", crop.size, "green")
            result = rr.render_video_frames(video, Image.new("RGB", (32, 32), "blue"), directory, params, predict)
            self.assertEqual((result["edited_frames"], result["unchanged_frames"]), (2, 1))
            self.assertEqual(len(used), 2)
            capture = cv2.VideoCapture(str(video))
            try:
                for i in range(3):
                    ok, bgr = capture.read()
                    self.assertTrue(ok)
                    output = np.asarray(Image.open(directory/"reference.frames"/f"frame_{i:09d}.png"))
                    if i == 1:
                        np.testing.assert_array_equal(output, cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
                    else:
                        np.testing.assert_array_equal(output[0, 0], cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)[0, 0])
            finally:
                capture.release()
            rr.render_video_frames(video, Image.new("RGB", (32, 32)), directory, params,
                                   lambda *args: self.fail("completed PNG checkpoints must not regenerate"))

    def test_explicit_only_video_requires_complete_frame_coverage(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as tmp:
            video = make_video(tmp)
            with self.assertRaises(ValueError):
                rr.locate_video(video, tmp, dict(target_regions=[dict(frame=0, boxes=[BOX])]))

    def test_explicit_empty_override_keeps_that_frame_unmodified(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as tmp:
            video = make_video(tmp)
            params = dict(target_identity=identity(), target_regions=[dict(frame=1, boxes=[])])
            data = rr.locate_video(video, tmp, params, detector=lambda frame: [candidate(.9)])
            self.assertEqual(data["frames"]["1"], dict(boxes=[], status="explicit"))

    def test_pause_during_locating_does_not_start_generation(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as tmp:
            job = dict(type="reface_video_reference", params=request(True)["params"])
            with patch.object(rr, "reference_reface_ready", return_value=True), \
                 patch("mobile_api.artifact_jobs.run_process", return_value=-1) as process:
                self.assertIsNone(rr.run_reference_reface(job, Path(tmp), lambda *a, **k: None, lambda: True))
                self.assertEqual(process.call_count, 1)
                self.assertIn("--locate", process.call_args.args[0])


class ReferenceLoaderTests(unittest.TestCase):
    def test_border_detection_boxes_are_clamped_without_fabricating_geometry(self):
        self.assertEqual(rr._clamped_detection_box((-4, -3, 50, 60), 100, 100),
                         dict(x=0.0, y=0.0, w=.5, h=.6))
        self.assertIsNone(rr._clamped_detection_box((101, 0, 110, 20), 100, 100))
        self.assertIsNone(rr._clamped_detection_box((0, 0, float("nan"), 20), 100, 100))

    def test_local_loader_uses_image_conditioning_and_preserves_anime_prompt_mode(self):
        from types import SimpleNamespace
        calls = []
        class Pipeline:
            def __init__(self):
                self.vae = SimpleNamespace(enable_slicing=lambda: calls.append(("vae_slicing", {})))
            @classmethod
            def from_pretrained(cls, path, **kwargs):
                calls.append(("base", kwargs))
                return cls()
            def load_ip_adapter(self, path, **kwargs):
                calls.append(("adapter", kwargs))
            def set_ip_adapter_scale(self, value):
                calls.append(("scale", value))
            def enable_model_cpu_offload(self):
                calls.append(("offload", {}))
            def __call__(self, **kwargs):
                calls.append(("predict", kwargs))
                return SimpleNamespace(images=[kwargs["image"]])
        def encoder(path, **kwargs):
            calls.append(("encoder", kwargs))
            return object()
        fake_torch = SimpleNamespace(float16="fp16", cuda=SimpleNamespace(is_available=lambda: True),
                                     Generator=lambda **kwargs: SimpleNamespace(manual_seed=lambda value: "cpu_seed"))
        modules = {"torch": fake_torch,
                   "diffusers": SimpleNamespace(StableDiffusionInpaintPipeline=Pipeline),
                   "transformers": SimpleNamespace(CLIPVisionModelWithProjection=SimpleNamespace(from_pretrained=encoder))}
        for kind in ("person", "character"):
            calls.clear()
            params = dict(target_kind=kind)
            with patch.dict("sys.modules", modules):
                predictor = rr._pipeline_predictor(params)
                predictor(Image.new("RGB", (64, 64)), Image.new("L", (64, 64), 255),
                          Image.new("RGB", (32, 32), "blue"), params)
            names = [name for name, _ in calls]
            self.assertLess(names.index("adapter"), names.index("offload"))
            for name in ("encoder", "base", "adapter"):
                self.assertTrue(next(v for n, v in calls if n == name)["local_files_only"])
            predicted = next(v for n, v in calls if n == "predict")
            self.assertIn("ip_adapter_image", predicted)
            if kind == "character":
                self.assertIn("anime", predicted["prompt"])
                self.assertNotIn("anime", predicted["negative_prompt"])
            else:
                self.assertIn("human face", predicted["prompt"])

    def test_image_worker_progress_keeps_stage_in_public_details(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as tmp:
            directory = Path(tmp)
            def process(command, work, stopped, on_line):
                on_line('@@reference_reface {"stage":"rendered","progress":0.95}')
                (directory/"reference.render.json").write_text('{"edited_regions":1}', encoding="utf-8")
                Image.new("RGB", (32, 32)).save(directory/"result.png")
                return 0
            report = unittest.mock.Mock()
            with patch.object(rr, "reference_reface_ready", return_value=True), \
                 patch("mobile_api.artifact_jobs.run_process", side_effect=process):
                meta = rr.run_reference_reface(dict(type="reface_image_reference", params=request()["params"]),
                                                directory, report, lambda: False)
            self.assertEqual(report.call_args.kwargs["details"]["stage"], "rendered")
            self.assertEqual(meta["edited_regions"], 1)
            self.assertEqual(meta["identity_fidelity"], "unverified")


class SourcePixelInitializationTests(unittest.TestCase):
    def test_source_pixel_seed_changes_only_the_selected_mask(self):
        crop = Image.new("RGB", (80, 80), "blue")
        reference = Image.new("RGB", (40, 40), "green")
        _, hard, _ = rr._face_mask(crop.size, BOX)
        result = rr.seed_reference_pixels(crop, hard, reference, dict(x=0, y=0, w=1, h=1))
        selected = np.asarray(hard) > 0
        np.testing.assert_array_equal(np.asarray(result)[~selected], np.asarray(crop)[~selected])
        np.testing.assert_array_equal(np.asarray(result)[selected], np.tile(np.array([0, 128, 0]), (selected.sum(), 1)))

    def test_initialization_is_explicit_and_rejects_unsupported_modes(self):
        body = request()
        body["params"]["initialization"] = "source_pixels"
        self.assertIsNone(validate_reface(body, CAPS))
        body["params"]["initialization"] = "invented_landmarks"
        with self.assertRaises(ApiError):
            validate_reface(body, CAPS)


if __name__ == "__main__":
    unittest.main()
