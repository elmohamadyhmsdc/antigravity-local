"""
Person (body) detection + body keypoints for the gallery, on onnxruntime only.

- Detector: YOLOX-m trained on COCO + Human-Art (OpenMMLab rtmposev1 ONNX SDK
  export, NMS built in). Input 640x640 letterboxed raw BGR, pad 114.
- Keypoints: RTMPose-m body7, 17 COCO keypoints via SimCC. Input 256x192 RGB,
  ImageNet mean/std, bbox padded 1.25x. The keypoints let person_linking tie a
  face to the right body in crowded photos (nose/eyes/ears land inside the face
  box) and pick torso/leg regions for the outfit descriptor.

Both models are fetched automatically on first use (~145 MB total) into
models/body/. `venv` has CPU-only torch, so this deliberately avoids torch.
"""

import os
import time
import zipfile
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, List, Optional

import cv2
import numpy as np

MODELS_DIR = Path(__file__).parent / "models" / "body"

_SDK = "https://download.openmmlab.com/mmpose/v1/projects/rtmposev1/onnx_sdk/"
MODEL_SPECS = {
    "person": {
        "file": "yolox_m_humanart.onnx",
        "url": _SDK + "yolox_m_8xb8-300e_humanart-c2c7a14a.zip",
        "zip_size": 94223081,
        "onnx_size": 101400344,
    },
    "pose": {
        "file": "rtmpose_m_body7.onnx",
        "url": _SDK + "rtmpose-m_simcc-body7_pt-body7_420e-256x192-e48f03d0_20230504.zip",
        "zip_size": 50799818,
        "onnx_size": 54330655,
    },
}

KPT_NAMES = ("nose", "l_eye", "r_eye", "l_ear", "r_ear", "l_shoulder", "r_shoulder",
             "l_elbow", "r_elbow", "l_wrist", "r_wrist", "l_hip", "r_hip",
             "l_knee", "r_knee", "l_ankle", "r_ankle")


def _download(url: str, dest: Path, expected_size: int, log: Callable[[str], None]) -> None:
    part = dest.with_name(dest.name + ".part")
    with urllib.request.urlopen(url, timeout=30) as resp, open(part, "wb") as out:
        total = int(resp.headers.get("Content-Length") or expected_size)
        done, next_report = 0, 0.1
        while True:
            chunk = resp.read(1 << 20)
            if not chunk:
                break
            out.write(chunk)
            done += len(chunk)
            if total and done / total >= next_report:
                log(f"[body models] {dest.name}: {done / 1e6:.0f}/{total / 1e6:.0f} MB")
                next_report += 0.1
    if part.stat().st_size != expected_size:
        size = part.stat().st_size
        part.unlink(missing_ok=True)
        raise IOError(f"{dest.name}: got {size} bytes, expected {expected_size}")
    os.replace(part, dest)


def ensure_model(key: str, log: Callable[[str], None] = print, models_dir: Path = None) -> Path:
    """Path to a ready ONNX file, downloading + unzipping it if needed.
    Downloads go through a .part file with a size check and one retry."""
    spec = MODEL_SPECS[key]
    models_dir = Path(models_dir or MODELS_DIR)
    target = models_dir / spec["file"]
    if target.exists() and target.stat().st_size == spec["onnx_size"]:
        return target
    models_dir.mkdir(parents=True, exist_ok=True)
    zip_path = models_dir / (Path(spec["file"]).stem + ".zip")
    last_err = None
    for attempt in (1, 2):
        try:
            if not (zip_path.exists() and zip_path.stat().st_size == spec["zip_size"]):
                log(f"[body models] downloading {spec['file']} ({spec['zip_size'] / 1e6:.0f} MB, attempt {attempt})")
                _download(spec["url"], zip_path, spec["zip_size"], log)
            with zipfile.ZipFile(zip_path) as zf:
                member = next(n for n in zf.namelist() if n.endswith("end2end.onnx"))
                part = target.with_name(target.name + ".part")
                with zf.open(member) as src, open(part, "wb") as out:
                    while True:
                        chunk = src.read(1 << 20)
                        if not chunk:
                            break
                        out.write(chunk)
            if part.stat().st_size != spec["onnx_size"]:
                part.unlink(missing_ok=True)
                raise IOError(f"{spec['file']}: unexpected size after unzip")
            os.replace(part, target)
            zip_path.unlink(missing_ok=True)
            log(f"[body models] ready: {target}")
            return target
        except Exception as e:  # network hiccup or truncated zip: start clean once more
            last_err = e
            zip_path.unlink(missing_ok=True)
            time.sleep(1)
    raise RuntimeError(f"Could not fetch body model '{key}': {last_err}")


