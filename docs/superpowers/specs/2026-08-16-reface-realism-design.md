# Reface Realism — Phase 1: Compositing Core

**Date:** 2026-08-16
**Status:** Approved design, ready for implementation planning
**Scope:** `the app/` — the HD reface path (`reface_engine_v3.py` and friends)

## Problem

The V3 reface output reads as fake. The user named six symptoms:

1. A hand passing in front of the face gets destroyed
2. An open mouth gets destroyed
3. Soft face with a visible seam against a sharper frame
4. Plastic, poreless "AI" skin
5. Lighting and colour that do not match the scene
6. Flicker and wobble in video

Five of the six trace back to how the current pipeline composites, not to the swap model.

### Root causes, confirmed in source

**Double paste.** `_process_face` (`reface_engine_v3.py:165`) calls
`self.swapper.get(..., paste_back=True)`. Inside insightface
(`insightface/model_zoo/inswapper.py:68-102`), that path builds its paste mask from
`img_white` — a solid rectangle covering the entire arcface crop, eroded by
`mask_size // 10` and Gaussian-blurred. It has no concept of occlusion, so it paints
the swapped face over any hand, microphone or hair in front of the face.

The HD-restored layer is then blended *on top of that already-swapped frame*
(`reface_engine_v3.py:203`). The occluder mask therefore only protects the hand from
the restored layer, never from the base swap underneath. **Occlusion protection is
effectively not wired up.** The same structure produces the soft halo: wherever the
mask feathers toward zero, the blend falls back to insightface's blurry 128px paste
instead of the untouched original frame.

**Damaged restorer input.** The aligned crop fed to CodeFormer is produced by warping
the *already pasted* full frame (`reface_engine_v3.py:178`), so it is a
128 → full-frame → 512 double resample. The restorer hallucinates on top of
resampling mush.

**Wrong mask geometry.** `feather=0.08` of a 512 crop is a 41px Gaussian applied to a
binary mask. Any hole the occluder does cut gets smeared into a translucent ghost.
The occluder output is also used raw, without the threshold-and-remap step that makes
it usable as a hard matte.

**Teeth get replaced.** `DEFAULT_REGIONS` (`face_masking.py:55`) includes class 11,
the inner mouth. A 128px swap contains roughly 30 real pixels of teeth, which
CodeFormer then reconstructs into a smear.

**No texture, focus or noise matching.** CodeFormer output is perfectly clean.
Real footage has sensor noise, compression artefacts and finite focus. A noise-free,
razor-sharp face composited into a grainy or soft frame floats on top of it.

**Colour match ignores light direction.** `_color_match` transfers LAB mean and
standard deviation globally, so a face lit from the left keeps the source's shading.

**Everything is per-frame.** Restoration and colour statistics are recomputed each
frame with no temporal coupling, which shimmers.

**Audio is discarded.** The encoder passes `-an` (`reface_engine_v3.py:423`), so every
refaced video comes out silent.

## Goals

- A hand, microphone or other occluder in front of the face survives untouched
- The target's real teeth and inner mouth survive
- No pixel outside the parser's face region is modified
- Face grain, focus and lighting match the surrounding frame
- Video is temporally stable: no shimmer in texture, tone or mask boundary
- Output video keeps its audio
- Today's behaviour remains reproducible for A/B comparison

## Non-goals

- Changing V1 (`reface_engine.py`) or V2 (`reface_engine_v2.py`)
- Replacing the swap model — that is phase 2
- DeepFaceLab training — that is phase 3
- Diffusion backends, cloud or mobile inference, and C2PA provenance. `the app/enhace.md`
  discusses these at length; they target a hosted product, not a 6 GB laptop, and are
  explicitly out of scope

## Phasing

This spec covers **phase 1 only**. Agreed sequence:

| Phase | Work | Why this order |
|---|---|---|
| **1** | Compositing core rebuild (this spec) | Fixes 5 of 6 symptoms with models already on disk |
| **2** | 256px swapper behind the same interface | Raises the resolution ceiling; needs phase 1's realism core to be worth anything |
| **3** | Per-person DeepFaceLab / DFM training | Highest quality ceiling, days of GPU time per person on the available hardware |

