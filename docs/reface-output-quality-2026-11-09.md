# Reface output quality — 2026-11-09

The user requested clearer Reface output after the video identity-leakage fixes.
The change preserves more of the swapped/restored face's detail before encoding.
It does not change the chosen source identity or introduce new model weights.

## Changes

- `face_compositor.py` now composes the swapper and FFHQ alignment matrices and
  resamples the swapped crop once with cubic interpolation. Previously it pasted
  into a frame-sized raster and recropped that raster, losing detail before the
  restorer saw it. The legacy placement remains available for diagnostics.
- Focus matching has an independent strength. Public Fast retains the previous
  full matching, Balanced uses half strength, and Most detail uses one quarter.
  This keeps some adaptation to the scene's focus without blurring the restored
  face all the way back to the original face's sharpness. Explicit constructor
  overrides remain supported; caller-owned option dictionaries are copied.
- The video leakage fixes remain active: current-frame visibility masks, swapped
  video mouth, and independently regenerated grain instead of original facial
  detail. Parser/occluder protection and feathered boundaries remain in use.
- The public pipeline selects H.264 encoding settings by quality profile:

| Profile | CRF | Encoder preset | Focus matching strength |
|---|---:|---|---:|
| Fast | 16 | medium | 1.0 |
| Balanced | 14 | medium | 0.5 |
| Most detail | 12 | slow | 0.25 |

All profiles previously encoded at CRF 16/medium. Direct legacy V3 defaults to
CRF 14/medium. Actual video encoder settings accompany video result diagnostics,
including the existing OpenCV fallback when FFmpeg cannot launch. Photos remain
PNG. Video dimensions, fractional frame rates, stream-copy joining and original
audio muxing keep their existing behavior. Most detail takes more processing work
and the reduced compression can increase file size.

## Measured comparison

The local experiment used four existing identities, up to twelve real build
photos and six held-out photos per identity, and twelve consecutive frames from
each of two existing DeepFaceLab sample clips: eight person/clip pairs and 96
rendered frames per configuration. Near-duplicate photo groups were split before
selecting the build and held-out subsets. Identity was scored with the independent
`glintr100` recognizer, rather than the swapper's conditioning recognizer.

| Balanced | Identity similarity | Original identity similarity | Sharpness ratio | Frame-change ratio |
|---|---:|---:|---:|---:|
| Before | 0.5608 | 0.1816 | 0.8082 | 0.9877 |
| After | 0.5606 | 0.1830 | 1.1956 | 1.0062 |

The sharpness measure increased about 48%, while mean identity similarity stayed
close to the baseline. Score coverage was 100%, with no reported failed, skipped
or degraded faces in either configuration. The two sharpness values are ratios
to the original frame; they do not mean 48% more true resolution or a universal
perceptual improvement. The frame-change ratio is near the original video's 1.0;
the former stronger blur also reduced frame changes. A face comparison sheet was
visually inspected.

The initial combined GPU evaluation approached the 6 GB card's memory limit with
the independent judge and GPEN 1024 loaded together. Its remaining Most detail
evaluation was stopped; the completed Balanced result was retained. Sequential
timings under this pressure are not used as production speed claims.

Most detail was then compared separately with the same four identities and two
clips, six consecutive frames per clip (48 frames/configuration). The independent
judge used CPU so GPEN 1024 could use the GPU without competing with that judge.
Both sides of this second comparison used the same CPU judge and frame subset:

| Most detail | Identity similarity | Original identity similarity | Sharpness ratio | Frame-change ratio |
|---|---:|---:|---:|---:|
| Before | 0.5743 | 0.1811 | 0.8622 | 0.9755 |
| After | 0.5731 | 0.1803 | 1.3101 | 1.0003 |

This is about a 52% increase in the sharpness measure, with identity similarity
close to the paired baseline. Coverage was 100% with no reported face failures,
skips or degradation. The before/after face sheet was visually inspected. These
figures should not be compared directly with the Balanced table, which uses a
different frame subset and GPU judging.

Experiment script and reports are under
`the app/build/reface-quality-2026-11-09/`: `evaluate_quality.py`, `report.json`,
`report-final.json`, `comparison.png`, and `comparison-final.png`. These are local
build artifacts. The script's legacy placement function reproduces the previous
two-resample path for paired comparisons.
The completed Most detail comparison is in `report-detail.json` and
`comparison-detail.png`; reproduce it with `--detail-only`.

## Verification and limits

- 114 focused automated checks passed: compositor 56, quality 29, video continuity
  8, unified pipeline 10, desktop adapters/UI/workers 11.
- New checks cover detail preservation through alignment, graduated focus
  matching, explicit override precedence, invalid encoder inputs, and decoded
  pixel error across actual H.264 profiles while preserving dimensions/frame rate.
- Real CUDA image/video acceptance passed separately for Balanced and Most detail.
  Each swapped exactly one selected face in a lossless photo while preserving the
  unselected person/background byte-for-byte, then stopped at three video frames,
  resumed for six and joined exactly nine frames at 29.97002997 fps. Video result
  diagnostics confirmed CRF 14/medium/focus 0.5 for Balanced and CRF 12/slow/focus
  0.25 for Most detail. Reports are `gpu-balanced/gpu-report.json` and
  `gpu-detail/gpu-report.json` in the same local build artifact folder.
- `git diff --check` passed. Evaluation processes have exited; only the identified
  evaluation process was stopped during the memory-pressure experiment.
- The samples cover a small set of identities and short early-clip motion. Photo
  groups are not labelled independent capture sessions. This is provisional
  calibration, not broad acceptance of long clips, profiles or heavy occlusions.
- The user's reported video has not been provided. The running PC server and
  phone were not redeployed or restarted; the server must reload these changes
  before rendering a fresh preview. No packages, CUDA setup, models, real library
  records or existing jobs/checkpoints were changed.