def default_providers() -> list:
    import onnxruntime as ort
    if "CUDAExecutionProvider" in ort.get_available_providers():
        return [("CUDAExecutionProvider", {"device_id": 0,
                                           "arena_extend_strategy": "kSameAsRequested",
                                           "gpu_mem_limit": 2 * 1024 ** 3}),
                "CPUExecutionProvider"]
    return ["CPUExecutionProvider"]


def _session(path: Path, providers):
    import onnxruntime as ort
    try:
        return ort.InferenceSession(str(path), providers=providers)
    except Exception:
        # A full GPU (e.g. a LoRA training job) shouldn't stop the gallery scan
        return ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])


@dataclass
class Body:
    bbox: np.ndarray                      # x1, y1, x2, y2 (float, image pixels)
    score: float
    kpts: Optional[np.ndarray] = None     # (17, 2)
    kpt_scores: Optional[np.ndarray] = None  # (17,)


class PersonDetector:
    SIZE = 640

    def __init__(self, model_path: Path, providers=None):
        self.session = _session(model_path, providers or default_providers())
        self.input_name = self.session.get_inputs()[0].name

    def detect(self, img_bgr: np.ndarray, score_thr: float = 0.5, min_height: int = 48) -> np.ndarray:
        """(N, 5) array of x1, y1, x2, y2, score."""
        h, w = img_bgr.shape[:2]
        ratio = min(self.SIZE / h, self.SIZE / w)
        nh, nw = max(1, int(round(h * ratio))), max(1, int(round(w * ratio)))
        padded = np.full((self.SIZE, self.SIZE, 3), 114, dtype=np.uint8)
        padded[:nh, :nw] = cv2.resize(img_bgr, (nw, nh), interpolation=cv2.INTER_LINEAR)
        blob = padded.transpose(2, 0, 1)[None].astype(np.float32)
        dets, labels = self.session.run(None, {self.input_name: blob})
        dets, labels = dets[0], labels[0]
        keep = (labels == 0) & (dets[:, 4] >= score_thr)
        dets = dets[keep].copy()
        if not len(dets):
            return np.zeros((0, 5), dtype=np.float32)
        dets[:, :4] /= ratio
        dets[:, [0, 2]] = dets[:, [0, 2]].clip(0, w)
        dets[:, [1, 3]] = dets[:, [1, 3]].clip(0, h)
        dets = dets[(dets[:, 3] - dets[:, 1]) >= min_height]
        return dets[np.argsort(-dets[:, 4])]


