"""
Antigravity Local - DeepFaceLab bridge: a trained video model per person

One-shot swappers (inswapper, HyperSwap) only see a 512-number identity
vector. A DeepFaceLab model is trained on thousands of frames of the person,
so it learns their actual face - skin, teeth, expressions - and is the best
quality available for video. It costs days of GPU time, so it runs as a
resumable background job (job type "train_dfl").

Pipeline for one identity (built with identity_builder.py):

    1. frames   the person's videos -> dfl_work/<slug>/data_src/*.jpg (ffmpeg), photos copied
    2. extract  DeepFaceLab S3FD, whole face, 512 px -> data_src/aligned
    3. clean    aligned faces that are not the person (our identity vector) or are blurry
                move to data_src/aligned_rejected - DeepFaceLab keeps every face it finds
    4. masks    DeepFaceLab's generic whole-face XSeg applied to data_src/aligned
    5. train    SAEHD against the RTM WF faceset ("ready to merge": works on any target),
                headless via dfl_runner.py, stop file = save and exit, resumes where it left
    6. export   .dfm -> models/dfm/<slug>.dfm; Reface V3 uses it for that identity

Everything DeepFaceLab runs inside its own bundled Python 3.6 / TensorFlow 2.6
(the RTX 3000 build). On a 40-series card its CUDA kernels are JIT-compiled the
first time (~1 minute); CUDA_CACHE_MAXSIZE is raised so that happens once.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable, Dict, List, Optional

APP = Path(__file__).parent
DFL_DIST = APP.parent / "DeepFaceLab_NVIDIA_RTX3000_series"
DFL_INTERNAL = DFL_DIST / "_internal"
DFL_ROOT = DFL_INTERNAL / "DeepFaceLab"
DFL_PYTHON = DFL_INTERNAL / "python-3.6.8" / "python.exe"
RTM_DST = APP.parent / "RTM WF faceset" / "aligned"      # generic dst faceset (faceset.pak)
GENERIC_XSEG = DFL_INTERNAL / "model_generic_xseg"
WORK_ROOT = APP / "dfl_work"
DFM_DIR = APP / "models" / "dfm"
RUNNER = APP / "dfl_runner.py"

VIDEO_EXTS = {".mp4", ".mov", ".mkv", ".avi", ".webm", ".wmv", ".m4v"}
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}

FRAMES_PER_SECOND = 6          # enough variety without thousands of near-identical frames
MIN_ALIGNED_SIMILARITY = 0.40  # identity match for an extracted face to stay in the training set
BLUR_KEEP_RATIO = 0.35         # drop faces with Laplacian variance below this fraction of the median

# SAEHD settings sized for a 6 GB laptop GPU. Prompts are matched by their
# opening words (dfl_runner.patch_questions); anything absent keeps
# DeepFaceLab's default.
BASE_OPTIONS = {
    "Autobackup every N hour": 2,
    "Write preview history": False,
    "Target iteration": 0,
    "Flip SRC faces randomly": False,      # faces aren't symmetric; flipping blurs moles and partings
    "Flip DST faces randomly": True,
    "Batch_size": 4,
    "Resolution": 224,
    "Face type": "wf",
    "AE architecture": "liae-udt",
    "AutoEncoder dimensions": 256,
    "Encoder dimensions": 64,
    "Decoder dimensions": 64,
    "Decoder mask dimensions": 22,
    "Masked training": True,
    "Eyes and mouth priority": True,
    "Uniform yaw distribution of samples": True,
    "Blur out mask": False,
    "Place models and optimizer on GPU": True,
    "Use AdaBelief optimizer?": True,
    "Use learning rate dropout": "n",
    "Enable random warp of samples": True,
    "Random hue/saturation/light intensity": 0.05,
    "GAN power": 0.0,
    "'True face' power.": 0.0,
    "Face style power": 0.0,
    "Background style power": 0.0,
    "Color transfer for src faceset": "rct",
    "Enable gradient clipping": True,
    "Enable pretraining mode": False,
}
# Training phases (the usual SAEHD recipe): generalise with random warp, then
# sharpen with it off and learning-rate dropout on, then a light GAN for pores.
PHASES = {
    "base": {},
    "sharpen": {"Enable random warp of samples": False, "Use learning rate dropout": "y"},
    "detail": {"Enable random warp of samples": False, "Use learning rate dropout": "y",
               "GAN power": 0.1, "GAN patch size": 28, "GAN dimensions": 16},
}
# Batch / placement fallbacks tried in order when the GPU runs out of memory.
OOM_FALLBACKS = [{}, {"Batch_size": 3}, {"Batch_size": 3, "Place models and optimizer on GPU": False},
                 {"Batch_size": 2, "Place models and optimizer on GPU": False}]

_ITER_RE = re.compile(r"\[#(\d+)\]\[(\d+)ms\]((?:\[[\d.]+\])+)")


# --- environment -----------------------------------------------------------------

def available() -> Optional[str]:
    """None when DeepFaceLab can run here, else the reason it can't."""
    for p, what in ((DFL_PYTHON, "DeepFaceLab's Python"), (DFL_ROOT / "main.py", "DeepFaceLab"),
                    (RTM_DST, "the RTM WF faceset")):
        if not p.exists():
            return f"{what} not found at {p}"
    return None


