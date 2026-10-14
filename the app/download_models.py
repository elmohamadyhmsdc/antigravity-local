"""
Antigravity Local - Reface model downloader

Fetches the ONNX models used by the HD reface pipeline (reface_engine_v3.py)
into the local ``models/`` folder. All models run on onnxruntime-gpu, so no
torch/basicsr/facexlib is required.

Sources are the public facefusion-assets GitHub releases (stable, direct URLs).

Usage (from "the app/"):
    venv\\Scripts\\python.exe download_models.py            # essential set
    venv\\Scripts\\python.exe download_models.py --extras    # + alt restorers
    venv\\Scripts\\python.exe download_models.py --lora      # + Character LoRA pipeline models
    venv\\Scripts\\python.exe download_models.py --all        # everything
    venv\\Scripts\\python.exe download_models.py codeformer   # just one
"""

import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

MODELS_DIR = Path(__file__).parent / "models"

# name -> (url, approx_size_kb, extension). Size is used to detect partial/corrupt files.
_BASE = "https://github.com/facefusion/facefusion-assets/releases/download"
MODELS = {
    # Face restoration (pick one as default; codeformer preserves identity best)
    "codeformer":        (f"{_BASE}/models-3.0.0/codeformer.onnx",        368116, ".onnx"),
    "gfpgan_1.4":        (f"{_BASE}/models-3.0.0/gfpgan_1.4.onnx",         332323, ".onnx"),
    "gpen_bfr_512":      (f"{_BASE}/models-3.0.0/gpen_bfr_512.onnx",       277676, ".onnx"),
    "gpen_bfr_1024":     (f"{_BASE}/models-3.0.0/gpen_bfr_1024.onnx",      278519, ".onnx"),
    "restoreformer_plus_plus": (f"{_BASE}/models-3.0.0/restoreformer_plus_plus.onnx", 287367, ".onnx"),
    # Face swappers at 256 px (FaceFusion HyperSwap; non-commercial). inswapper_128
    # is placed by hand (insightface licence) and stays the fallback.
    "hyperswap_1b_256":  (f"{_BASE}/models-3.3.0/hyperswap_1b_256.onnx",  393304, ".onnx"),
    "hyperswap_1c_256":  (f"{_BASE}/models-3.3.0/hyperswap_1c_256.onnx",  393304, ".onnx"),
    # Masking
    "bisenet_resnet_34": (f"{_BASE}/models-3.0.0/bisenet_resnet_34.onnx",   91438, ".onnx"),  # face parser
    "xseg_1":            (f"{_BASE}/models-3.1.0/xseg_1.onnx",              68676, ".onnx"),  # face occluder
    "xseg_2":            (f"{_BASE}/models-3.1.0/xseg_2.onnx",              68676, ".onnx"),  # second occluder, combined with xseg_1
    # Character LoRA pipeline: person segmentation for body crops (lora_dataset.py / mask_utils.py)
    "selfie_segmenter":  ("https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/latest/selfie_segmenter.tflite", 250, ".tflite"),
    # Character LoRA pipeline: auto-captioning (lora_dataset.py)
    "wd14_tagger_model": ("https://huggingface.co/SmilingWolf/wd-v1-4-moat-tagger-v2/resolve/main/model.onnx", 375000, ".onnx"),
    "wd14_tagger_tags":  ("https://huggingface.co/SmilingWolf/wd-v1-4-moat-tagger-v2/resolve/main/selected_tags.csv", 300, ".csv"),
    # Character LoRA pipeline: base checkpoint for training + generation (lora_trainer.py / lora_generate.py)
    "sd15_realistic_base": ("https://huggingface.co/SG161222/Realistic_Vision_V6.0_B1_noVAE/resolve/main/Realistic_Vision_V6.0_NV_B1.safetensors", 4164608, ".safetensors"),
}

# Sets
# The V3 defaults (eval_reface.py, 2026-10-14): HyperSwap 1b + GPEN 512, plus the
# fallbacks the engine drops back to (inswapper is placed by hand, CodeFormer).
ESSENTIAL = ["hyperswap_1b_256", "gpen_bfr_512", "codeformer", "bisenet_resnet_34", "xseg_1"]
EXTRAS = ["gfpgan_1.4", "gpen_bfr_1024", "restoreformer_plus_plus", "hyperswap_1c_256", "xseg_2"]
LORA = ["selfie_segmenter", "wd14_tagger_model", "wd14_tagger_tags", "sd15_realistic_base"]


def _human(kb: float) -> str:
    return f"{kb/1024:.1f} MB" if kb >= 1024 else f"{kb:.0f} KB"