class PoseEstimator:
    W, H = 192, 256
    MEAN = np.array([123.675, 116.28, 103.53], dtype=np.float32)
    STD = np.array([58.395, 57.12, 57.375], dtype=np.float32)
    SIMCC_SPLIT = 2.0

    def __init__(self, model_path: Path, providers=None):
        self.session = _session(model_path, providers or default_providers())
        self.input_name = self.session.get_inputs()[0].name

    def _box_to_cs(self, box):
        x1, y1, x2, y2 = [float(v) for v in box[:4]]
        cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
        bw, bh = max(x2 - x1, 1.0) * 1.25, max(y2 - y1, 1.0) * 1.25
        aspect = self.W / self.H
        if bw > bh * aspect:
            bh = bw / aspect
        else:
            bw = bh * aspect
        return cx, cy, bw, bh

    def estimate(self, img_bgr: np.ndarray, boxes: np.ndarray, batch: int = 16):
        """Keypoints (N, 17, 2) in image pixels and their scores (N, 17)."""
        if not len(boxes):
            return np.zeros((0, 17, 2), np.float32), np.zeros((0, 17), np.float32)
        rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
        all_k, all_s = [], []
        for start in range(0, len(boxes), batch):
            metas, inputs = [], []
            for box in boxes[start:start + batch]:
                cx, cy, bw, bh = self._box_to_cs(box)
                s = self.W / bw
                m = np.array([[s, 0, -(cx - bw / 2) * s], [0, s, -(cy - bh / 2) * s]], dtype=np.float32)
                crop = cv2.warpAffine(rgb, m, (self.W, self.H), flags=cv2.INTER_LINEAR)
                inputs.append(((crop.astype(np.float32) - self.MEAN) / self.STD).transpose(2, 0, 1))
                metas.append((cx, cy, bw, bh))
            simcc_x, simcc_y = self.session.run(None, {self.input_name: np.stack(inputs)})
            xs = simcc_x.argmax(-1) / self.SIMCC_SPLIT
            ys = simcc_y.argmax(-1) / self.SIMCC_SPLIT
            scores = np.minimum(simcc_x.max(-1), simcc_y.max(-1))
            for i, (cx, cy, bw, bh) in enumerate(metas):
                k = np.stack([xs[i] / self.W * bw + cx - bw / 2,
                              ys[i] / self.H * bh + cy - bh / 2], axis=-1)
                all_k.append(k.astype(np.float32))
                all_s.append(scores[i].astype(np.float32))
        return np.stack(all_k), np.stack(all_s)


class BodyAnalyzer:
    """Lazy wrapper: models load (and download) on first analyze(). If anything
    fails, `available` turns False and `error` says why - callers keep scanning
    faces without bodies."""

    def __init__(self, use_pose: bool = True, providers=None, log: Callable[[str], None] = print,
                 models_dir: Path = None, allow_downloads: bool = True):
        self.use_pose = use_pose
        self.providers = providers
        self.log = log
        self.models_dir = models_dir
        self.allow_downloads = allow_downloads
        self.detector: Optional[PersonDetector] = None
        self.pose: Optional[PoseEstimator] = None
        self.error: Optional[str] = None
        self._loaded = False

    def load(self) -> bool:
        if self._loaded:
            return self.detector is not None
        self._loaded = True
        try:
            providers = self.providers or default_providers()
            def model(key):
                if self.allow_downloads: return ensure_model(key, self.log, self.models_dir)
                spec = MODEL_SPECS[key]
                path = Path(self.models_dir or MODELS_DIR)/spec['file']
                if not path.is_file() or path.stat().st_size != spec['onnx_size']:
                    raise FileNotFoundError('Local body model is missing or incomplete: '+spec['file'])
                return path
            self.detector = PersonDetector(model("person"), providers)
            if self.use_pose:
                self.pose = PoseEstimator(model("pose"), providers)
        except Exception as e:
            self.error = str(e)
            self.detector = None
            self.log(f"[body models] body detection disabled: {e}")
        return self.detector is not None

    @property
    def available(self) -> bool:
        return self.load()

    def analyze(self, img_bgr: np.ndarray, score_thr: float = 0.5) -> List[Body]:
        if not self.load():
            return []
        dets = self.detector.detect(img_bgr, score_thr=score_thr)
        bodies = [Body(bbox=d[:4].astype(np.float32), score=float(d[4])) for d in dets]
        if self.pose is not None and bodies:
            kpts, kscores = self.pose.estimate(img_bgr, dets[:, :4])
            for b, k, s in zip(bodies, kpts, kscores):
                b.kpts, b.kpt_scores = k, s
        return bodies
