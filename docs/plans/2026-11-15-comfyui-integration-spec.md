# ComfyUI Integration Specification & Roadmap
**Project:** Antigravity Local & Mobile (`d:\AndroidScan\gallary`)  
**Date:** 2026-11-15  
**Status:** Architecture Specification / Next Session Execution Blueprint  

---

## 1. Executive Summary & Objective

The objective of this integration is to bridge the existing, verified **ComfyUI Desktop** backend, its optimized models, and specialized workflows with the **Antigravity Local** (`the app/`) and **Antigravity Mobile** (`mobile/`) ecosystem.

### Core Problems Solved:
1. **6GB VRAM Constraint & SDXL OOM Prevention:**  
   Standard unquantized Diffusers SDXL inpainting (`~6.5GB+`) risks `CUDA Out Of Memory` on the local **RTX 4050 Laptop GPU (6GB VRAM)**. ComfyUI already possesses **`ComfyUI-GGUF`** with **`juggernaut-xl-v9-Q4_K.gguf`**, executing high-fidelity SDXL inpainting in under **4GB VRAM**.
2. **Advanced Clothing & Restyle Quality:**  
   Replacing basic Diffusers inpainting with ComfyUI's pre-configured **`DifferentialDiffusion`** and **`CLIPSegClothingSegmenter`** pipeline produces photorealistic garment replacement with seamless boundary blending and zero face distortion.
3. **4K High-Resolution Output:**  
   Enabling **`UltimateSDUpscale`** + **`4x-UltraSharp`** with **Tile ControlNet** delivers artifact-free 2K/4K upscaling via tile processing without memory spikes.
4. **Storage Deduplication:**  
   Unifying model weight storage between ComfyUI and `gallary` saves over **25 GB** of duplicate disk storage.

---

## 2. Hardware Profile & Operational Boundaries

* **Target GPU:** NVIDIA GeForce RTX 4050 Laptop GPU
* **Total VRAM:** 6,141 MiB (~6.0 GB GDDR6)
* **Driver / CUDA:** Driver 621.24 / CUDA 13.0
* **Working VRAM Budget:** Maximum **4.8 GB** per active job (retaining 1.2 GB for OS, desktop window manager, and display).
* **Quantization Strategy:**
  * SD 1.5 checkpoints run in native **FP16** (~3.5 GB VRAM).
  * SDXL checkpoints run strictly via **GGUF Q4_K** (~3.8 GB VRAM).
  * Upscaling runs via **Tiled Processing** (512px–768px tile size, ~3.0 GB VRAM peak).

---

## 3. Master Path Registry