def _mirrors(url: str):
    """FaceFusion publishes the same files on Hugging Face, which serves them
    20-40x faster than GitHub release assets here (measured 2026-10-14: ~3-5
    MB/s vs ~0.1 MB/s). Try it first, keep GitHub as the fallback."""
    prefix = f"{_BASE}/"
    if url.startswith(prefix):
        tag, fname = url[len(prefix):].split("/", 1)
        return [f"https://huggingface.co/facefusion/{tag}/resolve/main/{fname}", url]
    return [url]


def _download_one(name: str) -> bool:
    if name not in MODELS:
        print(f"[SKIP] Unknown model '{name}'. Known: {', '.join(MODELS)}")
        return False
    url, approx_kb, ext = MODELS[name]
    for i, candidate in enumerate(_mirrors(url)):
        if i:
            print(f"       retrying from {candidate}")
        if _download_from(name, candidate, approx_kb, ext):
            return True
    return False


def _download_from(name: str, url: str, approx_kb: float, ext: str) -> bool:
    dest = MODELS_DIR / f"{name}{ext}"
    tmp = dest.with_suffix(dest.suffix + ".part")

    # Already present and roughly the right size? skip. For files without a
    # trustworthy expected size (e.g. tag CSVs, third-party checkpoints),
    # use a looser tolerance than the original facefusion-assets check.
    if dest.exists():
        have_kb = dest.stat().st_size / 1024
        if abs(have_kb - approx_kb) <= max(approx_kb * 0.05, 64):
            print(f"[OK]   {dest.name} already present ({_human(have_kb)})")
            return True
        print(f"[WARN] {dest.name} wrong size ({_human(have_kb)}, expected ~{_human(approx_kb)}); re-downloading")

    print(f"[GET]  {dest.name}  (~{_human(approx_kb)})  <- {url}")
    # A flaky connection drops large downloads part-way. Keep the .part file and
    # ask for the rest (HTTP Range) instead of starting over; servers that ignore
    # Range answer 200 and the file is rewritten from the start.
    last_error = None
    for attempt in range(1, 7):
        have = tmp.stat().st_size if tmp.exists() else 0
        headers = {"User-Agent": "antigravity-local/1.0"}
        if have:
            headers["Range"] = f"bytes={have}-"
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=60) as resp:
                resumed = have and resp.status == 206
                total = int(resp.headers.get("Content-Length", 0)) + (have if resumed else 0)
                done = have if resumed else 0
                if have and not resumed:
                    print("       server ignored the resume request; starting over")
                with open(tmp, "ab" if resumed else "wb") as f:
                    last_pct = -1
                    while True:
                        buf = resp.read(1024 * 256)
                        if not buf:
                            break
                        f.write(buf)
                        done += len(buf)
                        if total:
                            pct = int(done * 100 / total)
                            if pct != last_pct and pct % 5 == 0:
                                print(f"       {pct:3d}%  ({done//(1024*1024)} / {total//(1024*1024)} MB)")
                                last_pct = pct
                # A dropped connection can make resp.read() return an empty
                # buffer (looks like a clean EOF) well before Content-Length
                # bytes have actually arrived. Without this check that reads as
                # success and leaves a silently truncated file on disk.
                if total and done < total:
                    raise IOError(f"connection closed early: got {done} of {total} bytes")
            tmp.replace(dest)
            print(f"[DONE] {dest.name}  ({_human(dest.stat().st_size/1024)})")
            return True
        except urllib.error.HTTPError as e:
            if e.code == 416 and tmp.exists():   # we already have every byte
                tmp.replace(dest)
                print(f"[DONE] {dest.name}  ({_human(dest.stat().st_size/1024)})")
                return True
            last_error = e
            if e.code in (403, 404):
                break
        except Exception as e:
            last_error = e
        wait = min(30, 3 * attempt)
        print(f"       attempt {attempt} failed ({last_error}); retrying in {wait}s")
        time.sleep(wait)
    print(f"[FAIL] {dest.name}: {last_error}")
    return False


def main(argv):
    MODELS_DIR.mkdir(parents=True, exist_ok=True)

    args = [a for a in argv if not a.startswith("-")]
    flags = {a for a in argv if a.startswith("-")}

    if "--all" in flags:
        names = list(MODELS)
    elif args:
        names = args
    else:
        names = ESSENTIAL
        if "--extras" in flags:
            names = names + EXTRAS
        if "--lora" in flags:
            names = names + LORA

    print(f"Target: {MODELS_DIR}")
    print(f"Models: {', '.join(names)}\n")

    ok = sum(_download_one(n) for n in names)
    print(f"\n{ok}/{len(names)} models ready in {MODELS_DIR}")
    return 0 if ok == len(names) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