Reference hardware: RTX 4050 Laptop, 6 GB VRAM (`lora_trainer.py:22`).
`DeepFaceLab_NVIDIA_RTX3000_series/workspace/model/` is currently empty; the
`RTM WF faceset/aligned` set is the dst side only. Phase 3 starts from nothing trained.

## Architecture

One new module, `the app/face_compositor.py`, owns everything after the swap:
align → restore → mask → harmonize → paste, plus per-track temporal state.

```python
@dataclass
class CompositeConfig:
    restore_size: int = 512
    preserve_mouth_interior: bool = True
    mask_erode: float = 0.02        # fraction of crop size
    mask_feather: float = 0.05      # fraction of crop size, distance-transform ramp
    relight: float = 1.0            # 0..1
    detail_transfer: float = 0.4    # 0..1, scaled again by native face size
    grain_match: float = 1.0        # 0..1
    focus_match: bool = True
    blend: float = 1.0
    temporal: bool = False
    temporal_alpha: float = 0.5     # gain map and mask
    temporal_alpha_slow: float = 0.3  # noise sigma and focus radius

class FaceCompositor:
    def __init__(self, restorer: FaceRestorer, masker: FaceMasker, config: CompositeConfig)
    def reset(self) -> None
    def composite(self, frame, aligned_swap, M_swap, kps, track_id=0) -> np.ndarray
```

`M_swap` is the 2×3 affine mapping the frame into whatever crop space the swapper
produced. This single parameter is what makes the module swapper-agnostic:

- inswapper passes the arcface-128 matrix from `get(..., paste_back=False)`
- the DFM path passes its `align_face` matrix
- phase 2's 256px model passes its own template matrix

All three then share one realism core instead of each carrying a copy.

`RefaceEngineV3` becomes an orchestrator: detect → smooth → swap → `composite()`.
`dashboard.py` and `job_manager.py` keep constructing `RefaceEngineV3`, so no UI rewiring
beyond the new options.

**Prerequisite change:** `_smooth` (`reface_engine_v3.py:254`) matches faces to tracks
but discards which track matched. It must return stable track ids so the compositor can
key its temporal state.

## Pipeline

### 1. Alignment

inswapper's arcface-128 template frames tighter than the FFHQ-512 template CodeFormer
expects. Feeding the arcface framing to the restorer degrades it. Instead:

- `M_ffhq` = similarity transform from the 5-point landmarks to `FFHQ_512`
  (existing `_alignment_matrix`)
- `T = M_ffhq · M_swap⁻¹`, composed in homogeneous 3×3 form, then back to 2×3
- Warp `aligned_swap` into FFHQ space once via `T`. One resample, no round trip
  through the full frame
- Warp a ones-image by the same `T` to get coverage. The arcface crop does not reach
  the forehead, so pixels with coverage below 0.5 are filled from `orig_aligned`
  (the original frame warped by `M_ffhq`), with a short ramp at the coverage edge

The restorer then receives a complete, correctly framed 512 face.

### 2. Restore

`restorer.enhance(base)` as today. Unchanged, apart from receiving better input.

### 3. Mask

Computed in crop space at `restore_size`:

- `region_restored` = parser region of the restored crop
- `region_orig` = parser region of `orig_aligned`
- `region = region_restored * region_orig` — never paint where the real frame was not
  face. `region_orig` is needed anyway for the skin-restricted detail transfer and the
  noise annulus, so the second parser pass is not wasted work
- Regions exclude hair, glasses, hat, neck and ears, as today. Class 11 (inner mouth) is
  removed from the default set when `preserve_mouth_interior`
- `occ` = occluder on `orig_aligned`, hardened as
  `clip(GaussianBlur(occ, sigma=5), 0.5, 1) * 2 - 1`, matching facefusion. This turns a
  soft probability field into a usable matte instead of a smear
- Erode `region` by `mask_erode * restore_size`
- Feather with a distance transform: `ramp = clip(distanceTransform(binary) / feather_px, 0, 1)`.
  This gives a uniform-width edge; a Gaussian on a binary mask does not
- `mask = ramp * occ`, minus the inner-mouth hole (its own short ramp) when
  `preserve_mouth_interior`
- Final 1–2px Gaussian to remove staircase artefacts

