"""
Unit and integration tests for Phase 4: Reusable Multi-Photo Identity Profile.
Tests bundle schema, hashing, medoid outlier rejection, duplicate suppression,
mixed-identity protection, pose sector classification, and Studio API integration.
"""

import base64
import json
from pathlib import Path
import shutil
import tempfile
import unittest

import jsonschema
import numpy as np

from identity_bundle import (
    ALGORITHM_VERSION,
    POSE_SECTORS,
    SCHEMA_VERSION,
    ExcludedSourceRecord,
    IdentityBundle,
    SourceFaceRecord,
    build_identity_bundle,
    compute_bundle_hash,
    estimate_pose_from_kps,
    get_pose_sector,
    validate_bundle_dict,
)

FIXTURES_DIR = Path(__file__).resolve().parent / "mobile_api" / "contract" / "fixtures" / "identity"


class TestIdentityBundleCore(unittest.TestCase):
    def setUp(self):
        self.schema = json.loads((FIXTURES_DIR / "bundle_schema.json").read_text(encoding="utf-8"))
        self.sample = json.loads((FIXTURES_DIR / "sample_bundle.json").read_text(encoding="utf-8"))
        self.cases = json.loads((FIXTURES_DIR / "cases.json").read_text(encoding="utf-8"))

    def test_schema_validates_sample_bundle(self):
        jsonschema.validate(self.sample, self.schema)
        ok, err = validate_bundle_dict(self.sample)
        self.assertTrue(ok, f"Validation failed: {err}")

    def test_roundtrip_serialization_and_hash_integrity(self):
        bundle = IdentityBundle.from_dict(self.sample)
        self.assertEqual(bundle.schema_version, SCHEMA_VERSION)
        self.assertEqual(bundle.algorithm_version, ALGORITHM_VERSION)
        self.assertEqual(len(bundle.primary_embedding), 512)
        self.assertEqual(bundle.bundle_hash, self.sample["bundle_hash"])
        self.assertEqual(bundle.bundle_hash, compute_bundle_hash(self.sample))

        # JSON serialization roundtrip
        bundle_json = bundle.to_json()
        reloaded = IdentityBundle.from_json(bundle_json)
        self.assertEqual(reloaded.identity_id, bundle.identity_id)
        self.assertEqual(reloaded.bundle_hash, bundle.bundle_hash)
        self.assertEqual(len(reloaded.sources), len(bundle.sources))

    def test_tampered_bundle_hash_mismatch(self):
        tampered = dict(self.sample)
        # Modify an embedding value slightly
        emb_copy = list(tampered["primary_embedding"])
        emb_copy[0] += 0.05
        tampered["primary_embedding"] = emb_copy
        recalculated = compute_bundle_hash(tampered)
        self.assertNotEqual(recalculated, self.sample["bundle_hash"])

    def test_invalid_cases_from_fixture(self):
        for case in self.cases.get("invalid_bundles", []):
            desc = case["description"]
            b = case["bundle"]
            with self.subTest(desc=desc):
                ok, err = validate_bundle_dict(b)
                self.assertFalse(ok, f"Case '{desc}' should have failed validation")

    def test_pose_sector_classification(self):
        self.assertEqual(get_pose_sector(0.0, 0.0), "front")
        self.assertEqual(get_pose_sector(-25.0, 0.0), "left")
        self.assertEqual(get_pose_sector(25.0, 0.0), "right")
        self.assertEqual(get_pose_sector(0.0, 20.0), "up")
        self.assertEqual(get_pose_sector(0.0, -20.0), "down")

    def test_estimate_pose_from_kps(self):
        # 5 standard facial landmarks: left_eye, right_eye, nose, mouth_left, mouth_right
        kps_center = np.array([
            [40.0, 40.0],
            [60.0, 40.0],
            [50.0, 50.0],
            [42.0, 65.0],
            [58.0, 65.0]
        ], dtype=np.float32)
        yaw, pitch, roll = estimate_pose_from_kps(kps_center)
        self.assertAlmostEqual(yaw, 0.0, delta=5.0)
        self.assertAlmostEqual(roll, 0.0, delta=2.0)

    def test_medoid_outlier_rejection(self):
        rng = np.random.default_rng(42)
        def unit_v(v):
            return v / np.linalg.norm(v)

        base_vec = unit_v(rng.standard_normal(512))
        candidates = []

        # 5 legitimate photos with small perturbation
        for i in range(5):
            pert = unit_v(base_vec + 0.01 * rng.standard_normal(512))
            candidates.append({
                "source_id": f"legit_{i}.jpg",
                "embedding": pert.tolist(),
                "pose": {"yaw": float(i * 5), "pitch": 0.0, "roll": 0.0},
                "quality": 0.9,
                "bbox": {"x": 10.0, "y": 10.0, "w": 80.0, "h": 80.0},
            })

        # 1 outlier from completely different person
        outlier_vec = unit_v(rng.standard_normal(512))
        candidates.append({
            "source_id": "intruder.jpg",
            "embedding": outlier_vec.tolist(),
            "pose": {"yaw": 0.0, "pitch": 0.0, "roll": 0.0},
            "quality": 0.9,
            "bbox": {"x": 10.0, "y": 10.0, "w": 80.0, "h": 80.0},
        })

        bundle = build_identity_bundle(candidates, label="Medoid Test")
        self.assertEqual(bundle.metrics["kept_count"], 5)
        self.assertEqual(bundle.metrics["excluded_count"], 1)
        self.assertEqual(bundle.excluded_sources[0].source_id, "intruder.jpg")
        self.assertEqual(bundle.excluded_sources[0].reason, "outlier_dissimilar")

    def test_duplicate_suppression(self):
        rng = np.random.default_rng(99)
        def unit_v(v):
            return v / np.linalg.norm(v)

        vec = unit_v(rng.standard_normal(512))
        candidates = [
            {
                "source_id": "shot1.jpg",
                "embedding": vec.tolist(),
                "pose": {"yaw": 0.0, "pitch": 0.0, "roll": 0.0},
                "quality": 0.95,
                "bbox": {"x": 10.0, "y": 10.0, "w": 80.0, "h": 80.0},
            },
            {
                # Very near duplicate shot in same burst (cosine ~0.99, same pose)
                "source_id": "shot2_burst.jpg",
                "embedding": unit_v(vec + 0.005 * rng.standard_normal(512)).tolist(),
                "pose": {"yaw": 0.5, "pitch": 0.5, "roll": 0.0},
                "quality": 0.85,
                "bbox": {"x": 10.0, "y": 10.0, "w": 80.0, "h": 80.0},
            }
        ]

        bundle = build_identity_bundle(candidates, label="Duplicate Test")
        self.assertEqual(bundle.metrics["kept_count"], 1)
        self.assertEqual(bundle.metrics["excluded_count"], 1)
        self.assertEqual(bundle.excluded_sources[0].source_id, "shot2_burst.jpg")
        self.assertEqual(bundle.excluded_sources[0].reason, "duplicate")

    def test_mixed_identity_protection_with_mock_detector(self):
        from types import SimpleNamespace
        from identity_bundle import build_identity_bundle_from_images

        rng = np.random.default_rng(101)
        def unit_v(v):
            return v / np.linalg.norm(v)

        # Mock detector returning 2 prominent faces
        class MockTwoFacesDetector:
            def get(self, img):
                f1 = SimpleNamespace(
                    bbox=np.array([10, 10, 100, 100]),
                    embedding=unit_v(rng.standard_normal(512)),
                    det_score=0.92,
                    kps=np.zeros((5, 2)),
                    pose=(0, 0, 0)
                )
                f2 = SimpleNamespace(
                    # Second face area is 6400 vs 8100 (> 25% area)
                    bbox=np.array([120, 10, 200, 90]),
                    embedding=unit_v(rng.standard_normal(512)),
                    det_score=0.88,
                    kps=np.zeros((5, 2)),
                    pose=(0, 0, 0)
                )
                return [f1, f2]

        dummy_img = np.zeros((300, 300, 3), dtype=np.uint8)
        bundle = build_identity_bundle_from_images(
            [dummy_img],
            label="Group Photo Test",
            detector=MockTwoFacesDetector()
        )
        self.assertEqual(bundle.metrics["kept_count"], 0)
        self.assertEqual(bundle.metrics["excluded_count"], 1)
        self.assertEqual(bundle.excluded_sources[0].reason, "multiple_faces")

    def test_angle_best_match(self):
        bundle = IdentityBundle.from_dict(self.sample)
        # Test pose targeting left
        left_match = bundle.get_best_embedding_for_pose((-30.0, 0.0, 0.0))
        self.assertEqual(left_match.shape, (512,))
        # Target front
        front_match = bundle.get_best_embedding_for_pose((0.0, 0.0, 0.0))
        self.assertEqual(front_match.shape, (512,))