def dfl_env() -> Dict[str, str]:
    """What _internal/setenv.bat sets up, minus the console bits."""
    env = dict(os.environ)
    local = DFL_INTERNAL / "_e"
    py = DFL_INTERNAL / "python-3.6.8"
    for k, v in {"TMP": local / "t", "TEMP": local / "t", "HOME": local / "u", "HOMEPATH": local / "u",
                 "USERPROFILE": local / "u"}.items():
        env[k] = str(v)
    env["LOCALAPPDATA"] = str(local / "u" / "AppData" / "Local")
    env["APPDATA"] = str(local / "u" / "AppData" / "Roaming")
    env.pop("PYTHONHOME", None)
    env.pop("PYTHONPATH", None)
    path = [str(py), str(py / "Scripts"), str(DFL_INTERNAL / "CUDA"), str(DFL_INTERNAL / "CUDNN")]
    if (DFL_INTERNAL / "CUDNN" / "Win10.0").exists():
        path.insert(0, str(DFL_INTERNAL / "CUDNN" / "Win10.0"))
    path += [str(DFL_INTERNAL / "ffmpeg"), env.get("PATH", "")]
    env["PATH"] = os.pathsep.join(path)
    env["PYTHONUNBUFFERED"] = "1"
    env["TF_CPP_MIN_LOG_LEVEL"] = "2"
    # Keep the JIT-compiled kernels for this GPU instead of rebuilding them each start.
    env["CUDA_CACHE_MAXSIZE"] = str(4 * 1024 ** 3)
    for d in (local / "t", local / "u"):
        d.mkdir(parents=True, exist_ok=True)
    return env


def run(args: List[str], log_path: Path, on_line: Optional[Callable[[str], None]] = None) -> int:
    """Run a DeepFaceLab-python command, teeing its output to log_path."""
    log_path.parent.mkdir(parents=True, exist_ok=True)
    creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    with open(log_path, "a", encoding="utf-8", errors="replace") as log:
        log.write(f"\n$ {' '.join(map(str, args))}\n")
        proc = subprocess.Popen([str(a) for a in args], cwd=str(DFL_ROOT), env=dfl_env(),
                                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                creationflags=creationflags)
        buf = b""
        while True:
            chunk = proc.stdout.read1(4096) if hasattr(proc.stdout, "read1") else proc.stdout.read(4096)
            if not chunk:
                break
            buf += chunk
            # DeepFaceLab rewrites its progress line with '\r'; treat it as a line end.
            parts = re.split(rb"[\r\n]", buf)
            buf = parts.pop()
            for raw in parts:
                line = raw.decode("utf-8", errors="replace").strip()
                if not line:
                    continue
                log.write(line + "\n")
                if on_line:
                    on_line(line)
            log.flush()
        return proc.wait()


# --- workspace -------------------------------------------------------------------

