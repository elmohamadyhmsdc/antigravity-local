# Reface quality roadmap: identity building, better models, measured choices

**Date**: 2026-10-14
**Scope**: `the app/` Reface V2 page (engine V3), identity ("model of a person") building, swap/restore models.
**Constraint**: RTX 4050 Laptop, 6 GB VRAM. Personal / educational use only, so non-commercial model licences are acceptable (the user said so on 2026-10-14).

## 0. Done (2026-10-14) — correctness + lossless speed

Measured on a 1080p frame with one ~250 px face, against the output the pipeline was *meant* to produce:

| | before | after |
|---|---|---|
| per-frame time, 1080p | ~1100 ms (0.9 fps) | ~350 ms (end-to-end video: 2.5 fps) |
| per-frame time, 4K | ~1900 ms | ~355 ms |
| output vs intended HD composite | PSNR 23 dB (guard bug: plain insightface paste) | PSNR 62-66 dB, max 1-3 grey levels |

- `face_changed`: the "did it swap" guard is measured inside the face box. The whole-frame mean discarded the HD composite for every face under ~430 px in 1080p (and failed big/group photos).
- Detection runs det_10g only; recognition on demand. ROI-only place/paste. Gain map at 1/4 res. Parser ArgMax inside the ONNX graph. Restorer overlapped with the original-crop masks. float32 grain.
- Faces ticked in the UI are found per track by identity (`FaceSelector`), not by detection index.
- Fractional frame rates kept (29.97 stayed 29.97; was 29 -> audio drift and a cut tail).
- V3 background video jobs pause/resume: silent x264 parts, joined by stream copy, audio muxed once.
- UI: V2-only controls hidden under V3; missing restorers labelled.
- Tests: 7 new in `test_compositor.py` (incl. small-face guard regression, ROI paste parity, part join + audio). Verified end to end: 120-frame 29.97 fps clip, stopped at frame 48, resumed, 120 frames / 4.01 s / audio.
- Tried and rejected: `onnxruntime.transformers.float16` conversion (inswapper -> NaN, others 2-5x slower). TensorRT EP is listed but its libraries are not installed.

## 0.5 Done (2026-10-14, later) — measured model choices

`eval_reface.py` on 4 people (`lora_datasets`) x 2 DFL sample clips, 160 frames each, identity scored with glintr100 against held-out photos (ceiling: a real photo scores 0.62-0.73).

| Stage | Result | Default now |
|---|---|---|
| Swapper (+CodeFormer) | hyperswap_1b 0.430 / inswapper 0.421 / hyperswap_1c 0.411; 1b won 5 of 8 pairs, 369 vs 403 ms | `hyperswap_1b_256` (inswapper fallback) |
| Restorer (on 1b) | none 0.517 / gpen_1024 0.514 / **gpen_512 0.508** / restoreformer++ 0.490 / gfpgan 0.485 / codeformer 0.430; sharpness vs source gpen_512 0.879 best; 312 ms vs codeformer 420 | `gpen_bfr_512` |
| Occluder | xseg_1 0.508 vs xseg_1+xseg_2 0.507, +90 ms | `xseg_1` |
| Identity boost | 0 / 0.5 / 1.0 -> identity 0.508 / 0.516 / 0.515, leak 0.355 / 0.293 / 0.244 | 0.5 (1.0 alters face shape by eye) |

Net vs the morning's pipeline (inswapper + CodeFormer): identity 0.421 -> 0.516, leak 0.366 -> 0.293, ~2.4 fps end to end at 1080p.
Also: identity builder (D) shipped; feather-mask seam at the crop border fixed (the old failing test). DFL track (E video) built but paused - see memory/notes: training crash (io patch not picklable) and an unexplained deletion of the copied source photos in the DFL workspace must be resolved first.

## 1. Measure first: `eval_reface.py` (Phase C)

Every later choice (swapper, restorer, identity recipe) is decided by numbers from one harness, the way `compare_lora_identity.py` / `eval_grouping.py` already work.

