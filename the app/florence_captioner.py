"""
Florence-2 Vision-Language Captioner module for Antigravity Local.

Supports fine-tuned Florence-2 models (such as florence-2-base-nsfw-v2-ext)
for natural language image captioning in LoRA datasets.

The model folder (models/, gitignored) runs with trust_remote_code, and the stock
repository ships no working code for current transformers. The patched code and
configs live in florence2_patch/ (tracked) and are copied into the model folder
when they are missing there, e.g. after a fresh clone of the weights.

Captions are kept to one short sentence: sd-scripts reads 75 CLIP tokens by
default, and the trigger word, WD14 tags and quality flags must fit after it.
"""

import json
import os
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Callable, Dict, List, Optional, Union

import numpy as np
from PIL import Image

APP_DIR = Path(__file__).parent
MODEL_DIR = APP_DIR / "models" / "florence-2-base-nsfw-v2-ext"
PATCH_DIR = APP_DIR / "florence2_patch"
# Florence runs in venv_ai (CUDA torch). Loading it inside the main venv after an
# onnxruntime-gpu session (WD14, InsightFace) corrupts the heap (0xc0000374) and kills
# the dashboard or the mobile server, so the main venv only talks to a worker process.
WORKER_PYTHON = APP_DIR / "venv_ai" / "Scripts" / "python.exe"
RESULT_PREFIX = "@@florence "
STARTUP_TIMEOUT_S = 240.0
PER_IMAGE_TIMEOUT_S = 90.0   # CPU fallback with 3 beams under load
MIN_FREE_VRAM_BYTES = 1536 * 1024 * 1024
PATCH_FILES = ("configuration_florence2.py", "modeling_florence2.py", "processing_florence2.py",
               "config.json", "generation_config.json", "preprocessor_config.json")
MAX_CAPTION_WORDS = 25


def clean_caption(text: str, max_words: int = MAX_CAPTION_WORDS) -> str:
    """Drop repeated and unfinished sentences, keep at most `max_words` words of whole sentences."""
    text = re.sub(r"<[^>]+>", " ", text or "")
    text = re.sub(r"\s+", " ", text).strip()
    sentences = re.findall(r"[^.!?]+[.!?]", text)
    if not sentences and text:
        sentences = [text]
    kept, seen, words = [], set(), 0
    for sentence in sentences:
        sentence = sentence.strip()
        key = sentence.lower().rstrip(".!?")
        n = len(sentence.split())
        if not key or key in seen:
            continue
        if kept and words + n > max_words:
            break
        seen.add(key)
        kept.append(sentence)
        words += n
    out = " ".join(kept)
    if len(out.split()) > max_words:
        out = " ".join(out.split()[:max_words])
    return out.rstrip(" .!?,")


def ensure_model_code(model_path: Path = MODEL_DIR, patch_dir: Path = PATCH_DIR) -> None:
    """Copy the patched code/configs into the model folder when its own copy is missing."""
    if not patch_dir.is_dir() or (model_path / "modeling_florence2.py").is_file():
        return
    for name in PATCH_FILES:
        if (patch_dir / name).is_file():
            shutil.copy2(patch_dir / name, model_path / name)