### A. ComfyUI Infrastructure Paths
| Resource Component | Exact File / Directory Path | Role / Content |
|---|---|---|
| **ComfyUI App Executable** | `D:\AndroidScan\Comfy Desktop\Comfy Desktop.exe` | Electron UI launcher & supervisor |
| **ComfyUI Python Runtime** | `D:\Comfy-Desktop\ComfyUI-Installs\laptop\standalone-env\python.exe` | Python 3.13.12 + PyTorch 2.12.1+cu130 + UV |
| **ComfyUI Source Root** | `D:\Comfy-Desktop\ComfyUI-Installs\laptop\ComfyUI\` | Main ComfyUI server & backend code |
| **Custom Nodes Directory** | `D:\Comfy-Desktop\ComfyUI-Installs\laptop\ComfyUI\custom_nodes\` | `ComfyUI-GGUF`, `ComfyUI_UltimateSDUpscale`, `clipseg_clothing_segmenter.py`, `websocket_image_save.py` |
| **Workflows Directory** | `D:\Comfy-Desktop\ComfyUI-Installs\laptop\ComfyUI\user\default\workflows\` | Pre-built production JSON workflows |
| **Models Root Directory** | `D:\Comfy-Desktop\ComfyUI-Shared\models\` | Central repository for all weights |
| **Shared Outputs Directory** | `D:\Comfy-Desktop\ComfyUI-Shared\output\` | Rendered cache & intermediate generations |

### B. Gallary Application Paths
| Resource Component | Exact File / Directory Path | Role / Content |
|---|---|---|
| **Project Monorepo Root** | `D:\AndroidScan\gallary\` | Monorepo root |
| **Antigravity Local Backend** | `D:\AndroidScan\gallary\the app\` | Streamlit dashboard, FastAPI mobile server, worker manager |
| **Photo Edit Server Worker** | `D:\AndroidScan\gallary\the app\photo_edit_worker.py` | Worker handling inpainting, Big-LaMa removal, and diffusers |
| **Photo Edit Logic** | `D:\AndroidScan\gallary\the app\photo_edit.py` | Option validation, cropping, face core protection, mask prep |
| **Mobile API Server** | `D:\AndroidScan\gallary\the app\mobile_api\` | FastAPI HTTPS API (port 8443) serving the Flutter app |
| **Existing Models Storage** | `D:\AndroidScan\gallary\the app\models\` | Existing ONNX, Big-LaMa, and diffusers weights |
| **Flutter Mobile App** | `D:\AndroidScan\gallary\mobile\` | Android client app (`lib/features/photo_edit/`, `studio/`) |

---

## 4. Model & Workflow Inventory

### Verified Models in `D:\Comfy-Desktop\ComfyUI-Shared\models`:
1. **Base Checkpoints:**
   * `checkpoints\CyberRealistic_V5.0_FP16.safetensors` (3.97 GB) — High-realism human and portrait generation.
   * `checkpoints\CyberRealistic_V9_FP32.safetensors` (3.97 GB) — Latest fine-tuned realism.
   * `checkpoints\epicrealism_naturalSinRC1VAE.safetensors` (1.99 GB) — Fast, light SD 1.5 model with baked-in VAE.
   * `checkpoints\sd_xl_turbo_1.0_fp16.safetensors` (6.46 GB) — Ultra-fast 1–4 step generation.
2. **GGUF Models (Optimized for 6GB VRAM):**
   * `unet\juggernaut-xl-v9-Q4_K.gguf` (2.76 GB) + `clip\juggernaut-xl-v9-Q4_K.gguf` (2.76 GB) — Juggernaut XL in Q4_K quantization.
   * `diffusion_models\qwen-image-2.1-UC-Q4_K_M.gguf` (4.29 GB) + `qwen_image_2.1_int4_convrot.safetensors` (3.41 GB).
   * `text_encoders\qwen3vl_8b_int8_convrot.safetensors` (8.71 GB).
3. **ControlNet & Inpainting Guidance:**
   * `controlnet\control_v11p_sd15_inpaint_fp16.safetensors` (689 MB) — Exact mask infilling.
   * `controlnet\control_v11p_sd15_openpose_fp16.safetensors` (689 MB) — Human body pose preservation.
   * `controlnet\control_v11u_sd15_tile_fp16.safetensors` (689 MB) — Tile-guided super-resolution.
4. **Super-Resolution / Upscalers:**
   * `upscale_models\4x-UltraSharp.pth` (64 MB) — State-of-the-art detail preservation.
   * `upscale_models\4x_NMKD-Superscale-SP_178000_G.pth` (64 MB).
5. **VAEs:**
   * `vae\vae-ft-mse-840000-ema-pruned.safetensors` (319 MB) — Standard SD 1.5 color/detail decoder.
   * `vae\sdxl_vae.safetensors` (319 MB) — SDXL latent decoder.

### Key Pre-Configured Workflows:
* `SD15_DiffDiffusion_Outfit_Changer.json` — Clothes auto-segmentation & Differential Diffusion replacement.
* `SDXL_Precision_Character_Outfit_Changer.json` — GGUF SDXL high-res clothing replacement.
* `CyberRealistic_Ultimate_SD_Upscale.json` — Tile-based upscaling to 2K/4K.
* `Uncensored_Image_Editor_720p_1080p.json` — High-definition inpainting with ControlNet.
* `Qwen_image_2_1_image_edit_HQ.json` — Prompt-driven natural language photo manipulation.

---

## 5. Architectural Integration Strategy

```
                                  +------------------------------------+
                                  | Flutter Mobile App (`mobile/`)    |
                                  | (AI Studio / Photo Edit / Restyle) |
                                  +-----------------+------------------+
                                                    |  HTTPS (Port 8443)
                                                    v
                                  +------------------------------------+
                                  | Antigravity Local Backend          |
                                  | `the app/` (FastAPI / Streamlit)   |
                                  +-----------------+------------------+
                                                    |
                          +-------------------------+-------------------------+
                          |                                                   |
                          v                                                   v
       [Existing Lightweight Engine]                             [New ComfyUI Bridge Client]
       `photo_edit_worker.py` (Subprocess)                      `the app/comfy_bridge.py`
       - Big-LaMa Removal (< 1s)                                - WebSocket & REST (`localhost:8188`)
       - Realistic Vision Inpainting (768p)                     - SDXL GGUF Inpainting (1024p)
       - InsightFace / YOLOX Protection                         - Differential Diffusion Outfit Changer
                                                                - Ultimate SD 4K Upscale
                                                                              |
                                                                              v
                                                                +-----------------------------+
                                                                | ComfyUI Headless Server     |
                                                                | (Port 8188, RTX 4050 GPU)   |
                                                                | Custom Node:                |
                                                                | `websocket_image_save.py`   |
                                                                +-----------------------------+
