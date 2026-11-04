"""
Fakes for the server tests (test_mobile_api_contract.py, test_mobile_stateless.py): scripted
face/body detections instead of insightface and the ONNX body models, so the whole API can be
driven with FastAPI's TestClient - no GPU, no model files, no network.
"""

import tempfile
from pathlib import Path
from typing import Optional

import numpy as np

import face_quality
import person_linking as pl
from analysis import FrameAnalysis
from outlines import encode_outline

from .auth import AuthStore
from .gpu_guard import GpuGuard
from .pairing import PairingManager
from .workspace import Workspace


class FakeFace:
    """Stand-in for an insightface Face (raw embedding norm ~22 like the real recognition model)."""

    def __init__(self, bbox, embedding, det_score=0.9):
        self.bbox = np.asarray(bbox, dtype=np.float32)
        self.embedding = np.asarray(embedding, dtype=np.float32) * 22.0 / np.linalg.norm(embedding)
        self.det_score = det_score
        x1, y1, x2, y2 = bbox
        w, h = x2 - x1, y2 - y1
        self.kps = np.asarray([[x1 + 0.3 * w, y1 + 0.35 * h], [x1 + 0.7 * w, y1 + 0.35 * h], [x1 + 0.5 * w, y1 + 0.55 * h],
                               [x1 + 0.35 * w, y1 + 0.75 * h], [x1 + 0.65 * w, y1 + 0.75 * h]], dtype=np.float32)
        self.pose = None

    @property
    def embedding_norm(self):
        return float(np.linalg.norm(self.embedding))

    @property
    def normed_embedding(self):
        return self.embedding / self.embedding_norm


class FakeBody:
    def __init__(self, bbox, head_xy):
        self.bbox = np.asarray(bbox, dtype=np.float32)
        self.score = 0.91
        x1, y1, x2, y2 = bbox
        kpts = np.zeros((17, 2), dtype=np.float32)
        scores = np.zeros(17, dtype=np.float32)
        hx, hy = head_xy
        for i, (dx, dy) in enumerate([(0, 0), (-6, -4), (6, -4), (-12, -2), (12, -2)]):
            kpts[i] = (hx + dx, hy + dy)
            scores[i] = 0.9
        for i, (px, py) in [(5, (x1 + 10, y1 + 60)), (6, (x2 - 10, y1 + 60)), (11, (x1 + 15, y1 + 140)),
                            (12, (x2 - 15, y1 + 140))]:
            kpts[i] = px, py
            scores[i] = 0.8
        self.kpts, self.kpt_scores = kpts, scores


def unit(seed: int) -> np.ndarray:
    v = np.random.default_rng(seed).standard_normal(512).astype(np.float32)
    return v / np.linalg.norm(v)


def _fake_octagon(bbox):
    x1, y1, x2, y2 = [float(v) for v in bbox[:4]]
    w, h = x2 - x1, y2 - y1
    return np.array([
        [x1 + 0.3 * w, y1],
        [x1 + 0.7 * w, y1],
        [x2, y1 + 0.3 * h],
        [x2, y1 + 0.7 * h],
        [x1 + 0.7 * w, y2],
        [x1 + 0.3 * w, y2],
        [x1, y1 + 0.7 * h],
        [x1, y1 + 0.3 * h],
    ], dtype=np.float32)