- Inputs: a person with held-out real photos (gallery person), N target stills, 2-3 short target clips.
- Identity score: cosine similarity of the swapped face to the held-out mean, measured with an **independent** recogniser (e.g. antelopev2 `glintr100`), not buffalo_l's w600k that inswapper/HyperSwap are steered by.
- Quality: sharpness inside the face (Laplacian variance vs the target's own), a no-reference IQA if one fits, and a side-by-side PNG grid for the eye.
- Video stability: frame-to-frame variance of the output embedding and landmark jitter.
- Speed: ms per frame.
- Output: JSON + grid under `reface_output/eval/`.

## 2. Identity builder — "make a model of me" (Phase D)

Today `RefaceEngine.build_faceset_from_media` takes `faces[0]` of every image/frame (highest detector score — in a group photo or a video with other people that is often someone else), weights by `det_score` only, never rejects outliers, and saves full frames for video. Replace it with an **Identity** built like the gallery already builds people:

1. Sources: uploaded photos/videos, **a Gallery person** (already curated, embeddings + quality v2 stored), LoRA portraits (existing `lora_identity.py`).
2. Pick the right face: in each image take the face that matches the identity (seed = the dominant cluster or a chosen photo), not `faces[0]`.
3. Filter: `face_quality` v2 gate, minimum size, near-duplicate removal (cos >= 0.95, as on the phone), outlier rejection against the robust mean.
4. Video sampling for pose diversity (bucket by yaw/pitch, keep the sharpest per bucket) instead of every 1/3 s.
5. Report: count, pose coverage, identity consistency, and the photos that hurt (lowest similarity) so the user can drop them.
6. Format: `identities/<slug>/manifest.json` + `embeddings.npy` + aligned 512 crops (no pickle). Old `.pkl` facesets stay readable.
7. Identity vector: robust quality-weighted mean. A/B in the harness: pose-bucket vectors, and FaceFusion-style "identity strength" (push the source away from the target's own embedding, coefficient up to ±0.35).

## 3. Better models (Phase E)

Sizes checked 2026-10-14 against `facefusion/facefusion-assets` releases; all under the 500 MB auto-download limit.

| Model | Role | Size | Notes |
|---|---|---|---|
| HyperSwap 1b / 1c 256 | swapper, 4x the pixels of inswapper_128 | 403 MB each | arcface_128 template, input [-1,1], source = normed ArcFace embedding (same as ours). Plugs into the compositor unchanged (it takes the swapper's affine) |
| GPEN-BFR 512 / 1024 | restorer | 284 / 285 MB | |
| GFPGAN 1.4 | restorer | 340 MB | |
| RestoreFormer++ | restorer | 294 MB | |
| XSeg 2 | occluder | 70 MB | `models-3.1.0` |

Default swapper and restorer are whichever wins in the harness (identity first, then sharpness, then stability). `inswapper-512-live` (InsightFace) would be ideal but its weights are not published (apps only).

Per-identity trained models:
- **Stills — LoRA refine pass**: after the swap, re-render the face region with SD1.5 inpaint + the person's Character LoRA (+ IP-Adapter) at low denoise, in `venv_ai` as a job. The infrastructure exists (undress worker, LoRA training/generation). Biggest expected gain for photos.
- **Video — DeepFaceLab (optional, heavy)**: export the Identity as a DFL src faceset (`dfl_metadata.py`), train SAEHD/AMP at a resolution that fits 6 GB, export `.dfm`, auto-register in V3 (the DFM path already composites through the same core but has never run on a real `.dfm`). Days of GPU time per person.
- Out of reach on 6 GB: Flux / Qwen-Image-Edit native reconstruction (12-24 GB).

## 4. Using it (Phase F)

Pick an Identity, and the engine picks the best available method: DFM if trained (video), else the harness-chosen swapper + restorer, plus the LoRA refine pass for stills. One quality/speed preset instead of today's mixed V2/V3 controls.

## Order

C (harness) -> D (identity builder) -> E1 (HyperSwap + restorers, chosen by C) -> E stills (LoRA refine) -> F -> E video (DFL, if wanted).