class Workspace:
    def __init__(self, slug: str, root: Path = WORK_ROOT):
        self.slug = slug
        self.dir = Path(root) / slug
        self.src = self.dir / "data_src"
        self.aligned = self.src / "aligned"
        self.rejected = self.src / "aligned_rejected"
        self.model = self.dir / "model"
        self.log = self.dir / "dfl.log"
        self.state_file = self.dir / "state.json"
        self.stop_file = self.dir / "STOP"

    def state(self) -> Dict:
        if self.state_file.exists():
            try:
                return json.loads(self.state_file.read_text(encoding="utf-8"))
            except Exception:
                pass
        return {"slug": self.slug, "stages_done": [], "iter": 0, "phase": "base"}

    def save_state(self, state: Dict):
        self.dir.mkdir(parents=True, exist_ok=True)
        tmp = self.state_file.with_suffix(".tmp")
        tmp.write_text(json.dumps(state, indent=2), encoding="utf-8")
        os.replace(tmp, self.state_file)

    def aligned_count(self) -> int:
        return len(list(self.aligned.glob("*.jpg"))) if self.aligned.exists() else 0


# --- stages ------------------------------------------------------------------------

def stage_frames(ws: Workspace, media: List[str], fps: float = FRAMES_PER_SECOND) -> int:
    """Videos -> jpg frames, photos copied. Returns the number of images in data_src."""
    from ffmpeg_utils import _ffmpeg_exe
    ws.src.mkdir(parents=True, exist_ok=True)
    for i, m in enumerate(media):
        p = Path(m)
        if p.suffix.lower() in VIDEO_EXTS:
            out = ws.src / f"v{i:02d}_%06d.jpg"
            subprocess.run([_ffmpeg_exe(), "-y", "-loglevel", "error", "-i", str(p), "-vf", f"fps={fps}",
                            "-q:v", "2", str(out)], check=False)
        elif p.suffix.lower() in IMAGE_EXTS and p.exists():
            shutil.copy2(p, ws.src / f"p{i:04d}{p.suffix.lower()}")
    return len([f for f in ws.src.iterdir() if f.suffix.lower() in IMAGE_EXTS])


def stage_extract(ws: Workspace, on_line=None) -> int:
    # S3FD, whole face, 512 px, every face in the frame (cleaned up afterwards).
    rc = run([DFL_PYTHON, RUNNER, "extract", "--dfl-root", DFL_ROOT, "--src", ws.src, "--dst", ws.aligned],
             ws.log, on_line)
    if rc != 0:
        raise RuntimeError(f"DeepFaceLab extract failed (exit {rc}); see {ws.log}")
    return ws.aligned_count()