class FlorenceCaptioner:
    """Wrapper around Florence-2 for captioning and dataset generation.

    `available` turns False after a failed load, so a broken install costs one
    attempt per process instead of one per image.
    """

    def __init__(self, model_path: Union[str, Path] = MODEL_DIR, device: Optional[str] = None):
        self.model_path = Path(model_path)
        self.device = device
        self.processor = None
        self.model = None
        self.available = (os.environ.get("AG_FLORENCE_CAPTIONS", "1").strip().lower() not in ("0", "false", "no", "off")
                          and (self.model_path / "model.safetensors").is_file())

    def _ensure_loaded(self):
        if self.model is not None:
            return

        import torch
        from transformers import AutoProcessor, AutoModelForCausalLM

        ensure_model_code(self.model_path)
        if self.device is None:
            self.device = "cpu"
            if torch.cuda.is_available():
                # Another job holding the GPU makes a CUDA load crawl instead of failing.
                free, _ = torch.cuda.mem_get_info()
                self.device = "cuda" if free >= MIN_FREE_VRAM_BYTES else "cpu"

        self.processor = AutoProcessor.from_pretrained(str(self.model_path), trust_remote_code=True)
        try:
            self._load_model(self.device)
        except Exception as e:
            if self.device != "cuda":
                raise
            # GPU busy or out of memory: CPU is slower but finishes.
            print(f"[CAPTIONER] Florence-2 on CUDA failed ({e}); using CPU", file=sys.stderr)
            self.model = None
            torch.cuda.empty_cache()
            self.device = "cpu"
            self._load_model("cpu")

    def _load_model(self, device):
        import torch
        from transformers import AutoModelForCausalLM

        self.model = AutoModelForCausalLM.from_pretrained(
            str(self.model_path),
            dtype=torch.float16 if device == "cuda" else torch.float32,
            trust_remote_code=True,
        )
        self.model.to(device)
        self.model.eval()

    def caption(
        self,
        image: Union[np.ndarray, Image.Image],
        task: str = "<CAPTION>",
        max_new_tokens: int = 48,
        num_beams: int = 3,
    ) -> str:
        """
        One short caption for the image (PIL Image or BGR numpy array), or "" when the
        model is unavailable. Supported tasks: '<CAPTION>', '<DETAILED_CAPTION>', '<MORE_DETAILED_CAPTION>'.
        """
        if not self.available:
            return ""
        try:
            self._ensure_loaded()
        except Exception as e:
            self.available = False
            self.unload()
            print(f"[CAPTIONER] Florence-2 failed to load, captions continue without it: {e}")
            return ""
        import torch

        if isinstance(image, np.ndarray):
            # Convert BGR (OpenCV) to RGB (PIL)
            if len(image.shape) == 3 and image.shape[2] == 3:
                rgb = np.ascontiguousarray(image[:, :, ::-1])
            else:
                rgb = image
            pil_image = Image.fromarray(rgb).convert("RGB")
        elif isinstance(image, Image.Image):
            pil_image = image.convert("RGB")
        else:
            raise ValueError(f"Unsupported image type: {type(image)}")

        # Florence-2 is trained on 768x768. Under transformers 5 the processor passes the
        # photo through at full size, and a tall crop (705x1904) trips a CUDA device-side
        # assert that also poisons every later image in the process.
        image_size = (pil_image.width, pil_image.height)
        pil_image = pil_image.resize((768, 768), Image.BICUBIC)
        inputs = self.processor(text=task, images=pil_image, return_tensors="pt")
        inputs = {k: v.to(self.device) for k, v in inputs.items()}
        if self.device == "cuda":
            inputs["pixel_values"] = inputs["pixel_values"].to(torch.float16)

        with torch.no_grad():
            generated_ids = self.model.generate(
                input_ids=inputs["input_ids"],
                pixel_values=inputs["pixel_values"],
                max_new_tokens=max_new_tokens,
                num_beams=num_beams,
                no_repeat_ngram_size=3,
                early_stopping=True,
            )

        generated_text = self.processor.batch_decode(generated_ids, skip_special_tokens=False)[0]
        parsed = self.processor.post_process_generation(
            generated_text,
            task=task,
            image_size=image_size,
        )

        if isinstance(parsed, dict) and task in parsed:
            return clean_caption(str(parsed[task]))
        return clean_caption(str(parsed))

    def unload(self):
        """Unload model from VRAM/RAM to free resources."""
        import gc

        self.model = None
        self.processor = None
        gc.collect()
        try:
            import torch
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
        except Exception:
            pass


_CAPTIONER_INSTANCE: Optional[FlorenceCaptioner] = None