class TestMobileApiStudioIdentityIntegration(unittest.TestCase):
    def test_validate_artifact_build_identity(self):
        from mobile_api.artifact_jobs import validate_artifact

        caps = {"engines": {"identity_bundle": True}}
        valid_request = {
            "type": "build_identity",
            "params": {"label": "Sarah", "min_quality": 0.4, "top_k": 10},
            "inputs": {"images": ["a" * 64, "b" * 64]}
        }
        # Should not raise
        validate_artifact(valid_request, caps)

        # Invalid: missing images slot
        invalid_inputs = {
            "type": "build_identity",
            "params": {},
            "inputs": {"target": "a" * 64}
        }
        with self.assertRaises(Exception):
            validate_artifact(invalid_inputs, caps)

    def test_validate_reface_accepts_identity_bundle(self):
        from mobile_api.studio_jobs import validate_reface

        caps = {"engines": {"reface": True, "reface_v3": True}, "restorers": ["codeformer", "gpen_bfr_512"]}
        sample = json.loads((FIXTURES_DIR / "sample_bundle.json").read_text(encoding="utf-8"))

        req_with_bundle_param = {
            "type": "reface_image",
            "params": {
                "identity_bundle": sample,
                "quality_profile": "balanced"
            },
            "inputs": {
                "target": "c" * 64
            }
        }
        # Should not raise even though source_faces is omitted
        validate_reface(req_with_bundle_param, caps)

        # Invalid bundle parameter
        bad_req = {
            "type": "reface_image",
            "params": {
                "identity_bundle": {"bad": True},
                "quality_profile": "balanced"
            },
            "inputs": {
                "target": "c" * 64
            }
        }
        with self.assertRaises(Exception):
            validate_reface(bad_req, caps)

    def test_artifact_jobs_build_identity_execution(self):
        from mobile_api.artifact_jobs import run_artifact
        from types import SimpleNamespace
        import cv2

        tmp_dir = Path(tempfile.mkdtemp(prefix="test_identity_job_"))
        try:
            # Create a mock image file
            img_path = tmp_dir / "input.images.0000"
            dummy = np.zeros((200, 200, 3), dtype=np.uint8)
            ok, buf = cv2.imencode(".jpg", dummy)
            img_path.write_bytes(buf.tobytes())

            job = {
                "type": "build_identity",
                "params": {"label": "Runner Test", "min_quality": 0.1, "top_k": 5}
            }

            class MockEngines:
                _face_app = None
                def load(self, faces=True): pass

            ctx = SimpleNamespace(engines=MockEngines())
            
            # Since _face_app is None in test, build_identity_bundle_from_images falls back or reports
            # Let's provide a mock detector on ctx.engines._face_app
            class MockDetector:
                def get(self, img):
                    f = SimpleNamespace(
                        bbox=np.array([20, 20, 100, 100]),
                        embedding=np.ones(512, dtype=np.float32) / np.sqrt(512),
                        det_score=0.95,
                        kps=np.zeros((5, 2)),
                        pose=(0, 0, 0)
                    )
                    return [f]

            ctx.engines._face_app = MockDetector()

            reports = []
            def report(progress, message, **details):
                reports.append((progress, message))

            def stopped():
                return False

            res = run_artifact(job, tmp_dir, report, stopped, ctx)
            self.assertIsNotNone(res)
            self.assertIn("identity_id", res)
            self.assertIn("bundle_hash", res)
            self.assertEqual(res["source_count"], 1)

            bundle_file = tmp_dir / "identity_bundle.json"
            self.assertTrue(bundle_file.exists())
            bundle_obj = IdentityBundle.from_json(bundle_file.read_text(encoding="utf-8"))
            self.assertEqual(bundle_obj.label, "Runner Test")
            self.assertEqual(len(bundle_obj.sources), 1)
        finally:
            shutil.rmtree(tmp_dir, ignore_errors=True)



if __name__ == "__main__":
    unittest.main()
