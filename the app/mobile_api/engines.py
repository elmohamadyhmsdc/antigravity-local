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


class InsightEngines:
    model_id = EMBEDDING_MODEL_ID

    def __init__(self, log: Callable[[str], None] = print, *, isolate_scans=True):
        self._log = log
        self._lock = threading.Lock()
        self._face_app = None
        self._body = None
        from .scan_worker import ScanWorker
        self._scan_worker = ScanWorker(log) if isolate_scans else None

    @property
    def loaded(self) -> bool:
        return self._face_app is not None or (self._scan_worker is not None and self._scan_worker.loaded)

    def load(self) -> None:
        """Idempotent; called under the lock by analyze() or eagerly by `--preload`."""
        if self._face_app is not None:
            return
        from cuda_dll_dirs import add_nvidia_dll_dirs
        add_nvidia_dll_dirs()
        from insightface.app import FaceAnalysis
        from body_detector import BodyAnalyzer
        face_dir = Path.home()/'.insightface/models/buffalo_l'
        if not all((face_dir/name).is_file() for name in ('det_10g.onnx', 'w600k_r50.onnx', '1k3d68.onnx')):
            raise FileNotFoundError('Local buffalo_l face models are incomplete. Downloads are disabled.')
        started = time.time()
        app = FaceAnalysis(name="buffalo_l", allowed_modules=["detection", "recognition", "landmark_3d_68"],
                           providers=["CUDAExecutionProvider", "CPUExecutionProvider"])
        app.prepare(ctx_id=0, det_size=[(128, 128), (640, 640)])
        self._face_app = app
        self._body = BodyAnalyzer(log=self._log, allow_downloads=False)
        self._log(f"[engines] face models ready in {time.time() - started:.1f}s")

    def analyze(self, img, options) -> analysis.FrameAnalysis:
        with self._lock:
            if self._scan_worker is not None:
                return self._scan_worker.analyze(img, options)
            self.load()
            return analysis.analyze_frame(self._face_app, self._body, img, options)

    def unload(self):
        import gc
        with self._lock:
            if self._scan_worker is not None:
                self._scan_worker.close()
            self._face_app = None
            self._body = None
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

    def __init__(self, app_dir: Path = APP_DIR, gpu_ttl: float = 3.0):
        self.app_dir = Path(app_dir)
        self._gpu_ttl = gpu_ttl
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
        from .model_readiness import restyle_missing_models
        has_swapper = self._has("models", "inswapper_128.onnx")
        venv_ai = self._has("venv_ai", "Scripts", "python.exe")
        return {
            "reface_v3": has_swapper and bool(self.restorers()),
            "reface_v2": has_swapper,
            "dfm_models": self.dfm_models(),
            "undress": venv_ai and not restyle_missing_models(self.app_dir),
            "lora_train": self._has("venv_lora", "Scripts", "python.exe") and self._has("sd-scripts"),
            "lora_generate": venv_ai and bool(self.lora_base_checkpoints()),
            "body_detection": self._has("models", "body", "yolox_m_humanart.onnx")
                              and self._has("models", "body", "rtmpose_m_body7.onnx"),
        }

    def snapshot(self) -> Dict:
        return {"gpu": self.gpu(), "engines": self.engines(), "restorers": self.restorers(),
                "lora_base_checkpoints": self.lora_base_checkpoints()}