### 4. Harmonize

All in crop space. `native_px` = target face bbox height in original frame pixels.

**Relight.** Masked low-frequency gain, per channel:

```
lo(x) = blur(x * mask, sigma=restore_size/16) / (blur(mask, sigma=restore_size/16) + 1e-6)
gain  = clip((lo(orig_aligned) + 4) / (lo(result) + 4), 0.7, 1.4)
result = result * lerp(1, gain, config.relight)
```

Pixel values are on a 0–255 scale, so the `+ 4` is a floor that keeps the ratio stable in
near-black regions. The masked blur keeps background pixels from contaminating the
estimate, and the clip prevents blowups. This follows light direction and white balance,
which the current global mean/std transfer cannot. When the mask area falls below the
floor, fall back to the existing LAB mean/std transfer.

**Focus match.** Compare Laplacian variance of `result` and `orig_aligned` inside the
eroded mask. If the result is sharper, pick the smallest sigma from
`{0.5, 0.8, 1.2, 1.8, 2.6}` whose blurred variance drops to or below the original's,
and apply it.

**Detail transfer.** `detail_frac = clip((native_px - 128) / (512 - 128), 0, 1)`

```
hf     = orig_aligned - GaussianBlur(orig_aligned, sigma=2)
amount = config.detail_transfer * detail_frac
result = result + amount * hf * skin_mask
```

Restricted to the skin class so eyelashes and lip lines are not doubled. The scaling is
the point: a 90px face has no real detail to borrow, so it leans on CodeFormer; a 700px
face is full of real pores, so it borrows heavily.

**Grain.** Estimate sensor/compression noise with Immerkær's estimator

```
N = [[1,-2,1],[-2,4,-2],[1,-2,1]]
sigma_n = sqrt(pi/2) / (6 * (W-2) * (H-2)) * sum(abs(gray conv N))
```

measured on an annulus between the face bbox and 1.5× the bbox, excluding
`region_orig`, so skin texture does not inflate it. Fall back to the whole crop if the
annulus is too small. Then add luma-dominant noise of that sigma, Gaussian-blurred by
0.5px to correlate it (real noise is demosaiced, not white), plus an independent chroma
component at 0.3 sigma. Scaled by `config.grain_match * (1 - detail_frac)` so grain and
detail transfer do not stack — large faces get real texture, small faces get synthetic
grain.

### 5. Paste back

Warp `result` and `mask` by `invertAffineTransform(M_ffhq)` onto the **original** frame,
never onto a pre-pasted swap:

```
out = original * (1 - mask * blend) + back * (mask * blend)
```

When the face is small in the frame, pre-downsample the crop with `INTER_AREA` to
approximately the destination size before warping, to avoid aliasing.

## Temporal layer (video)

Per-track state keyed by the track ids `_smooth` now returns:

- EMA on the gain map, the mask, the noise sigma and the focus radius. Crop space is
  normalised, so these are directly comparable across frames. `temporal_alpha` for gain
  and mask, `temporal_alpha_slow` for sigma and radius
- Grain is deliberately excluded: fresh noise every frame, only its sigma is smoothed.
  Frozen grain reads as a dirty lens, which is its own tell
- The existing landmark EMA stays as is
- `reset()` at the start of each video; tracks unseen for 30 frames are evicted

## Audio

Encode the video as today, then mux the original audio with `-c copy`. When
`start_time`/`end_time` clipping is active, trim the audio input with `-ss`/`-to` to
match. If the source has no audio stream, skip silently.

## Config surface

The V3 branch of the Reface V2 page gets a "Realism" expander with a preset selector:

| Preset | Settings |
|---|---|
| **Natural** (default) | detail 0.4, grain 1.0, relight 1.0, focus match on, teeth preserved |
| **Maximum detail** | detail 0.6, otherwise as Natural. For stills and close-ups |
| **Clean (legacy V3)** | detail 0, grain 0, relight 0 with the old LAB path, teeth swapped |

"Clean" exists to reproduce current behaviour exactly, so improvements can be verified by
comparison rather than asserted.

Individual sliders sit under an advanced toggle. Parameters thread through
`job_manager` the same way `restorer` and `restorer_weight` already do
(`job_manager.py:326-330`). Video defaults to Natural with `temporal=True`; images
default to Natural with temporal off.