def stage_clean(ws: Workspace, identity_vector, face_app,
                min_similarity: float = MIN_ALIGNED_SIMILARITY) -> Dict[str, int]:
    """Move extracted faces that aren't the person, or are blurry, out of the training set."""
    import cv2
    import numpy as np

    ws.rejected.mkdir(parents=True, exist_ok=True)
    ident = np.asarray(identity_vector, np.float32)
    ident = ident / max(float(np.linalg.norm(ident)), 1e-8)
    sharp = {}
    counts = {"kept": 0, "not the person": 0, "no face found": 0, "blurry": 0}
    for f in sorted(ws.aligned.glob("*.jpg")):
        img = cv2.imread(str(f))
        faces = face_app.get(img) if img is not None else []
        if not faces:
            shutil.move(str(f), ws.rejected / f.name)
            counts["no face found"] += 1
            continue
        face = max(faces, key=lambda x: (x.bbox[2] - x.bbox[0]) * (x.bbox[3] - x.bbox[1]))
        if float(face.normed_embedding @ ident) < min_similarity:
            shutil.move(str(f), ws.rejected / f.name)
            counts["not the person"] += 1
            continue
        h, w = img.shape[:2]
        centre = cv2.cvtColor(img[h // 4:3 * h // 4, w // 4:3 * w // 4], cv2.COLOR_BGR2GRAY)
        sharp[f] = float(cv2.Laplacian(centre, cv2.CV_64F).var())
    if sharp:
        floor = float(np.median(list(sharp.values()))) * BLUR_KEEP_RATIO
        for f, v in sharp.items():
            if v < floor:
                shutil.move(str(f), ws.rejected / f.name)
                counts["blurry"] += 1
            else:
                counts["kept"] += 1
    return counts


def stage_masks(ws: Workspace, on_line=None):
    rc = run([DFL_PYTHON, RUNNER, "xseg", "--dfl-root", DFL_ROOT, "--src", ws.aligned, "--xseg-model", GENERIC_XSEG],
             ws.log, on_line)
    if rc != 0:
        raise RuntimeError(f"XSeg apply failed (exit {rc}); see {ws.log}")


def parse_progress(line: str) -> Optional[Dict]:
    m = _ITER_RE.search(line)
    if not m:
        return None
    losses = [float(x) for x in re.findall(r"\[([\d.]+)\]", m.group(3))]
    return {"iter": int(m.group(1)), "ms_per_iter": int(m.group(2)), "loss": losses}


def stage_train(ws: Workspace, phase: str = "base", overrides: Optional[Dict] = None,
                on_progress: Optional[Callable[[Dict], None]] = None) -> Dict:
    """Train until the stop file appears (or the process dies). Resumes a saved model.

    Tries smaller batch / CPU optimizer placement when the GPU runs out of memory.
    Returns {"exit": code, "iter": last iteration, "oom": bool, "options": used}.
    """
    ws.model.mkdir(parents=True, exist_ok=True)
    state = ws.state()
    change_phase = state.get("phase") != phase
    last = {"iter": state.get("iter", 0)}
    tried = state.get("fallback", 0)

    for idx in range(tried, len(OOM_FALLBACKS)):
        answers = {**BASE_OPTIONS, **PHASES.get(phase, {}), **OOM_FALLBACKS[idx], **(overrides or {})}
        answers_path = ws.dir / "answers.json"
        answers_path.write_text(json.dumps(answers, indent=2), encoding="utf-8")
        oom = {"hit": False}

        def on_line(line):
            if "OOM" in line or "out of memory" in line.lower() or "ResourceExhausted" in line:
                oom["hit"] = True
            p = parse_progress(line)
            if p:
                last.update(p)
                if on_progress:
                    on_progress(dict(last, phase=phase))

        args = [DFL_PYTHON, RUNNER, "train", "--dfl-root", DFL_ROOT, "--src", ws.aligned, "--dst", RTM_DST,
                "--model-dir", ws.model, "--name", ws.slug, "--answers", answers_path,
                "--stop-file", ws.stop_file]
        # A saved model keeps its options unless we ask to override them: on a
        # phase change, or when retrying with smaller settings after running out of memory.
        if any(ws.model.glob("*_SAEHD_data.dat")) and (change_phase or idx != tried):
            args.append("--override")
        code = run(args, ws.log, on_line)
        state.update(iter=last.get("iter", 0), phase=phase, fallback=idx, options=answers)
        ws.save_state(state)
        if oom["hit"] and not ws.stop_file.exists() and idx + 1 < len(OOM_FALLBACKS):
            continue
        return {"exit": code, "iter": last.get("iter", 0), "oom": oom["hit"], "options": answers}
    return {"exit": 1, "iter": last.get("iter", 0), "oom": True, "options": {}}


def stage_export(ws: Workspace, quantized: bool = False) -> Path:
    before = {p: p.stat().st_mtime for p in ws.model.glob("*.dfm")}
    args = [DFL_PYTHON, RUNNER, "export", "--dfl-root", DFL_ROOT, "--model-dir", ws.model, "--name", ws.slug]
    if quantized:
        args.append("--quantized")
    if run(args, ws.log) != 0:
        raise RuntimeError(f"DFM export failed; see {ws.log}")
    dfms = sorted(ws.model.glob("*.dfm"), key=lambda p: p.stat().st_mtime, reverse=True)
    fresh = [p for p in dfms if before.get(p) != p.stat().st_mtime]
    if not fresh:
        raise RuntimeError("DeepFaceLab finished without writing a .dfm")
    DFM_DIR.mkdir(parents=True, exist_ok=True)
    dest = DFM_DIR / f"{ws.slug}.dfm"
    shutil.copy2(fresh[0], dest)
    return dest


def dfm_for(slug: str) -> Optional[Path]:
    """The exported video model for an identity, if one exists."""
    p = DFM_DIR / f"{slug}.dfm"
    return p if p.exists() else None


# --- background job ------------------------------------------------------------------

def run_dfl_job(job, manager) -> bool:
    """job_type "train_dfl". params: slug, media (paths), phase.

    Stages already done (state.json) are skipped, so Resume continues training.
    Stop (the job manager's stop request) saves the model, exports the .dfm and
    pauses the job.
    """
    import threading
    from datetime import datetime
    from job_manager import JobStatus

    params = job.params or {}
    slug = params["slug"]
    ws = Workspace(slug)
    state = ws.state()
    details = dict(job.details or {})

    def save(message=None, **kv):
        details.update(kv)
        job.details = details
        if message:
            job.message = message
        manager.save_job(job)

    reason = available()
    if reason:
        raise RuntimeError(reason)
    if ws.stop_file.exists():
        ws.stop_file.unlink()
    job.status = JobStatus.RUNNING
    job.started_at = job.started_at or datetime.now().isoformat()
    save("Preparing the training set...", stage="prepare")

    done = set(state.get("stages_done", []))

    def mark(stage):
        done.add(stage)
        state["stages_done"] = sorted(done)
        ws.save_state(state)

    if "frames" not in done:
        n = stage_frames(ws, params.get("media") or [])
        save(f"{n} images to extract faces from", stage="frames", images=n)
        mark("frames")
    if "extract" not in done:
        save("Extracting faces (DeepFaceLab S3FD)...", stage="extract")
        n = stage_extract(ws)
        save(f"{n} faces extracted", aligned=n)
        mark("extract")
    if "clean" not in done:
        import numpy as np
        from insightface.app import FaceAnalysis
        save("Keeping only the person's sharp faces...", stage="clean")
        vec = np.load(APP / "identities" / slug / "identity.npy")
        app = FaceAnalysis(name="buffalo_l", allowed_modules=["detection", "recognition"],
                           providers=["CUDAExecutionProvider", "CPUExecutionProvider"])
        app.prepare(ctx_id=0, det_size=(640, 640))
        counts = stage_clean(ws, vec, app)
        del app
        save(f"Training set: {counts['kept']} faces", clean=counts, aligned=ws.aligned_count())
        mark("clean")
    if ws.aligned_count() < 50:
        raise RuntimeError(f"Only {ws.aligned_count()} usable faces of the person - add more video "
                           "(a few minutes, turning the head, different expressions).")
    if "masks" not in done:
        save("Applying face masks (generic XSeg)...", stage="masks")
        stage_masks(ws)
        mark("masks")

    # Translate the job manager's stop request into the runner's stop file.
    stop_seen = {"v": False}

    def watch():
        while not stop_seen["v"]:
            if manager.is_stop_requested(job.id):
                stop_seen["v"] = True
                ws.stop_file.touch()
                return
            time.sleep(2.0)
    threading.Thread(target=watch, daemon=True).start()

    last_save = {"t": 0.0}

    def progress(p):
        if time.time() - last_save["t"] < 5:
            return
        last_save["t"] = time.time()
        loss = p.get("loss") or []
        save(f"Training ({p.get('phase')}): iteration {p['iter']:,}"
             + (f", loss {loss[0]:.4f}" if loss else ""),
             stage="train", iter=p["iter"], loss=loss, ms_per_iter=p.get("ms_per_iter"), phase=p.get("phase"))

    phase = params.get("phase", "base")
    save(f"Training ({phase})... the first start compiles GPU kernels (~1-2 min)", stage="train", phase=phase)
    result = stage_train(ws, phase=phase, on_progress=progress)
    stop_seen["v"] = True
    save(iter=result["iter"], options=result.get("options"))

    if result["iter"] > 0:
        save("Exporting the trained model (.dfm)...", stage="export")
        try:
            dfm = stage_export(ws)
            save(dfm=str(dfm), exported_iter=result["iter"])
        except Exception as e:
            save(export_error=str(e))

    if manager.is_stop_requested(job.id) or ws.stop_file.exists():
        manager.pause_job(job.id, 0)
        job = manager.load_job(job.id)
        job.message = f"⏸️ Paused at iteration {result['iter']:,} - model saved" + (
            " and exported" if details.get("dfm") else "")
        manager.save_job(job)
        if ws.stop_file.exists():
            ws.stop_file.unlink()
        return False
    if result.get("oom"):
        raise RuntimeError("The GPU ran out of memory even at the smallest batch size. Close other GPU apps and resume.")
    raise RuntimeError(f"DeepFaceLab stopped unexpectedly (exit {result['exit']}); see {ws.log}")
