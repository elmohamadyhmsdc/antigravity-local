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
        from .scan_worker import ScanWorker
        self._scan_worker = ScanWorker(log) if isolate_scans else None

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
        from insightface.app import FaceAnalysis
        face_dir = Path.home()/'.insightface/models/buffalo_l'
        if not all((face_dir/name).is_file() for name in ('det_10g.onnx', 'w600k_r50.onnx', '1k3d68.onnx')):
            raise FileNotFoundError('Local buffalo_l face models are incomplete. Downloads are disabled.')
        started = time.time()
        app = FaceAnalysis(name="buffalo_l", allowed_modules=["detection", "recognition", "landmark_3d_68"],
                           providers=["CUDAExecutionProvider", "CPUExecutionProvider"])
        app.prepare(ctx_id=0, det_size=[(128, 128), (640, 640)])
        self._face_app = app
        self._log(f"[engines] face models ready in {time.time() - started:.1f}s")

    def analyze(self, img, options) -> analysis.FrameAnalysis:
        with self._lock:
            if self._scan_worker is not None:
                return self._scan_worker.analyze(img, options)
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
                res.sensitive = self._detect_sensitive(img, _bodies_as_dicts(res.bodies))
            if wants_embeddings:
                res.body_embeddings = self._embed_bodies(img, res)
            return res

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
            if self._scan_worker is not None:
                return self._scan_worker.sensitive(img, bodies, embeddings)
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
            if self._scan_worker is not None:
                return self._scan_worker.outlines(img, targets)
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

    def unload(self):
        import gc
        with self._lock:
            if self._scan_worker is not None:
                self._scan_worker.close()
            self._face_app = None
            self._body = None
            self._outline_engine = None
            self._sensitive_detector = None
            self._embedder = None
        gc.collect()


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
