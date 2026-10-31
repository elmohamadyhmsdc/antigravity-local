"""
Florence-2 Vision-Language Captioner module for Antigravity Local.

Supports fine-tuned Florence-2 models (such as florence-2-base-nsfw-v2-ext)
for rich natural language image captioning, tag generation, and dataset building.
"""

import os
from pathlib import Path
from typing import Optional, Union
import numpy as np
from PIL import Image

MODEL_DIR = Path(__file__).parent / "models" / "florence-2-base-nsfw-v2-ext"


class FlorenceCaptioner:
    """Wrapper around Florence-2 for captioning and dataset generation."""

    def __init__(self, model_path: Union[str, Path] = MODEL_DIR, device: Optional[str] = None):
        self.model_path = Path(model_path)
        self.device = device
        self.processor = None
        self.model = None
        self.available = False

        if not self.model_path.exists() or not (self.model_path / "model.safetensors").exists():
            return

        self.available = True

    def _ensure_loaded(self):
        if self.model is not None:
            return

        import torch
        from transformers import AutoProcessor, AutoModelForCausalLM

        if self.device is None:
            self.device = "cuda" if torch.cuda.is_available() else "cpu"

        dtype = torch.float16 if self.device == "cuda" else torch.float32

        self.processor = AutoProcessor.from_pretrained(str(self.model_path), trust_remote_code=True)
        self.model = AutoModelForCausalLM.from_pretrained(
            str(self.model_path),
            torch_dtype=dtype,
            trust_remote_code=True,
        )
        self.model.to(self.device)
        self.model.eval()

    def caption(
        self,
        image: Union[np.ndarray, Image.Image],
        task: str = "<DETAILED_CAPTION>",
        max_new_tokens: int = 120,
        num_beams: int = 1,
    ) -> str:
        """
        Generate a caption for the provided image (PIL Image or BGR numpy array).
        Supported tasks: '<CAPTION>', '<DETAILED_CAPTION>', '<MORE_DETAILED_CAPTION>'.
        """
        if not self.available:
            return ""

        self._ensure_loaded()
        import torch

        if isinstance(image, np.ndarray):
            # Convert BGR (OpenCV) to RGB (PIL)
            if len(image.shape) == 3 and image.shape[2] == 3:
                rgb = image[:, :, ::-1]
            else:
                rgb = image
            pil_image = Image.fromarray(rgb).convert("RGB")
        elif isinstance(image, Image.Image):
            pil_image = image.convert("RGB")
        else:
            raise ValueError(f"Unsupported image type: {type(image)}")

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
            )

        generated_text = self.processor.batch_decode(generated_ids, skip_special_tokens=False)[0]
        parsed = self.processor.post_process_generation(
            generated_text,
            task=task,
            image_size=(pil_image.width, pil_image.height),
        )

        if isinstance(parsed, dict) and task in parsed:
            return str(parsed[task]).strip()
        elif isinstance(parsed, str):
            return parsed.strip()
        return str(parsed).strip()

    def unload(self):
        """Unload model from VRAM/RAM to free resources."""
        import gc
        import torch

        self.model = None
        self.processor = None
        gc.collect()
        if torch.cuda.is_available():
            torch.cuda.empty_cache()


_CAPTIONER_INSTANCE: Optional[FlorenceCaptioner] = None


def get_florence_captioner() -> FlorenceCaptioner:
    """Singleton getter for FlorenceCaptioner."""
    global _CAPTIONER_INSTANCE
    if _CAPTIONER_INSTANCE is None:
        _CAPTIONER_INSTANCE = FlorenceCaptioner()
    return _CAPTIONER_INSTANCE
