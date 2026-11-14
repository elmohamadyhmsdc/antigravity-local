"""
The engines behind the API, and the probe that reports what this PC can do.

`Engines` is the seam the tests replace: the routes only call `engines.analyze(img, options)`.
The real implementation loads insightface (buffalo_l) and the ONNX body models on first use
(not at import/startup, so an idle server does not hold GPU memory) and serialises inference -
the models are not thread-safe and the card is shared.
"""

import shutil
import subprocess
import threading
import time
from pathlib import Path
from typing import Callable, Dict, List, Optional

import analysis

from . import APP_DIR, EMBEDDING_DIM, EMBEDDING_MODEL_ID


def _bodies_as_dicts(bodies) -> list:
    return [{"bbox": [float(v) for v in b.bbox[:4]], "kpts": b.kpts, "kpt_scores": b.kpt_scores} for b in bodies]


def _character_body_dicts(characters) -> tuple:
    """(body dicts, owner) for the characters that have a body; owner[i] = index in `characters`."""
    figures, owner = [], []
    for index, c in enumerate(characters):
        if getattr(c, "body_bbox", None) is not None:
            figures.append({"bbox": [float(v) for v in c.body_bbox[:4]], "kpts": c.body_kpts,
                            "kpt_scores": c.body_kpt_scores})
            owner.append(index)
    return figures, owner


def load_face_analyzer():
    """Load the same local detection, recognition, and pose models on desktop and mobile."""
    from cuda_dll_dirs import add_nvidia_dll_dirs

    add_nvidia_dll_dirs()
    from insightface.app import FaceAnalysis
    face_dir = Path.home()/'.insightface/models/buffalo_l'
    if not all((face_dir/name).is_file() for name in ('det_10g.onnx', 'w600k_r50.onnx', '1k3d68.onnx')):
        raise FileNotFoundError('Local buffalo_l face models are incomplete. Downloads are disabled.')
    app = FaceAnalysis(name="buffalo_l", allowed_modules=["detection", "recognition", "landmark_3d_68"],
                       providers=["CUDAExecutionProvider", "CPUExecutionProvider"])
    app.prepare(ctx_id=0, det_size=[(128, 128), (640, 640)])
    return app