```

### Design Principles:
1. **Zero Degradation of Existing Features:**  
   Big-LaMa object removal and lightweight ONNX face-swapping remain on their dedicated fast pipelines.
2. **Headless Execution:**  
   ComfyUI is orchestrated in headless mode (`main.py --listen 127.0.0.1 --port 8188 --dont-up-scale-nc`), controlled programmatically via REST API (`POST /prompt`) and WebSocket (`/ws`) for progress streaming and binary image return.
3. **In-Memory Streaming (No Disk Bloat):**  
   The existing `websocket_image_save.py` node sends rendered image buffers directly over the WebSocket to `the app/`, eliminating disk writes and cleanup overhead.
4. **Shared Models (Symlink / Unified Paths):**  
   Configure `gallary/the app` to resolve weights from `D:\Comfy-Desktop\ComfyUI-Shared\models` to avoid storing duplicate multi-gigabyte models.

---

## 6. Execution Roadmap for the Next Session

### Phase 1: ComfyUI Client Bridge (`comfy_bridge.py`)
- [ ] Create `the app/comfy_bridge.py` providing:
  - Connection management (`http://127.0.0.1:8188` & `ws://127.0.0.1:8188/ws`).
  - Health check & auto-start capability (can launch ComfyUI if not running).
  - Workflow dispatch function: `dispatch_workflow(api_prompt_dict, images_dict) -> bytes`.
  - Progress listener yielding completion percentage to the caller.

### Phase 2: Workflow API Templates
- [ ] Export existing GUI workflows as **API Format JSONs**:
  - `workflows_api/sdxl_gguf_inpaint.json`
  - `workflows_api/outfit_changer_diffdiffusion.json`
  - `workflows_api/ultimate_sd_upscale.json`
- [ ] Implement parameter injection helpers (injecting prompt, seed, denoise strength, mask image, input image).

### Phase 3: Integration with `the app/photo_edit.py`
- [ ] Register new models and operations in `photo_edit.py`:
  - `MODEL_SDXL_GGUF = 'sdxl_gguf'` (routed to ComfyUI Juggernaut XL Q4).
  - `MODEL_OUTFIT_DIFF = 'outfit_diff'` (routed to ComfyUI Differential Diffusion).
  - `OPERATION_UPSCALE = 'upscale'` (routed to Ultimate SD Upscale).
- [ ] Update `photo_edit_worker.py` to route these requests to `comfy_bridge.py`.

### Phase 4: Mobile App & API Contract Exposure
- [ ] Update `the app/mobile_api/contract/openapi.yaml` to include new models and upscale operations.
- [ ] Update Flutter client (`PhotoEditModel` in `mobile/lib/features/photo_edit/selection_model.dart`):
  - Add `sdxlGguf` option with badge "1024p Ultra".
  - Add "Upscale 4K" action in `MediaViewerScreen` / `StudioScreen`.
- [ ] Regenerate contract fixtures and run Flutter analyzer/tests.

### Phase 5: Verification & End-to-End Testing
- [ ] Test VRAM usage during active SDXL GGUF run (must stay under 5.0 GB).
- [ ] Verify execution time:
  - SD 1.5 Outfit Changer: target ≤ 5 seconds.
  - SDXL GGUF Inpainting: target ≤ 15 seconds.
  - 4K Ultimate Upscale: target ≤ 30 seconds.
- [ ] Verify seamless delivery of edited photos back to the Flutter phone app over Wi-Fi.