## Error handling

One rule: **a realism stage may degrade the output, never fail the job.**

- Each harmonize step is individually guarded. On exception it returns the previous
  stage's result and logs **once per run**, not per frame — a per-frame warning on a
  10,000-frame video buries the log
- Missing parser, occluder or restorer degrades exactly as today: box mask, no occlusion
  subtraction, no restoration
- Mask area below the floor (0.5% of the crop) falls back to global LAB transfer and
  skips detail and grain, whose statistics are meaningless on a few hundred pixels
- Degenerate landmarks that make `M_ffhq` or `T` non-invertible: skip that face, leave
  the frame untouched, count it in the result message

## Testing

The repo has no pytest suite; tests are standalone scripts that print results and
`exit(1)` on failure. Two new scripts follow that convention.

`the app/test_compositor.py` — no GPU, no model files, synthetic arrays only:

1. **Affine round-trip** — `T = M_ffhq · M_swap⁻¹` maps known points within tolerance,
   and the inverse restores them
2. **Containment** — the final mask is 0 everywhere `region_orig` is 0
3. **Occlusion regression** — a synthetic rectangle zeroed in the occluder mask is still
   0 after hardening, erosion and feathering. This is the direct regression test for the
   destroyed-hand bug
4. **Teeth** — with `preserve_mouth_interior`, the mask is 0 across the class-11 region
5. **Noise estimator** — recovers a known sigma from synthetic Gaussian noise within
   tolerance
6. **Relight bounds** — the gain map never escapes [0.7, 1.4]
7. **Temporal** — identical consecutive frames produce identical output; a step change
   converges smoothly instead of jumping

`the app/compare_v3.py` — the script that actually settles the question. Renders one
target through the legacy path and the new one and writes a side-by-side PNG, or a
split-screen clip for video. "No one can tell it is fake" is a judgement made by eye;
the unit tests only prove the mechanics are sound.

Commands are to be posted for the user to run, per the standing rule in `CLAUDE.md`.

## Success criteria

Mechanically checkable:

- With a hand over the face, pixels inside the occluder region are bit-identical to the
  input frame
- With `preserve_mouth_interior`, inner-mouth pixels are bit-identical to the input
- No pixel outside `region_orig` differs from the input
- Estimated noise sigma of the output face is within 25% of the surrounding frame's
- Refaced video retains an audio stream when the source had one

Judged by eye, on the user's own footage, via `compare_v3.py`: Natural should beat Clean
on seam visibility, skin texture and lighting integration, in both stills and motion.

## Files affected

| File | Change |
|---|---|
| `the app/face_compositor.py` | **New** — `CompositeConfig`, `FaceCompositor` |
| `the app/reface_engine_v3.py` | `_process_face` and `_process_face_dfm` route through the compositor; `_smooth` returns track ids; `reset()` per video; audio mux |
| `the app/face_masking.py` | Occluder hardening, distance-transform feather, inner-mouth hole helper |
| `the app/dashboard.py` | Realism expander in the V3 branch |
| `the app/job_manager.py` | Thread realism params through to the engine |
| `the app/test_compositor.py` | **New** |
| `the app/compare_v3.py` | **New** |
| `the app/CLAUDE.md` | Document the new module in the module table |

## Risks and open items

- **Framing change alters the look.** Restoring a correctly framed FFHQ crop instead of a
  re-warped one will shift output relative to today, including in ways not strictly
  better on every clip. The Clean preset exists so this is measurable rather than
  argued about.
- **Second parser pass costs roughly 10 ms per face.** Accepted: `region_orig` is needed
  for detail transfer and the noise annulus regardless.
- **Phase 2 is not a drop-in.** The `M_swap` parameter handles differing alignment
  templates, but the 256px candidates (hyperswap, ghost, simswap families) each use their
  own source-embedding convention. Exact ONNX I/O must be verified per model before
  committing to one. Out of scope here, flagged so phase 1 does not assume otherwise.
- **Track ids are centroid-matched**, inherited from the existing `_smooth`. Fast cuts or
  crossing faces can swap tracks, briefly mixing temporal state. Acceptable for now;
  worth revisiting if it shows up in practice.
