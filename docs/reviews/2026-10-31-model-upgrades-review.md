# Review: model upgrades of 2026-10-31

Scope: the uncommitted model changes recorded in the handoff section "AI Model Upgrades &
Hardware Compatibility (RTX 4050 6GB)": `mask_utils.py` (RMBG), `undress_core.py` /
`model_readiness.py` (Realistic Vision V6 inpainting + V5.1 fallback), `undress_engine.py`
(Hyper-SD 8-step LoRA), `reface.py` / `reface_engine_v3.py` (HyperSwap 1c), `florence_captioner.py`
+ `lora_dataset.py` (Florence-2 captions), `download_upgrades.py`.
Read-only review; no code was changed.

## Findings (most severe first)

### 1. HIGH (verified): RMBG preprocessing is wrong, so the "person" mask is almost the whole frame
`mask_utils.get_segmentation_mask`:
- normalises with ImageNet mean/std. RMBG-1.4 expects `x/255 - 0.5` (std 1.0);
- skips RMBG's min-max normalisation of the output before the 0.5 threshold;
- `get_person_bbox` passes a **BGR** image straight in (the model expects RGB).

Measured on six real body crops from `lora_datasets/aya_selim` (CPU, `models/rmbg.onnx`):

| crop | current foreground | correct foreground | IoU |
|---|---|---|---|
| 0000 | 0.79 | 0.60 | 0.75 |
| 0001 | 0.99 | 0.61 | 0.62 |
| 0002 | 0.75 | 0.26 | 0.32 |
| 0003 | 0.99 | 0.42 | 0.43 |
| 0004 | 0.95 | 0.60 | 0.63 |
| 0005 | 0.96 | 0.46 | 0.47 |

A side-by-side check showed the current mask keeps the whole picture (sky, trees, building);
the correct preprocessing cuts out the person. Effect: `get_person_bbox` returns roughly the
whole image, so LoRA dataset **body crops lose their framing** compared with the old selfie
segmenter. `test_lora_dataset.py` only checks for a non-None box, so it did not catch this.
The docstring also calls RMBG 1.4 "BiRefNet"; BiRefNet is RMBG 2.0, 1.4 is IS-Net.

**Fix:** RGB input, `x/255 - 0.5`, min-max on the output, then threshold; `get_person_bbox`
converts BGR→RGB before calling.

### 2. MEDIUM (regression): MediaPipe fallback now receives BGR
The old `get_person_bbox` converted BGR→RGB before MediaPipe. The new shared
`get_segmentation_mask` does not, so the fallback (no `rmbg.onnx`) gets BGR labelled `SRGB`.

### 3. MEDIUM: RMBG is salient-object segmentation, not person segmentation
It keeps whatever stands out: in the test photo it kept the toy the person was holding and part
of a watermark bar. The box is the min/max of every foreground pixel, so one stray object
widens the "person" box. **Fix:** keep only the connected component that contains/overlaps the
main face (or the body keypoints) before taking the box.

### 4. MEDIUM: "Detail" now uses HyperSwap 1c, against this repo's own measurement
`reface.py` forces `hyperswap_1c_256` for `quality_profile == "detail"`, and
`SWAPPER_PREFERENCE` puts 1c ahead of inswapper. The comment right above
`SWAPPER_PREFERENCE` (eval_reface.py, 2026-10-14) measured identity
**1b 0.430 > inswapper 0.421 > 1c 0.411**. 1c was the weakest. The phone exposes "detail"
(`mobile/lib/features/reface/reface_options.dart`), so phone users who pick the best-quality option
get the lowest-identity swapper. **Fix:** revert, or re-run
`eval_reface.py --stage swappers` and keep 1c only if it wins.

### 5. MEDIUM (unverified quality): Hyper-SD is always on, generation not A/B-tested
`get_sd15_pipeline` fuses `Hyper-SD15-8steps-CFG-lora` into the RV6 inpainting UNet whenever the
file exists and drops base steps 20 → 8. The handoff verifies only that the pipeline *loads*.
No before/after image check was recorded. The LoRA was trained on SD1.5 base, here it runs on
an inpainting UNet with OpenPose ControlNet under UniPC (the Hyper-SD authors use DDIM/TCD with
trailing spacing). Guidance 6.0 is inside its intended CFG range. There is no switch to turn it
off. **Fix:** a payload/setting flag (default on only after a check), and an A/B on 3 photos at
20 steps without vs 8 steps with. (Not affected: `refine_tiles` is no longer called, and SDXL uses
its own pipeline.)

### 6. LOW: V6 inpainting housekeeping
- `unet/` holds both `diffusion_pytorch_model.bin` (1.7 GB pickle) and the converted
  `.safetensors` (1.7 GB). Diffusers prefers safetensors, so the `.bin` is dead weight and a
  pickle on disk. Deleting it needs the user's OK.
- Source is `andregn/Realistic_Vision_V6.0-inpainting`, an individual re-upload, not the original
  author's repo. Worth knowing; it loads (`in_channels: 9`, like V5.1).
- Fallback logic is correct: `ensure_local_model` and `model_readiness` both try V6 then V5.1.
  If neither exists, `ensure_local_model` would still `snapshot_download` V6 (2.4 GB). This
  existed before for V5.1, but downloads are not authorised; consider refusing instead.

### 7. LOW: Florence-2 captioner is not wired in, and its code lives outside the repo
- Nothing passes `captioner=` to `build_dataset*`, so the feature currently never runs.
- The model folder (`models/florence-2-base-nsfw-v2-ext`, gitignored) now has three untracked
  `.py` files and modified configs, loaded with `trust_remote_code=True`. That code is not in this
  repository's history and is lost on a re-clone. Move it into the project, or record it.
- In the main `venv` torch is CPU-only. If it gets wired into the dashboard, it runs in fp32 on CPU.
  It was tested in `venv_ai`.
- Design point: a natural-language description of hair, clothes etc. in every caption teaches the
  LoRA that those attributes are *not* part of the trigger word. That may or may not be wanted.

### 8. LOW: `download_upgrades.py` checks size only
`download_file` takes `sha256`, but no caller passes one.

## What is fine
- `buffalo_l` kept as the embedding model (protects every phone library).
- V6/V5.1 fallback in `undress_core` + `model_readiness` is consistent.
- RMBG license: BRIA RMBG-1.4 is free for non-commercial use only. That's fine for this
  local tool; just note it.

## Resolution (same day)
All findings were fixed except deleting the V6 `.bin`, which needs the user (see the handoff
section "Model upgrade fixes"). Two more crashes turned up while verifying, and both are fixed:
Florence loading after onnxruntime-gpu in one process (heap corruption), and tall images in
Florence (CUDA assert). The V5.1 fallback was removed at the user's request.