class InsightEngines:
    model_id = EMBEDDING_MODEL_ID

    def __init__(self, log: Callable[[str], None] = print, *, isolate_scans=True):
        self._log = log
        self._lock = threading.Lock()
        self._face_app = None
        self._body = None
        self._outline_engine = None
        self._sensitive_detector = None
        self._embedder = None
        self._isolate_scans = bool(isolate_scans)
        from .scan_worker import ScanWorker
        self._scan_worker = ScanWorker(log) if isolate_scans else None

    def _get_scan_worker(self):
        if self._scan_worker is None and getattr(self, "_isolate_scans", False):
            from .scan_worker import ScanWorker
            self._scan_worker = ScanWorker(self._log)
        return self._scan_worker

    @property
    def loaded(self) -> bool:
        return (self._face_app is not None or getattr(self._body, "detector", None) is not None
                or (self._scan_worker is not None and self._scan_worker.loaded))

    def load(self, *, faces=True) -> None:
        """Idempotent; called under the lock by analyze() or eagerly by `--preload`."""
        from cuda_dll_dirs import add_nvidia_dll_dirs
        add_nvidia_dll_dirs()
        from body_detector import BodyAnalyzer
        if self._body is None:  # characters get keypoints like people
            self._body = BodyAnalyzer(log=self._log, allow_downloads=False)
        if not faces or self._face_app is not None:
            return
        started = time.time()
        self._face_app = load_face_analyzer()
        self._log(f"[engines] face models ready in {time.time() - started:.1f}s")

    def analyze(self, img, options) -> analysis.FrameAnalysis:
        with self._lock:
            worker = self._get_scan_worker()
            if worker is not None:
                return worker.analyze(img, options)
            self.load(faces=True)  # character mode also needs faces (real-face filter)
            res = analysis.analyze_frame(self._face_app, self._body, img, options)
            if getattr(options, "outlines", False):
                if self._outline_engine is None:
                    from outlines import OutlineEngine
                    self._outline_engine = OutlineEngine()
                f_out, b_out = self._outline_engine.compute(img, res)
                res.face_outlines = f_out
                res.body_outlines = b_out
            wants_embeddings = getattr(options, "body_embeddings", False)
            if getattr(options, "sensitive", False) or wants_embeddings:
                self._sensitive_for(img, res, wants_embeddings)
            return res

    def _sensitive_for(self, img, res, wants_embeddings: bool) -> None:
        """Regions (and, when asked, body vectors) for people AND drawn characters in one detector pass.
        People keep `body_index`; a region on a character's body gets `character_index` instead, and the
        character's vectors go to `res.character_body_embeddings` (aligned with `res.characters`)."""
        people = _bodies_as_dicts(res.bodies)
        figures, owner = _character_body_dicts(res.characters)
        regions = self._detect_sensitive(img, people + figures)
        n = len(people)
        person_regions, figure_regions, out = [], [], []
        for region in regions:
            i = region.get("body_index")
            if i is not None and i >= n:
                figure_regions.append(dict(region, body_index=i - n))
                out.append(dict(region, body_index=None, character_index=owner[i - n]))
            else:
                if i is not None:
                    person_regions.append(region)
                out.append(region)
        res.sensitive = out
        if wants_embeddings:
            res.body_embeddings = self._embed_dicts(img, people, person_regions)
            if figures:
                vectors = self._embed_dicts(img, figures, figure_regions)
                aligned = [None] * len(res.characters)
                for position, character_index in enumerate(owner):
                    aligned[character_index] = vectors[position] if position < len(vectors) else None
                res.character_body_embeddings = aligned

    def _embed_bodies(self, img, res) -> list:
        """Roadmap 7.5: chest / lower-body DINOv2 embeddings and morphology for the bodies with exposed regions."""
        return self._embed_dicts(img, _bodies_as_dicts(res.bodies), res.sensitive or [])

    def _embed_dicts(self, img, bodies: list, regions: list) -> list:
        if self._embedder is None:
            from body_embeddings import DinoEmbedder
            self._embedder = DinoEmbedder()
        from body_embeddings import analyse_bodies
        return analyse_bodies(img, bodies, regions, self._embedder)

    def _detect_sensitive(self, img, bodies: list) -> list:
        """Roadmap section 8: regions with `body_index`. Loaded on first use only."""
        if self._sensitive_detector is None:
            from sensitive_detection import SensitiveDetector, env_model_path
            self._sensitive_detector = SensitiveDetector(env_model_path())
        from sensitive_detection import detect_for_bodies
        return detect_for_bodies(self._sensitive_detector, img, bodies)

    def compute_sensitive(self, img, bodies: list, embeddings: bool = False):
        """Backfill for photos scanned before the feature (`bodies`: dicts with bbox xyxy px, kpts, kpt_scores).
        A list of regions; with `embeddings` a dict {regions, bodies} (roadmap 7.5 for photos scanned earlier)."""
        with self._lock:
            worker = self._get_scan_worker()
            if worker is not None:
                return worker.sensitive(img, bodies, embeddings)
            regions = self._detect_sensitive(img, bodies)
            if not embeddings:
                return regions
            return {"regions": regions, "bodies": self._embed_dicts(img, bodies, regions)}

    def compute_equipment(self, img, bodies: list) -> list:
        with self._lock:
            from equipment_detection import detect_equipment
            return detect_equipment(img, bodies)

    def compute_garments(self, img, bodies: list) -> list:
        """Roadmap Phase 7: WD14 garment scores per body (list of tag lists, in order). Raw evidence only."""
        with self._lock:
            if getattr(self, "_garment_tagger", None) is None:
                from garment_tags import GarmentTagger
                self._garment_tagger = GarmentTagger()
            return self._garment_tagger.tag_bodies(img, bodies)

    def compute_outlines(self, img, targets: list) -> list:
        with self._lock:
            worker = self._get_scan_worker()
            if worker is not None:
                return worker.outlines(img, targets)
            if self._outline_engine is None:
                from outlines import OutlineEngine
                self._outline_engine = OutlineEngine()

            from outlines import encode_outline
            import numpy as np
            from types import SimpleNamespace

            results = [None] * len(targets)
            body_indices = []
            body_objs = []

            for i, t in enumerate(targets):
                kind = t.get("kind")
                bbox = t.get("bbox", {})
                if isinstance(bbox, dict):
                    bx = float(bbox.get("x", 0))
                    by = float(bbox.get("y", 0))
                    bw = float(bbox.get("w", 0))
                    bh = float(bbox.get("h", 0))
                    b_arr = np.array([bx, by, bx + bw, by + bh], dtype=np.float32)
                else:
                    b_arr = np.array(bbox, dtype=np.float32)

                if kind == "f":
                    kps = np.asarray(t["kps"], dtype=np.float32) if t.get("kps") is not None else None
                    face_obj = SimpleNamespace(bbox=b_arr, kps=kps)
                    poly = self._outline_engine.face_outline(img, face_obj)
                    results[i] = encode_outline(poly)
                elif kind == "b":
                    kpts_raw = t.get("kpts")
                    kpts = np.asarray(kpts_raw, dtype=np.float32) if kpts_raw is not None else None
                    kpt_scores = None
                    if kpts is not None and kpts.size > 0:
                        if kpts.shape[-1] >= 3:
                            kpt_scores = kpts[:, 2]
                            kpts = kpts[:, :2]
                        else:
                            kpt_scores = np.ones(len(kpts), dtype=np.float32)
                    body_obj = SimpleNamespace(bbox=b_arr, kpts=kpts, kpt_scores=kpt_scores)
                    body_indices.append(i)
                    body_objs.append(body_obj)

            if body_objs:
                b_polys = self._outline_engine.body_outlines(img, body_objs)
                for idx, poly in zip(body_indices, b_polys):
                    results[idx] = encode_outline(poly)

            return results

    def targeted_analyze(self, img, target_kind: str, roi=None, prompt: str = "", high_res: bool = True) -> list:
        with self._lock:
            h, w = img.shape[:2]
            if roi is not None:
                rx = max(0, int(roi['x'] * w))
                ry = max(0, int(roi['y'] * h))
                rw = max(1, int(roi['w'] * w))
                rh = max(1, int(roi['h'] * h))
                crop = img[ry:ry+rh, rx:rx+rw]
            else:
                rx, ry, rw, rh = 0, 0, w, h
                crop = img

            detections = []
            if target_kind == 'face':
                self.load(faces=True)
                if self._face_app is not None:
                    faces = self._face_app.get(crop)
                    for f in faces:
                        fx1, fy1, fx2, fy2 = f.bbox
                        abs_x = (rx + fx1) / w
                        abs_y = (ry + fy1) / h
                        abs_w = (fx2 - fx1) / w
                        abs_h = (fy2 - fy1) / h
                        detections.append({
                            "bbox": {"x": float(abs_x), "y": float(abs_y), "w": float(abs_w), "h": float(abs_h)},
                            "score": float(f.det_score),
                            "label": "face",
                            "outline": None,
                            "keypoints": None,
                        })
            elif target_kind == 'area':
                if self._sensitive_detector is None:
                    from sensitive_detection import SensitiveDetector, env_model_path
                    self._sensitive_detector = SensitiveDetector(env_model_path())
                raw_regions = self._sensitive_detector.detect(crop)
                for r in raw_regions:
                    bx1, by1, bx2, by2 = r['bbox']
                    abs_x = (rx + bx1) / w
                    abs_y = (ry + by1) / h
                    abs_w = (bx2 - bx1) / w
                    abs_h = (by2 - by1) / h
                    detections.append({
                        "bbox": {"x": float(abs_x), "y": float(abs_y), "w": float(abs_w), "h": float(abs_h)},
                        "score": float(r.get('score', 0.8)),
                        "label": r.get('label', 'exposed_area'),
                        "outline": None,
                        "keypoints": None,
                    })
            elif target_kind == 'body':
                if self._body is None:
                    from body_detector import BodyAnalyzer
                    self._body = BodyAnalyzer(log=self._log, allow_downloads=False)
                bodies = self._body.detect(crop)
                for b in bodies:
                    bx1, by1, bx2, by2 = b.bbox
                    abs_x = (rx + bx1) / w
                    abs_y = (ry + by1) / h
                    abs_w = (bx2 - bx1) / w
                    abs_h = (by2 - by1) / h
                    kpts = None
                    if getattr(b, 'kpts', None) is not None:
                        kpts = [[float((rx + kp[0]) / w), float((ry + kp[1]) / h), float(kp[2])] for kp in b.kpts]
                    detections.append({
                        "bbox": {"x": float(abs_x), "y": float(abs_y), "w": float(abs_w), "h": float(abs_h)},
                        "score": float(getattr(b, 'score', 0.85)),
                        "label": "person",
                        "outline": None,
                        "keypoints": kpts,
                    })
            elif target_kind == 'object':
                from equipment_detection import detect_equipment
                objs = detect_equipment(crop, [])
                for obj in objs:
                    bx = rx / w + obj['bbox']['x'] * (rw / w)
                    by = ry / h + obj['bbox']['y'] * (rh / h)
                    bw = obj['bbox']['w'] * (rw / w)
                    bh = obj['bbox']['h'] * (rh / h)
                    detections.append({
                        "bbox": {"x": float(bx), "y": float(by), "w": float(bw), "h": float(bh)},
                        "score": 0.9,
                        "label": obj.get('label', 'object'),
                        "outline": None,
                        "keypoints": None,
                    })
            return detections

    def unload(self):
        import gc
        with self._lock:
            if self._scan_worker is not None:
                self._scan_worker.close()
                self._scan_worker = None
            self._face_app = None
            self._body = None
            self._outline_engine = None
            self._sensitive_detector = None
            self._embedder = None
        gc.collect()
        try:
            import torch
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
                torch.cuda.ipc_collect()
        except Exception:
            pass