def get_florence_captioner() -> FlorenceCaptioner:
    """Singleton getter for FlorenceCaptioner (in-process; use inside venv_ai only)."""
    global _CAPTIONER_INSTANCE
    if _CAPTIONER_INSTANCE is None:
        _CAPTIONER_INSTANCE = FlorenceCaptioner()
    return _CAPTIONER_INSTANCE


def florence_enabled() -> bool:
    return FlorenceCaptioner().available


def caption_paths(paths: List[Union[str, Path]],
                  progress: Optional[Callable[[int, int], None]] = None,
                  python: Path = WORKER_PYTHON,
                  worker_command: Optional[List[str]] = None) -> Dict[str, str]:
    """Captions for image files, from a Florence-2 worker process in venv_ai.

    Returns {str(path): caption} for the images it finished. Never raises for worker
    trouble (missing venv/model, crash, timeout): those images just get no caption.
    `progress(done, total)` is called per image; if it raises (a cancelled job), the
    worker is killed and the exception propagates. `worker_command` replaces the
    venv_ai command (tests).
    """
    paths = [str(p) for p in paths]
    if worker_command is None:
        if not paths or not florence_enabled() or not Path(python).is_file():
            return {}
        worker_command = [str(python), "-u", str(Path(__file__).resolve()), "--worker"]
    elif not paths:
        return {}
    results: Dict[str, str] = {}
    lines: "queue.Queue[Optional[str]]" = queue.Queue()
    try:
        proc = subprocess.Popen(
            worker_command,
            cwd=str(APP_DIR), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            env=dict(os.environ, PYTHONIOENCODING="utf-8", HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1"),
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    except Exception as e:
        print(f"[CAPTIONER] Florence-2 worker did not start: {e}")
        return {}

    def read():
        try:
            for raw in proc.stdout:
                lines.put(raw.decode("utf-8", errors="replace"))
        finally:
            lines.put(None)

    threading.Thread(target=read, daemon=True).start()
    try:
        proc.stdin.write(json.dumps(paths).encode("utf-8"))
        proc.stdin.close()
        deadline = time.monotonic() + STARTUP_TIMEOUT_S
        while len(results) < len(paths):
            try:
                line = lines.get(timeout=max(0.1, deadline - time.monotonic()))
            except queue.Empty:
                print(f"[CAPTIONER] Florence-2 worker timed out after {len(results)}/{len(paths)} images")
                break
            if line is None:
                break
            if not line.startswith(RESULT_PREFIX):
                continue
            try:
                item = json.loads(line[len(RESULT_PREFIX):])
                results[item["path"]] = str(item.get("caption") or "")
            except (ValueError, KeyError, TypeError):
                continue
            deadline = time.monotonic() + PER_IMAGE_TIMEOUT_S
            if progress:
                progress(len(results), len(paths))
    except OSError as e:
        print(f"[CAPTIONER] Florence-2 worker failed: {e}")
    finally:
        if proc.poll() is None:
            proc.kill()
        try:
            proc.wait(timeout=10)
        except Exception:
            pass
    if len(results) < len(paths):
        print(f"[CAPTIONER] Florence-2 described {len(results)}/{len(paths)} images (exit {proc.returncode})")
    return {p: c for p, c in results.items() if c}


def _worker() -> None:
    """venv_ai side: JSON list of image paths on stdin, one RESULT_PREFIX line per image."""
    paths = json.loads(sys.stdin.read() or "[]")
    captioner = FlorenceCaptioner()
    for path in paths:
        try:
            with Image.open(path) as image:
                text = captioner.caption(image)
        except Exception as e:
            print(f"[CAPTIONER] {path}: {e}", file=sys.stderr)
            text = ""
        print(RESULT_PREFIX + json.dumps({"path": path, "caption": text}), flush=True)


if __name__ == "__main__":
    if "--worker" in sys.argv:
        _worker()
