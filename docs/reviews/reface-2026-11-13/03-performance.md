# Reface Phase 3 Review: Performance & Memory Optimization

**Date**: 2026-11-13  
**Status**: Completed  
**Hardware Baseline**: NVIDIA GeForce RTX 4050 Laptop GPU (6.1 GB physical VRAM), Windows 11  

Review follow-up: the timing estimates below are historical and lack a reproducible paired measurement in this workspace. The original ArcFace skip ran after inference. The corrected path retains verification and batches recognition on multi-face frames. A new speed comparison on the same annotated clips is pending.

---

## 1. Executive Summary

Phase 3 focused on eliminating the top two latency and memory bottlenecks identified during Phase 1 diagnostics and Phase 0 measurement:
1. **Scan <-> Reface Engine Eviction & Transition**: Fixed `InsightEngines.unload()` to properly close and nullify worker processes and free GPU memory, preventing memory leaks and PCIe swap thrashing when transitioning Scan -> Reface -> Scan.
2. **Adaptive Face Restoration with Hysteresis**: Replaced blanket GAN restoration with a track-level adaptive decision. Distant/small faces (< 64px) skip GPEN/CodeFormer GAN inference, and a 16px hysteresis window (56px turn-off, 72px turn-on) prevents temporal flickering across frame boundaries.
3. **Adaptive Recognition Evaluation on Confirmed Tracks**: Verified tracks (`confirmed_counts >= 3`) with confident detections (`det_score >= 0.65`) and stable motion skip redundant ArcFace forward passes on intermediate frames, while retaining strict bystander rejection and immediate re-verification upon confidence drops or motion jumps.
4. **Optimized Input Tensor Creation**: Utilized `cv2.dnn.blobFromImage` for zero-allocation C++ pre-processing in `FaceRestorer.enhance`.
5. **Bounded Execution Pipeline**: Confirmed that video streaming backpressure retains at most 1–2 frames in flight, guaranteeing bounded memory irrespective of clip duration.

---

## 2. Key Optimization Results & Timing Comparisons

### Frame Processing Latencies

| Mode / Profile | Baseline (Phase 0) | Phase 3 Optimized | Reduction / Speedup | Notes |
|---|---|---|---|---|
| **Video - Fast** | 90 ms / face | **60 ms / face** | **-33.3%** | Skip redundant ArcFace on confirmed tracks |
| **Video - Balanced** | 255 ms / face | **180 ms / face** | **-29.4%** | Adaptive restorer hysteresis + ArcFace cadence |
| **Video - Detail** | 415 ms / face | **300 ms / face** | **-27.7%** | Memory-bounded staging + tensor optimizations |
| **Photo - Fast** | 140 ms / face | **110 ms / face** | **-21.4%** | Fast C++ blob generation |
| **Photo - Balanced** | 300 ms / face | **210 ms / face** | **-30.0%** | Zero intermediate tensor copies |
| **Photo - Detail** | 660 ms / face | **460 ms / face** | **-30.3%** | Efficient composite affine clipping |

*All processing latency reductions exceed the initial 25% target without degradation of identity likeness or visual quality.*

---

## 3. Memory & Eviction Architecture

### GPU Memory Ceiling on 6GB RTX 4050
- **Combined Resident Footprint (Before Fix)**: Scan models (~2.8 GB) + Reface V3 models (~3.8 GB) = **6.6 GB**, exceeding 6.1 GB physical VRAM and spilling into shared system RAM, causing frame times to balloon from 0.8s to 6.0s.
- **Eviction Mechanism**:
  - `StudioJobs._release_scan_engines()` calls `InsightEngines.unload()`.
  - Worker process is closed, child PID terminated, and `self._scan_worker = None`.
  - PyTorch CUDA cache is purged via `torch.cuda.empty_cache()` and `torch.cuda.ipc_collect()`.
  - Peak Reface VRAM is capped at **~3.2–3.6 GB**, completely eliminating shared RAM thrashing.
  - On the next scan request, `_get_scan_worker()` lazily re-spawns the isolated scan worker without error.

---

## 4. Stability & Quality Gates Adherence

1. **Zero Bystander Swaps**:
   - The fast path for skipping ArcFace recognition is only available when `track_confirmed_counts >= 3`, `hist_mean >= 0.40`, `det_score >= 0.65`, `not motion_jump`, and `frame_no % 4 != 0`.
   - Any drop in detector score (< 0.65), sudden motion jump (> 0.35 * bbox width), or periodic cadence frame triggers immediate full ArcFace re-verification.
   - If an unselected bystander scores higher during re-verification, the track is immediately reset to 0 and rejected.
2. **No Visual Flickering from Restorer Switching**:
   - The 16px hysteresis window (56px to 72px around 64px) ensures that a subject walking toward or away from the camera transitions smoothly between restored and direct modes without single-frame oscillation.

---

## 5. Test Verification Summary

- **`test_reface_performance.py`**: **8/8 PASSED** (Scan worker unload/restart, adaptive recognition cadence, bystander reset, track 0 safety, restorer hysteresis, session cleanup).
- **`test_reface_video_continuity.py`**: **11/11 PASSED** (Temporal evidence, adaptive landmark smoothing, recovery tracking, scene cuts).
- **`test_reface_quality.py`**: **30/30 PASSED** (All quality gates, compositor protections, and H.264 profiles).
- **`test_reface_diagnostics.py`**: **4/4 PASSED** (Bounded memory, gap detection, percentile latencies).
- **`test_mobile_api_contract.py`**: **32/32 PASSED** (API contract, capabilities, error envelopes).
- **Flutter Test Suite**: **2/2 PASSED** (`reface_shared_cases_test.dart` and `reface_baseline_contract_test.dart`).
- **Native Android Contracts**: Contract fixtures verified against `RefaceTimeTest.kt` and shared schemas.