class FakeEngines:
    """Two faces (one good, one that fails the detector gate) and one body tied to the first face."""
    model_id = "buffalo_l@1"
    sensitive_ready = True
    embeddings_ready = True
    garments_ready = True

    def __init__(self):
        self.calls = []
        self.fail_with: Optional[Exception] = None

    def load(self):
        pass

    def analyze(self, img, options) -> FrameAnalysis:
        self.calls.append(options)
        if self.fail_with is not None:
            raise self.fail_with
        h, w = img.shape[:2]
        faces = [FakeFace((60, 50, 200, 230), unit(1)), FakeFace((w - 60, 60, w - 36, 90), unit(2), det_score=0.4)]
        quality = [face_quality.assess(f, None) for f in faces]
        passes = [face_quality.passes_gate(f, options.min_face_quality, q["quality_score"])
                  for f, q in zip(faces, quality)]
        bodies = [FakeBody((20, 30, 260, 460), (130, 90))] if options.detect_bodies else []
        appearances = [pl.appearance_descriptor(img, b.bbox, b.kpts, b.kpt_scores) for b in bodies]
        pairs = pl.associate_faces_bodies([f.bbox for f in faces], bodies, face_kps=[f.kps for f in faces]) if bodies else []
        f_out = []
        b_out = []
        if getattr(options, "outlines", False):
            f_out = [_fake_octagon(f.bbox) if p else None for f, p in zip(faces, passes)]
            b_out = [_fake_octagon(b.bbox) for b in bodies]
        result = FrameAnalysis(faces=faces, quality=quality, passes_gate=passes, bodies=bodies,
                               appearances=appearances, pairs=list(pairs), image_w=w, image_h=h,
                               timings_ms={"detect": 1.5, "quality": 0.5},
                               face_outlines=f_out, body_outlines=b_out)
        if getattr(options, "sensitive", False) or getattr(options, "body_embeddings", False):
            result.sensitive = self.fake_regions(bodies)
        if getattr(options, "body_embeddings", False):
            result.body_embeddings = [self.fake_embedding(i) for i, _ in enumerate(bodies)]
        return result

    @staticmethod
    def fake_embedding(index: int) -> dict:
        import base64
        v = np.random.default_rng(100 + index).standard_normal(384).astype("<f4")
        v /= np.linalg.norm(v)
        return {"chest_embedding": base64.b64encode(v.tobytes()).decode("ascii"), "buttocks_embedding": None,
                "morphology": {"scale_source": "kpts", "breast_span_ratio": 0.31, "areola_contrast": 0.22,
                               "skin_tone_lab": [62.5, 12.1, 18.4], "micro_marks": [[0.11, 0.42, 0.05]]}}

    @staticmethod
    def fake_regions(bodies):
        """One chest region on the first body, one unattached belly region."""
        regions = [{"label": "BELLY_COVERED", "exposed": False, "score": 0.5, "bbox": [400.0, 300.0, 460.0, 350.0],
                    "body_index": None}]
        if bodies:
            regions.insert(0, {"label": "FEMALE_BREAST_EXPOSED", "exposed": True, "score": 0.91,
                               "bbox": [100.0, 140.0, 170.0, 190.0], "body_index": 0})
        return regions

    def compute_sensitive(self, img, bodies: list, embeddings: bool = False):
        if self.fail_with is not None:
            raise self.fail_with
        self.sensitive_calls = getattr(self, "sensitive_calls", []) + [bodies]
        regions = self.fake_regions(bodies)
        if not embeddings:
            return regions
        return {"regions": regions, "bodies": [self.fake_embedding(i) for i, _ in enumerate(bodies)]}

    def compute_garments(self, img, bodies: list) -> list:
        if self.fail_with is not None:
            raise self.fail_with
        self.garment_calls = getattr(self, "garment_calls", []) + [bodies]
        return [[{"tag": "t-shirt", "category": "upper", "score": 0.8123},
                 {"tag": "jeans", "category": "lower", "score": 0.4412}] if i % 2 == 0 else []
                for i, _ in enumerate(bodies)]

    def compute_outlines(self, img, targets: list) -> list:
        if self.fail_with is not None:
            raise self.fail_with
        outlines = []
        for t in targets:
            bbox = t.get("bbox", {})
            if isinstance(bbox, dict):
                x = float(bbox.get("x", 0))
                y = float(bbox.get("y", 0))
                w = float(bbox.get("w", 0))
                h = float(bbox.get("h", 0))
                b = (x, y, x + w, y + h)
            else:
                b = (bbox[0], bbox[1], bbox[0] + bbox[2], bbox[1] + bbox[3])
            outlines.append(encode_outline(_fake_octagon(b)))
        return outlines


class FakeProbe:
    def __init__(self):
        self.value = {
            "gpu": {"name": "Fake GPU", "vram_total_mb": 6144, "vram_free_mb": 5000},
            "engines": {"reface": True, "reface_v3": True, "reface_v2": True, "dfm_models": ["RTM_WF_224"], "undress": True,
                        "lora_train": True, "lora_generate": True, "body_detection": True, "character_detection": True,
                        "sensitive_detection": True, "body_embeddings": True, "garment_tags": True},
            "restorers": ["codeformer"],
            "reface_profiles": {"fast": {"restorer": "none", "restore_size": 512, "use_parser": False,
                                     "photo_ms_per_face": 140, "video_ms_per_face": 90},
                                "balanced": {"restorer": "codeformer", "restore_size": 512, "use_parser": True,
                                         "photo_ms_per_face": 300, "video_ms_per_face": 255},
                                "detail": {"restorer": "codeformer", "restore_size": 512, "use_parser": True,
                                       "photo_ms_per_face": 660, "video_ms_per_face": 415}},
            "lora_base_checkpoints": ["sd15_realistic_base"],
        }

    def snapshot(self):
        return self.value


class Clock:
    def __init__(self, now: float = 1_000_000.0):
        self.now = now

    def __call__(self) -> float:
        return self.now

    def advance(self, seconds: float):
        self.now += seconds


def make_test_context(root: Optional[Path] = None, *, engines=None, probe=None, clock: Optional[Clock] = None,
                      blob_cache_bytes: int = 64 * 1024 * 1024, max_upload_bytes: int = 32 * 1024 * 1024,
                      name: str = "Test PC", cert=None):
    """A ServerContext over a temporary workspace (the caller deletes `root`)."""
    from .app import ServerContext  # needs FastAPI; the fakes above do not
    root = Path(root) if root else Path(tempfile.mkdtemp(prefix="mobile_api_test_"))
    ws = Workspace(root / "mobile_workspace", blob_cache_bytes=blob_cache_bytes, max_upload_bytes=max_upload_bytes)
    ws.prepare()
    auth = AuthStore(ws.devices_path, server_name=name)
    pairing = PairingManager(auth, clock=clock or Clock())
    return ServerContext(
        workspace=ws, auth=auth, pairing=pairing,
        gpu=GpuGuard(root / "dashboard_jobs", ws.jobs_dir),
        engines=engines or FakeEngines(), probe=probe or FakeProbe(), cert=cert,
        host_addresses=["192.168.1.20"])
