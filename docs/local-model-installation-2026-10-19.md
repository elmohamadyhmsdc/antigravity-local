# Remaining model installation — 2026-10-19

The user requested downloading the remaining missing models. The current local
readiness probe identified only `diffusers/stable-diffusion-xl-1.0-inpainting-0.1`.
The previously installed base Restyle, Reface, body and LoRA models were ready.

Installed the 18 SDXL FP16 component/configuration files used by the existing
`get_sdxl_pipeline` loader: **6,941,218,469 bytes** (6.941 decimal GB). Repository
revision: `115134f363124c53c7d878647567d04daf26e41e`.

- Location: `the app/models/undress/diffusers--stable-diffusion-xl-1.0-inpainting-0.1/`.
- All weights matched published SHA-256 hashes; small files matched Git blob
  hashes. Every selected file was checked again after the transfers completed.
- Receipt: `the app/models/undress/refine-download-manifest.json`.
- Downloader: `mobile/tools/download_restyle_refine.py`; it reuses the existing
  base downloader's resumable transfers and verification, with a separate
  explicit SDXL file list and receipt. The base-only downloader remains unchanged.
- Download log: `mobile/build/restyle-refine-download.log`.

Validation completed with the existing environments and without package or
Python/CUDA changes:

- `venv/Scripts/python.exe -m mobile_api --check-models` succeeded:
  `restyle_refine: true`, `restyle_missing_models: []`; all other supported
  engines remained ready. There are no installed DFM models, as before.
- The application's `get_sdxl_pipeline('cpu', torch.float16)` successfully loaded
  all components with Hugging Face/Transformers offline. Its UNet has 9 input
  channels and its second text encoder is present. Log:
  `mobile/build/restyle-refine-load-check.log`.

The load check did not perform inference or assess GPU memory, image quality or
phone behaviour. Diffusers warned that CPU FP16 inference is unsupported; this
check exercised deserialization and loading only. No personal images were used.