# --- capabilities --------------------------------------------------------------------


def available_dfm_models():
    from dfm_engine import DFMEngine
    # The desktop discovery also finds unrelated ONNX files containing "model"
    # (for example WD14). Only expose exports or explicit DFM model locations.
    return [model for model in DFMEngine.list_available_models()
            if Path(model.path).suffix.lower() == '.dfm'
            or 'dfm' in Path(model.path).stem.lower()
            or any(part.lower() in ('dfm','dfm_models','dfl_models','workspace') for part in Path(model.path).parts[:-1])
            or model.model_type != 'Unknown']

def _nvidia_smi() -> Optional[str]:
    return shutil.which("nvidia-smi") or (r"C:\Windows\System32\nvidia-smi.exe"
                                          if Path(r"C:\Windows\System32\nvidia-smi.exe").exists() else None)


class CapabilityProbe:
    """Reads the file system (models/, venvs, DeepFaceLab workspace) and nvidia-smi. Cheap, cached briefly."""

    def __init__(self, app_dir: Path = APP_DIR, gpu_ttl: float = 10.0, snapshot_ttl: float = 10.0):
        self.app_dir = Path(app_dir)
        self._gpu_ttl = gpu_ttl
        self._gpu_cache = (0.0, None)
        self._snapshot_ttl = snapshot_ttl
        self._snapshot_cache = None
        self._snapshot_stamp = 0.0

    def invalidate(self) -> None:
        """Clear cached snapshots, e.g. after model downloads."""
        self._snapshot_cache = None
        self._snapshot_stamp = 0.0
        self._gpu_cache = (0.0, None)

    def _has(self, *rel: str) -> bool:
        return (self.app_dir.joinpath(*rel)).exists()

    def gpu(self) -> Optional[Dict]:
        stamp, cached = self._gpu_cache
        if time.time() - stamp < self._gpu_ttl:
            return cached
        info = None
        exe = _nvidia_smi()
        if exe:
            try:
                out = subprocess.run([exe, "--query-gpu=name,memory.total,memory.free", "--format=csv,noheader,nounits"],
                                     capture_output=True, text=True, timeout=4).stdout.strip().splitlines()
                if out:
                    name, total, free = [p.strip() for p in out[0].split(",")]
                    info = {"name": name, "vram_total_mb": int(float(total)), "vram_free_mb": int(float(free))}
            except (OSError, ValueError, subprocess.SubprocessError):
                info = None
        self._gpu_cache = (time.time(), info)
        return info

    def restorers(self) -> List[str]:
        files = {"codeformer": "codeformer.onnx", "gfpgan_1.4": "gfpgan_1.4.onnx", "gpen_bfr_512": "gpen_bfr_512.onnx"}
        try:  # same table the engines use, when importable
            from face_restore import RESTORER_FILES
            files = dict(RESTORER_FILES)
        except Exception:  # noqa: BLE001 - onnxruntime missing etc.: fall back to the table above
            pass
        return [name for name, f in files.items() if self._has("models", f)]

    def dfm_models(self) -> List[str]:
        try:
            return [m.name for m in available_dfm_models()]
        except Exception:  # noqa: BLE001
            return []

    def lora_base_checkpoints(self) -> List[str]:
        return [p.stem for p in sorted((self.app_dir / "models").glob("sd15*.safetensors"))]

    def engines(self) -> Dict:
        from equipment_detection import model_available as equipment_available
        from photo_edit import ready as photo_edit_ready
        from .model_readiness import restyle_missing_models
        from .reference_reface import reference_reface_ready
        from pathlib import Path as _Path
        face_ready = all((_Path.home() / '.insightface' / 'models' / 'buffalo_l' / name).is_file()
                         for name in ('det_10g.onnx', 'w600k_r50.onnx'))
        character_ready = all(self._has('models', name) for name in ('anime_face_detect.onnx', 'ccip_character.onnx'))
        has_swapper = self._has("models", "inswapper_128.onnx")
        venv_ai = self._has("venv_ai", "Scripts", "python.exe")
        return {
            "face_detection": face_ready,
            "identity_bundle": face_ready,
            "reface_geometry": face_ready,
            "character_identity": character_ready and self._has('models', 'body', 'yolox_m_humanart.onnx'),
            "dataset_person": face_ready and self._has('models', 'wd14_tagger_model.onnx') and self._has('models', 'gpen_bfr_512.onnx'),
            "dataset_character": character_ready and self._has('models', 'body', 'yolox_m_humanart.onnx') and self._has('models', 'wd14_tagger_model.onnx'),
            "reface_reference": reference_reface_ready(self.app_dir),
            "reface": has_swapper,
            "reface_v3": has_swapper and bool(self.restorers()),
            "reface_v2": has_swapper,
            "dfm_models": self.dfm_models(),
            "undress": venv_ai and not restyle_missing_models(self.app_dir, refine=False),
            "restyle_refine": venv_ai and not restyle_missing_models(self.app_dir, refine=True),
            "lora_train": self._has("venv_lora", "Scripts", "python.exe") and self._has("sd-scripts"),
            "lora_generate": venv_ai and bool(self.lora_base_checkpoints()),
            "body_detection": self._has("models", "body", "yolox_m_humanart.onnx")
                              and self._has("models", "body", "rtmpose_m_body7.onnx"),
            "character_detection": self._has("models", "body", "yolox_m_humanart.onnx"),
            "sensitive_detection": self._has("models", "sensitive", "640m.onnx"),
            "body_embeddings": self._has("models", "sensitive", "640m.onnx")
                               and self._has("models", "reid", "dinov2_vits14.onnx"),
            "equipment": equipment_available(),
            "photo_edit": photo_edit_ready(self.app_dir),
            "garment_tags": self._has("models", "wd14_tagger_model.onnx") and self._has("models", "wd14_tagger_tags.csv"),
        }

    def snapshot(self) -> Dict:
        now = time.time()
        if self._snapshot_cache is not None and now - self._snapshot_stamp < self._snapshot_ttl:
            cached = dict(self._snapshot_cache)
            cached["gpu"] = self.gpu()
            return cached
        from reface_config import profile_catalog
        restorers = self.restorers()
        result = {"gpu": self.gpu(), "engines": self.engines(), "restorers": restorers,
                  "reface_profiles": profile_catalog(restorers),
                  "lora_base_checkpoints": self.lora_base_checkpoints()}
        self._snapshot_cache = result
        self._snapshot_stamp = now
        return result
