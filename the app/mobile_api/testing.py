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


class FakeEngines:
    """Two faces (one good, one that fails the detector gate) and one body tied to the first face."""
    model_id = "buffalo_l@1"

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
        return FrameAnalysis(faces=faces, quality=quality, passes_gate=passes, bodies=bodies,
                             appearances=appearances, pairs=list(pairs), image_w=w, image_h=h,
                             timings_ms={"detect": 1.5, "quality": 0.5})


class FakeProbe:
    def __init__(self):
        self.value = {
            "gpu": {"name": "Fake GPU", "vram_total_mb": 6144, "vram_free_mb": 5000},
            "engines": {"reface": True, "reface_v3": True, "reface_v2": True, "dfm_models": ["RTM_WF_224"], "undress": True,
                        "lora_train": True, "lora_generate": True, "body_detection": True, "character_detection": True},
            "restorers": ["codeformer"],
            "reface_profiles": {"fast": {"restorer": "none", "restore_size": 512, "use_parser": False},
                                "balanced": {"restorer": "codeformer", "restore_size": 512, "use_parser": True},
                                "detail": {"restorer": "codeformer", "restore_size": 512, "use_parser": True}},
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
