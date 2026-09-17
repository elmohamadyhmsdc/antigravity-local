# LoRA Integration in Reface V2 (Design Document)

**Date**: 2026-09-17  
**Status**: Approved  
**Target Surface**: `the app/dashboard.py` (Reface V2 page), `the app/identity.py`, `the app/reface_engine_v3.py`

---

## 1. Problem Statement & Motivation

In **Reface V2** (powered by `RefaceEngineV3` and `inswapper_128.onnx`), the quality and likeness of face swaps heavily depend on having high-quality, evenly lit, neutral-expression source images of the subject. When users only have 1–2 candid, blurry, or occluded photos of a person, face swaps suffer from poor likeness and artifacts.

Conversely, the app contains a **Character LoRA** pipeline (`lora_trainer.py`, `lora_generate.py`) that trains Stable Diffusion 1.5 LoRAs on a character's face. Once trained, the LoRA can synthesize studio-quality, frontal and angled reference portraits with uniform lighting and clean facial geometry.

By bridging Character LoRA into Reface V2 as a source identity provider, users can use a trained LoRA to automatically generate master reference portraits and extract a superior, quality-weighted 512-d identity vector for face swapping.

---

## 2. Architecture & Data Flow

```mermaid
flowchart TD
    subgraph Character LoRA [venv_ai (PyTorch 3.10)]
        A[Trained LoRA .safetensors] -->|lora_generate.py| B[Synthetic Master Reference Portraits]
    end

    subgraph Reface V2 Bridge [Main venv]
        B -->|buffalo_l FaceAnalysis| C[Face Detection, Embeddings & Poses]
        C -->|identity.py build_identity_embedding| D[512-d Averaged Identity Vector]
        D -->|Cache to disk| E[facesets/lora_<name>.pkl]
    end

    subgraph Reface V2 Engine [ONNX Runtime GPU]
        D -->|AveragedSource| F[RefaceEngineV3 / V2 Swap Pipeline]
        G[Target Image / Video] --> F
        F --> H[High-Fidelity Swapped Output]
    end
```

### Key Technical Decisions:
1. **Separation of Execution Contexts**: LoRA generation runs in `venv_ai` as an isolated subprocess. Swapping runs in `venv` with ONNX Runtime GPU. This prevents any VRAM collision on cards with limited memory (6 GB).
2. **Inswapper Compatibility**: Inswapper consumes only a 512-d InsightFace vector (`normed_embedding`). It cannot read `.safetensors` files directly. Feeding the averaged synthetic embedding into `AveragedSource` satisfies Inswapper while dramatically improving likeness.
3. **Automatic Persistent Caching**: Extracted LoRA face data is saved to `facesets/lora_<person_slug>.pkl`, making the identity permanently reusable across all Reface tabs without re-running detection.

---

## 3. UI & User Experience Changes

### Reface V2 Page (`dashboard.py` Line ~4337)
Expand the **Step 1: Source Face** mode selector:
```python
source_mode = st.radio("Source Mode", ["📤 Upload New", "📦 Use Faceset", "🧬 Trained LoRA"], horizontal=True, key="v2_source_mode")
```

When **🧬 Trained LoRA** is chosen:
1. **Select Character LoRA**: Dropdown populated with characters who have trained LoRA files.
2. **Preview & Selection**: If synthetic reference portraits already exist in `lora_output/<character_name>/`, display them in a multi-select thumbnail grid.
3. **On-Demand Generation**: If no references exist or if fresh angles are requested, a `🎨 Generate Master Reference Faces` button calls `add_job_to_queue("generate_lora_images", ...)` with standard frontal/angled prompts.
4. **Activation**: A button `✅ Use This LoRA Identity` detects faces across the selected portraits, compiles them into a `Faceset`, saves `facesets/lora_<slug>.pkl`, and activates the identity in session state.

---

## 4. Error Handling & Edge Cases

- **Missing LoRA / Weights**: If the model was deleted or unlinked, an inline warning displays a direct link to the Character LoRA page.
- **Unusable Diffusion Artifacts**: InsightFace validates each synthetic portrait. Images where no face or corrupted landmarks are found are gracefully ignored, and a toast/alert informs the user (e.g. *"Detected 3 usable faces out of 4 portraits"*).
- **VRAM Budget**: Memory is cleanly isolated between generation and swapping passes.

---

## 5. Verification Plan

### Automated Tests
- Create `the app/test_lora_reface_bridge.py`:
  - Unit test converting reference image crops into an `AveragedSource`.
  - Validate that the output embedding is exactly shape `(512,)` with unit norm `||v|| = 1.0`.
  - Validate serialization to `facesets/lora_test.pkl` and subsequent deserialization via `Faceset.load()`.
  - Validate error handling when image lists are empty or contain invalid image paths.

### Manual Verification
1. Launch dashboard (`run_dashboard.bat`).
2. Navigate to `🎭 Reface V2` -> `🧬 Trained LoRA`.
3. Select a trained character, verify portrait thumbnails appear.
4. Click `✅ Use This LoRA Identity`.
5. Upload a target image/video, run swap with `✨ HD V3`.
6. Inspect output to verify likeness, sharpness, and clean blending.
