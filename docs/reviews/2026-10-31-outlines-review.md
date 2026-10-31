# Review: exact face & body outlines (Antigravity, 2026-10-31)

Scope: commits bbfba09..a0687b7 against `docs/plans/2026-10-31-exact-face-body-outlines-plan.md`.
Read-only review; no code was changed.

Run by the reviewer (CPU, no GPU): `test_outlines`, `test_analysis` 8/8, `test_mobile_scan_worker`
(OK, incl. outline transport), `test_mobile_api_contract` 31/31, `test_mobile_stateless` 5/5,
`test_mobile_video` 18/18, `validate_contract.py`: all pass.
Not run by the reviewer (the user runs them): `flutter analyze`, `flutter test`, the GPU check
(`test_mobile_scan_gpu.py`) and on-phone acceptance. The 597 Flutter tests and GPU timings in the
handoff are Antigravity's own numbers.

## Findings (most severe first)

### 1. HIGH (privacy): debug photos of a real person are pushed to a public repository
`docs/reviews/outlines-2026-10-31/{portrait,full_body,group}.png` were committed in 7c60fd4 and
pushed. `origin` (`elmohamadyhmsdc/antigravity-local`) is **PUBLIC**. Two of the images show an
identifiable real person (one a revealing outfit photo). The repository is a face-swap/undress
tool, so this is a real privacy problem. The plan said to keep the debug PNGs local.
**Fix:** `git rm` the folder and ignore `docs/reviews/*/` images. Removing them from history
needs a history rewrite and force push, which is the user's decision.

### 2. MEDIUM: backfill can align a face with keypoints from a different photo
`outline_backfill.dart` sends `faces.kps` for every face detection. But a detection can point at
a face record first stored from **another** photo: dedupe link (cosine ≥ 0.95), video-track
link/replace, rescan. `_refreshLinkedFace` updates quality, not `kps`/`media_id`. The server then
warps the 512 crop around the other photo's face position and parses the wrong area. The
resulting outline is saved, so `outline IS NULL` never retries it.
Impact today is small: backfill only touches photos scanned before outlines existed.
**Fix:** send `kps` only when `faces.media_id == detection.media_id` (and the frame matches);
otherwise omit them (server uses the bbox path). Also make the server ignore kps that fall
outside the target bbox.

### 3. MEDIUM-LOW: outlines shift on faces/bodies cut by the photo edge
The scan path stores the box as `clampBox(normalized bbox)` but encodes the outline relative to
the **unclamped** `face.bbox` / `body.bbox`. InsightFace boxes often extend past the image edge,
so edge faces draw a shifted/squeezed outline. Backfill already encodes against the stored box.
**Fix:** encode against the clamped box converted back to pixels (`box.x * w`, …).

### 4. LOW (visual): body outlines go flat where the body crop ends
Body crops are padded only 6 % / 4 %. RMBG fills to the crop edge, so the polygon follows the
crop rectangle: hair is cut by a flat line on both portraits, and in the group photo a partly
covered body becomes a rectangle. Face outlines look good (skin only, ears included, hair excluded
by design).
**Fix:** a larger top pad (about 15 %, at least up to above the face box). Optionally, don't
trust mask edges that touch a crop side which isn't the image edge.

### 5. LOW: backfill sends no body keypoints
`bodies.kpts` is stored but not sent, so backfilled bodies in crowded photos lose the skeleton
preference that picks the right person. **Fix:** send `kpts` (same media-id check as #2).

### 6. INFO (scan time): video frames now compute outlines on every sampled frame
Outlines run on all bodies of each sampled frame, including ones the phone later drops.
Handoff timing: body ~170–237 ms + face ~18 ms each. This adds noticeably to a multi-hour first
scan. Acceptable, but expect it.

## What is fine
- Server: `return_outlines` defaults to false, so responses without it are unchanged (contract
  fixtures validate). Worker IPC carries outlines, and the worker recovers after a crash.
  `/v1/analyze/outlines` validates targets (≤ 32), size limits, GPU guard and the error envelope.
  `mobile_api` is still stateless.
- RMBG preprocessing in `outlines.py` matches the corrected one (RGB, x/255 − 0.5, min-max, 0.5).
- Phone: schema v13 uses `addMissing` (idempotent). `decodeOutline`/`_parseOutline` reject
  malformed data without throwing. Catmull-Rom smoothing; the old template silhouette is gone;
  remaining `BoxShape.circle` uses are avatars, not detection overlays. The phone sends
  `return_outlines` for photos **and** videos. Backfill skips videos, is debounced per session
  and fails silently.
- None of the files from the model-fix commit (a2e196c) were modified.
