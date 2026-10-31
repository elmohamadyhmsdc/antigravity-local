# Exact Face & Body Outlines: Implementation Plan

> **For Antigravity:** do the tasks in order. Every task ends with its tests passing.
> Do not commit unrelated files (see "Do not touch" below). When you finish, write a
> handoff section and tell the user, who will ask Claude for a review against the
> **Review checklist** at the end of this file.

**Goal:** wherever the phone highlights a face or a body, the line follows the real
shape of that face/body in the photo, not a box, a circle, or a drawn template.

**Problem with the 2026-10-31 attempt (why "it did nothing"):**
- `ReviewHighlightPainter.createBodySilhouettePath` (`mobile/lib/features/review/review_media_viewer.dart:453`)
  draws one hard-coded standing-person shape (fixed fractions of the box) and stretches it
  over every body. A sitting, side-on, cropped or half-body person gets a shape that is
  not theirs.
- Faces became `addOval(box)` / `BoxShape.circle`. The edge is still the detector box,
  just rounded.
- The media screen and video view still draw bodies as rounded rectangles.
- **Root cause:** no shape data exists anywhere in the pipeline. The PC sends `bbox` + 5 `kps`
  per face and `bbox` + 17 `kpts` per body. `media_detections` stores only `x, y, w, h`. The
  phone cannot draw an exact edge it was never given.

**Architecture:** the PC computes a polygon per face and per body during analysis, using
models that are **already installed locally** (no downloads):
- Face: BiSeNet face parser `the app/models/bisenet_resnet_34.onnx` (already used by
  `face_masking.FaceMasker`), run on the FFHQ-aligned crop and mapped back to the image.
- Body: RMBG-1.4 `the app/models/rmbg.onnx` (input `input [N,3,1024,1024]` float, output
  `output [N,1,1024,1024]` sigmoid), run on the padded body crop.

Mask → largest relevant contour → simplified polygon (≤ 64 points) → JSON as an optional
`outline` field on `Face` / `Body`. The phone stores it in a new nullable column
`media_detections.outline` (box-relative coordinates), and every overlay draws it through
**one** shared path helper. When there is no outline, faces fall back to an oval and
bodies to a plain rounded rectangle. The fake silhouette is deleted.

**Tech:** Python 3.13 `venv` (onnxruntime-gpu, OpenCV, NumPy), FastAPI `mobile_api`,
Flutter/Dart, Drift (SQLCipher).

---

## Constraints (read before starting)

- **No downloads, no package installs, no Python/CUDA changes.** Both models are already on
  disk. If one is missing at runtime, outlines for that kind are `null`; never fetch.
- **Do not touch** the user's uncommitted work: `the app/lora_dataset.py`,
  `the app/mobile_api/model_readiness.py`, `the app/reface.py`, `the app/reface_engine_v3.py`,
  `the app/undress_core.py`, `the app/download_upgrades.py`, `the app/test_florence_load.py`.
  `docs/ANTIGRAVITY_HANDOFF.md` also has uncommitted edits: append your section, don't rewrite it.
  Commit only files this plan names.
- `mobile_api` stays stateless: no `database` import, nothing under `data/`
  (`test_mobile_stateless.py` must still pass).
- Backward compatible both ways: an old phone (no `return_outlines`) costs the server nothing
  extra, and a new phone talking to an old server gets `outline == null` and still scans.
- The analyzer stays at zero issues (`flutter analyze`, infos included).
- Run commands per the repo rule in `CLAUDE.md` (post them for the user, or run them if the
  user has told you to).
- Out of scope: Streamlit `gallery_page.py`, character (anime) detections, people avatars
  (`people_screen.dart` circles are avatars, not overlays).

## Data format (single source of truth, used by every task)

**Wire (`openapi.yaml`)**: `outline` is optional and nullable on `Face` and `Body`:
an array of 3–64 `[x, y]` points in **image pixel coordinates** (same space as `bbox`/`kps`),
ordered around the shape (either direction), not closed (last ≠ first), rounded to 1 decimal.

**Phone storage (`media_detections.outline`, TEXT NULL)**: compact JSON of a flat list
`[x0,y0,x1,y1,...]` in **box-relative** coordinates, `x_rel = (x_px - bbox.x) / bbox.w`,
`y_rel = (y_px - bbox.y) / bbox.h`, rounded to 3 decimals and clamped to `[-0.25, 1.25]`
(an arm or hair may stick out of the detector box a little). Box-relative means the outline
lines up with the stored box in every view, at any display size, with no image size needed.

---

### Task 1: Python outline module (`the app/outlines.py`), CPU-tested

**Files**
- Create: `the app/outlines.py`
- Create: `the app/test_outlines.py`

**Pure helpers (no models, CPU, unit-tested):**
1. `mask_to_polygon(mask: np.ndarray, *, max_points=64, min_area_frac=0.01, prefer=None) -> Optional[np.ndarray]`
   - `mask` is uint8/bool at crop resolution. Morphological open then close (kernel ≈ 1% of the
     shorter side, at least 3 px) to drop specks and fill pin holes.
   - `cv2.findContours(RETR_EXTERNAL, CHAIN_APPROX_NONE)`. Drop contours below
     `min_area_frac` of the mask area.
   - Choose the contour: if `prefer` (a uint8 mask of the same size) is given, the contour
     whose filled area overlaps `prefer` most; otherwise the largest.
   - Simplify with `cv2.approxPolyDP`, starting at `epsilon = 0.003 * perimeter` and
     multiplying by 1.5 until `len <= max_points`. Return `None` if fewer than 3 points remain.
   - Returns `(K, 2)` float32 in crop pixels.
2. `to_image_coords(poly, crop_origin_xy, scale)` and `apply_affine(poly, inv_2x3)`: map a
   crop polygon back to image pixels.
3. `skeleton_mask(kpts, kpt_scores, shape, origin_xy, min_score=0.3)`: draw the COCO limbs
   (the usual 16 pairs) as thick lines (≈ 4% of the box height) plus filled circles at
   visible joints, in crop coordinates. Used as `prefer` for bodies so the chosen component
   is *this* person, not a neighbour that RMBG also kept.
4. `encode_outline(poly) -> list[[x, y]]`: rounding to 1 decimal, as the wire format.

**Model-backed class:**
5. `OutlineEngine(models_dir=MODELS_DIR, providers=None)`
   - Lazily loads `bisenet_resnet_34.onnx` through `face_masking.FaceMasker(load_occluder=False)`
     (reuse it; do not copy its preprocessing) and `rmbg.onnx` with its own
     `onnxruntime.InferenceSession` (CUDA then CPU providers; `cuda_dll_dirs.add_nvidia_dll_dirs()`
     first, as `face_masking.py` does). Missing file or load error → that kind returns `None`,
     logged once, never raised.
   - `face_outline(img, face) -> Optional[np.ndarray]`:
     - `M = face_compositor.alignment_matrix(face.kps, 512)`; `crop = cv2.warpAffine(img, M, (512, 512))`.
       If `kps` is missing or `M` is None, use the face box padded 30% instead.
     - `seg = masker.segment(crop)`; face mask = classes skin, both brows, both eyes, nose, mouth,
       upper/lower lip, both ears, glasses (`face_masking.REGIONS`). Exclude hair, hat, neck and
       cloth: the outline is the face itself, not the head.
     - `mask_to_polygon` → map back with `cv2.invertAffineTransform(M)`.
   - `body_outlines(img, bodies) -> List[Optional[np.ndarray]]`:
     - Per body: crop the box padded 6% horizontally / 4% vertically (same as
       `analysis.body_crop`, but no resize), clipped to the image.
     - Preprocess for RMBG-1.4: BGR→RGB, resize to 1024×1024 bilinear, `/255`, subtract 0.5
       (std 1.0), NCHW float32. **Batch** all bodies of the frame in one `run` (cap the batch at
       8; the input's batch axis is dynamic).
     - Output: take `[i, 0]`, min-max normalise to 0..1, resize back to the crop size, threshold
       at 0.5.
     - `prefer = skeleton_mask(...)` when keypoints exist; `mask_to_polygon(..., prefer=prefer)`;
       map back to image pixels.
   - `compute(img, result: FrameAnalysis) -> (face_outlines, body_outlines)`: faces with
     `passes_gate` only (others get `None`; the phone does not store them), every body.
     Record the elapsed time in `result.timings_ms["outline"]`.

**Tests (`test_outlines.py`, standalone script that exits 1 on failure, like the others):**
- A filled circle mask → polygon with 8–64 points whose area is within 3% of the circle.
- A noisy mask with specks → specks ignored; holes don't create inner contours.
- Two blobs + `prefer` overlapping the smaller one → the smaller one is chosen.
- A very detailed contour → `max_points` respected.
- Empty / tiny mask → `None`.
- Affine round trip: polygon warped by `M` and back by its inverse matches within 0.5 px.
- `OutlineEngine` with both model paths missing → `compute` returns all `None`, no exception.
- `OutlineEngine` with a fake parser/RMBG session (inject callables) → outlines in image
  coordinates and inside the image bounds (± padding).

**Commit:** `feat(outlines): mask-to-polygon core and OutlineEngine over local BiSeNet + RMBG`

---

### Task 2: Wire outlines through analysis, the scan worker and the API response

**Files**
- Modify: `the app/analysis.py`
- Modify: `the app/mobile_api/engines.py`
- Modify: `the app/mobile_api/scan_worker.py`
- Modify: `the app/mobile_api/schemas.py`
- Modify: `the app/mobile_api/routes_analyze.py`
- Modify: `the app/mobile_api/video_jobs.py`
- Modify: `the app/test_analysis.py`, `the app/test_mobile_scan_worker.py`,
  `the app/test_mobile_api_contract.py`, `the app/test_mobile_video.py` (add cases)

**Steps**
1. `analysis.AnalyzeOptions`: add `outlines: bool = False` (default off, so
   `library_scanner.py` and the desktop gallery are unaffected).
   `FrameAnalysis`: add `face_outlines: list = field(default_factory=list)` and
   `body_outlines: list = field(default_factory=list)`. `analyze_frame` does **not** compute
   them (keeps it model-free and fake-testable).
2. `InsightEngines` (`engines.py`): hold a lazily created `OutlineEngine`. In the direct
   (non-worker) branch of `analyze()`, after `analyze_frame`, if `options.outlines` fill
   `result.face_outlines` / `result.body_outlines` via `OutlineEngine.compute`. Release it in
   `unload()`. Because the worker process runs `InsightEngines(isolate_scans=False)`, this
   covers both paths. Load must refuse downloads like the rest (`allow_downloads=False` spirit).
3. `scan_worker.encode_result` / `decode_result`: **carry the two new fields across the pipe**
   (lists of `None` or `[[x, y], ...]`). Today these functions copy a fixed set of fields; if you
   skip this, outlines are computed in the worker and silently dropped in the API process.
   `AnalyzeOptions(**request['options'])` already forwards `outlines` because it is a dataclass
   field.
4. `schemas.AnalyzeRequestOptions`: add `return_outlines: bool = False`; `parse_analyze_options`
   reads it with `_flag(opts, "return_outlines", False)`.
   `routes_analyze.py` and `video_jobs.py`: pass `outlines=opts.return_outlines` when building
   the `analysis.AnalyzeOptions` for the engine. (For video, read the same flag from the job's
   analyze params.)
5. `face_json` / `body_json`: add `"outline": encode_outline(poly) if poly is not None else None`
   when `return_outlines` is on; omit the key entirely when off (old phones see no change).
   Pass the per-index outline from `analysis_to_response` (`result.face_outlines[i]` when the
   list is long enough, else `None`).
6. Tests:
   - `test_analysis.py`: `analyze_frame` leaves both outline lists empty.
   - `test_mobile_scan_worker.py`: `encode_result` → JSON → `decode_result` preserves outlines,
     including `None` entries.
   - `test_mobile_api_contract.py` (fake engines): with `return_outlines: true` every face/body
     has an `outline` key (list or null) that matches the schema; without it, no `outline` key.
   - `test_mobile_video.py`: a video job with `return_outlines` produces frame lines with outlines.
   - The fake engines in `mobile_api/testing.py` produce a simple 8-point outline (an octagon
     inside the box) when `options.outlines` is on.

**Commit:** `feat(mobile_api): return_outlines option carries face/body polygons to the phone`

---

### Task 3: Contract + golden fixtures

**Files**
- Modify: `the app/mobile_api/contract/openapi.yaml`
- Modify: `the app/mobile_api/contract/make_fixtures.py`
- Regenerated: `the app/mobile_api/contract/fixtures/*.json`

**Steps**
1. `AnalyzeImageOptions`: add `return_outlines: { type: boolean, default: false }` with a
   description ("ask for face/body polygons; costs one parser pass per stored face and one
   RMBG pass per body").
2. `Face` and `Body`: add (not required)
   ```yaml
   outline:
     description: Polygon around the real face/body shape, image pixels, 3-64 [x, y] points, not closed. Null when unavailable.
     oneOf:
       - { type: array, minItems: 3, maxItems: 64, items: { type: array, minItems: 2, maxItems: 2, items: { type: number } } }
       - { type: "null" }
   ```
3. `AnalyzeVideoParams`: add the same `return_outlines` flag.
4. `make_fixtures.py`: in `AnalyzeImageResponse.two_faces_one_body` give face 0 a ~12-point
   outline inside its box, face 1 `outline: null`, and the body a ~20-point outline. Keep
   `no_faces` and `character_no_face` without the key (proves "absent" stays valid).
5. Regenerate and validate:
   ```
   venv\Scripts\python mobile_api\contract\make_fixtures.py
   venv\Scripts\python mobile_api\contract\validate_contract.py
   ```
   Running `make_fixtures.py` twice must give byte-identical files.

**Commit:** `feat(contract): optional outline on Face/Body and return_outlines option`

---

### Task 4: Real-GPU check and a visual debug script (evidence for the review)

**Files**
- Create: `the app/debug_outlines.py`
- Modify: `the app/test_mobile_scan_gpu.py`

**Steps**
1. `debug_outlines.py <photo> <out.png>`: loads `InsightEngines(isolate_scans=False)`, runs
   `analyze` with `outlines=True`, draws each face outline (amber) and body outline (cyan) as
   anti-aliased polylines on the photo, plus the detector box in thin grey for comparison, and
   prints per-detection point counts and the `outline` timing. Read-only; writes only `<out.png>`.
2. `test_mobile_scan_gpu.py --source <photo>`: also request outlines and assert every stored
   face (passes gate) and every body has a non-null outline with ≥ 8 points lying within the
   image; print the outline ms.
3. Run it on at least three local photos: one close-up portrait, one full-body standing
   person, one group photo with overlapping people (bodies touching). Save the three PNGs under
   `docs/reviews/outlines-2026-10-31/` (small JPEG/PNG, ≤ 1 MB each; do not commit originals
   that show private photos unless the user agrees: ask first, otherwise keep them local and
   mention their path).
4. Record GPU ms per face/body. Acceptance: outline adds ≤ 25 ms per stored face and
   ≤ 120 ms per body on this PC. If RMBG is slower, the model's spatial input is fixed at
   1024: do not resize the input. Keep 1024, report the measured number, and leave the
   speed decision to the user.

**Commit:** `test(outlines): GPU acceptance check and visual debug script`

---

### Task 5: Phone DTO, request flag, shared outline geometry

**Files**
- Modify: `mobile/lib/data/api/dtos/analyze.dart`
- Create: `mobile/lib/domain/geometry/outline.dart`
- Create: `mobile/test/domain/outline_test.dart`
- Modify: the existing DTO/contract tests (`mobile/test/.../contract_fixtures_test.dart`)

**Steps**
1. `DetectedFace` / `DetectedBody`: add `final List<Offset>? outline;` (image pixels).
   Parse leniently: missing, null, fewer than 3 points, more than 64, a non-pair, or a
   non-finite number → `null` (a bad outline must never fail a scan). Do not throw.
2. `AnalyzeImageOptions.toJson` (line ~324): send `'return_outlines': true`. The video
   scan's analyze params get the same flag.
3. `outline.dart` (pure Dart, `dart:ui` only):
   - `String? encodeOutline(List<Offset>? px, BBox box)` → box-relative flat JSON as in
     "Data format" (3 decimals, clamp `[-0.25, 1.25]`); `null` for null/empty or zero-size box.
   - `List<Offset>? decodeOutline(String? text)` → box-relative points; `null` on anything
     malformed (never throw: old or corrupt rows exist).
   - `Path detectionPath(Rect box, {List<Offset>? outline, required bool isFace})`:
     with an outline, map `box.left + p.dx * box.width`, `box.top + p.dy * box.height` and
     build a **closed smooth** path (Catmull-Rom → cubic Béziers, tension 0.5) so 30-60
     straight segments look like a natural edge. Without one: `isFace` → `addOval(box)`;
     body → `addRRect(box, radius = 8% of the shorter side)`.
4. Tests: encode/decode round trip within 0.001; clamping; malformed strings → null;
   `detectionPath` bounds equal the box for the fallback; with an outline the path bounds
   match the mapped points' bounds (± smoothing overshoot, allow 3%); a fixture parse gives
   12 points for face 0, null for face 1, 20 for the body.

**Commit:** `feat(mobile): parse outlines and share one detection path helper`

---

### Task 6: Phone storage: schema v13 and the scan store

**Files**
- Modify: `mobile/lib/data/db/tables.dart` (`MediaDetections`: `TextColumn get outline => text().nullable()();`)
- Modify: `mobile/lib/data/db/app_database.dart`
- Regenerate: `mobile/lib/data/db/app_database.g.dart` (`dart run build_runner build`)
- Modify: `mobile/lib/domain/scan/photo_result_store.dart`
- Modify: `mobile/test/data/app_database_test.dart`, the photo result store tests

**Steps**
1. `currentSchemaVersion = 13`; `if (from < 13) { await addMissing(mediaDetections, [mediaDetections.outline]); }`
   using the existing `addMissing` helper (idempotent if the column already exists).
   No rescan is forced; existing rows keep `outline = NULL` (see Task 8).
2. `_putDetection(...)` gets a `String? outline` parameter and writes it. All four call sites
   (`photo_result_store.dart` ~lines 311, 375, 420, 500) pass
   `encodeOutline(face.outline, face.bbox)` / `encodeOutline(body.outline, body.bbox)` for
   the detection being written. Careful at the sites where a detection is linked to an
   existing face (rescan / same-file duplicate): the outline is the one from **this**
   analysis of **this** frame, because the box being stored is also this frame's box.
3. Backup: `backup_service.dart` inserts by the column names present in each JSONL row, so
   a new backup includes `outline` and an old backup (no key) restores with NULL. Add a test
   that restores an old-format `media_detections` row without `outline`.
4. Tests: migration 12 → 13 on a v12 database keeps rows and adds the column; a scan of an
   analysis with outlines stores them; one without stores NULL; rescanning the same photo
   replaces the outline.

**Commit:** `feat(mobile): store outlines in media_detections (schema v13)`

---

### Task 7: Every overlay draws the real outline

Replace **all** shape drawing with `detectionPath(...)`. Delete
`ReviewHighlightPainter.createBodySilhouettePath` entirely (grep must find no use).

**Readers (carry the outline to the UI):**
- `mobile/lib/data/repositories/media_queries.dart` `watchDetections`: select `d.outline`,
  add `outline` (decoded `List<Offset>?`) to `MediaDetection`.
- `mobile/lib/data/repositories/review_visual_repository.dart`: select `d.outline` (NULL when
  falling back to the face/body table box), add it to `ReviewVisual`.

**Painters / overlays:**
1. `review_media_viewer.dart` `ReviewHighlightPainter`: new `outline` parameter; path =
   `detectionPath(target, outline: outline, isFace: isFace)`. Keep the dimmed-outside cutout,
   translucent fill and 3 px stroke. Include `outline` in `shouldRepaint` (compare with
   `listEquals`). Pass `v.outline` from the viewer.
2. `highlighted_photo.dart`: pass `v.outline`.
3. `media_screen.dart` (~line 546) and `video_media_view.dart` (~line 171): replace the
   `Container(BoxDecoration(shape: ...))` boxes with a `CustomPaint` using `detectionPath`
   inside the same `Positioned` (box-relative outline → paint in the Positioned's local
   rect `Offset.zero & size`). Keep the existing tap target (`GestureDetector`) and
   semantics; hit testing may stay rectangular. Keep the person label chip.
4. `analyze_screen.dart` `DetectionsPainter`: faces and bodies use `detectionPath` with the
   live DTO outline converted to box-relative (`(p - box.topLeft) / box.size`); keep the
   keypoint dots for bodies.
5. `reface_screen.dart` (~line 862) target-face selector and `restyle_screen.dart` (~line 218)
   protected face: same `CustomPaint` approach from the live analysis outline; selected state
   keeps its green colour.
6. Widget tests: for each of review viewer, media screen, video view, analyze, reface,
   restyle: with an outline the painter receives it (golden-free check: find the
   `CustomPaint`, read its painter's `outline`); without one, faces fall back to oval and
   bodies to rounded rect. Existing keys (`review-target-highlight`, `target-face-$i`,
   `highlight-$kind-$id`, `toggle-faces`, `toggle-bodies`) must keep working.

**Commit:** `feat(mobile): draw real face/body outlines in every overlay; drop template silhouette`

---

### Task 8: Outlines for photos scanned before this change (on-demand backfill)

Existing libraries have thousands of detections with `outline = NULL`. Don't force a
rescan. Fill them when the user actually looks at a photo.

**Server**
- New endpoint `POST /v1/analyze/outlines` (multipart: `image` JPEG + `targets` JSON
  `[{"kind": "f"|"b", "bbox": {x, y, w, h}, "kps": [[x, y] x5]?, "kpts": [[x, y, s] x17]?}]`,
  at most 32 targets). Runs only `OutlineEngine` on the given boxes (no detection, no
  embedding), under the same `compute_lock` / `gpu.require_free()` as `/v1/analyze/image`,
  inside the scan worker process (add a request type to the worker protocol rather than
  loading models in the API process). Response `{ "outlines": [ <outline or null>, ... ] }`
  in target order. Same auth, error envelope and size caps as analyze. Add it to
  `openapi.yaml` with a fixture and contract tests (fake engine).

**Phone**
- `OutlineBackfill` service: when the review viewer, highlighted photo or media screen
  opens a **photo** whose detections have `outline == NULL`, and the server is connected and
  not busy with a user job, compress the photo exactly like the scan path (≤ 2560 px),
  convert the stored box-relative boxes back to that image's pixels, call the endpoint, and
  update the rows in one transaction. The `watchDetections` stream then repaints with the
  real outline. Debounce (one request per photo per session), skip videos for now (fallback
  shapes), and never block or error the UI: failure = keep fallback.
- Faces need `kps` for the aligned parser crop; if the phone does not have them for a stored
  face, send the box only (the server falls back to the padded box crop).
- Tests: fake API; opening a photo with NULL outlines triggers one call and stores results;
  a failure leaves NULL and shows the fallback; a connected-but-busy server is skipped.

**Commit:** `feat: on-demand outline backfill for photos scanned before outlines existed`

---

### Task 9: Verify, document, hand off

1. Python (from `the app/`, venv active), all must pass:
   `test_outlines.py`, `test_analysis.py`, `test_mobile_scan_worker.py`,
   `test_mobile_api_contract.py`, `test_mobile_stateless.py`, `test_mobile_video.py`,
   `mobile_api\contract\validate_contract.py`, and the GPU check from Task 4.
2. Flutter (from `mobile/`): `dart format lib test`, `flutter analyze` (0 issues),
   full `flutter test` (report the total; the last recorded run was 373).
3. Phone: build and install on the connected Samsung (adb reverse, never the emulator), scan
   one portrait, one full-body photo, one group photo; open each in Review and in the media
   screen; take screenshots showing the outline following the person. Also open an old
   (pre-change) photo with the PC connected and confirm the backfill replaces the fallback.
4. Append a section to `docs/ANTIGRAVITY_HANDOFF.md`: what changed, the exact test counts,
   GPU timings, phone result, known limits (videos and characters use fallbacks; heavy
   occlusion merges people into one RMBG blob, mitigated by the skeleton preference).

---

## Review checklist (what Claude will check after you finish)

- [ ] `createBodySilhouettePath` is gone; no `BoxShape.circle` / rounded-rect *overlay*
      remains for faces or bodies; every overlay goes through `detectionPath`.
- [ ] Outlines come from real masks (BiSeNet / RMBG), not from boxes or keypoints only.
- [ ] `scan_worker.encode_result`/`decode_result` carry outlines (the easy-to-miss drop point).
- [ ] Without `return_outlines` the response is byte-for-byte what it was (no `outline` key),
      and `library_scanner` never pays for outlines.
- [ ] No download, no model fetch path, no new package; missing model → `null`, not an error.
- [ ] `mobile_api` still stateless; `test_mobile_stateless.py` passes.
- [ ] Outline coordinates: pixels on the wire, box-relative in the DB, same box as the
      stored detection (including the rescan/link paths in `photo_result_store.dart`).
- [ ] Schema v13 migration is idempotent and tested; old backups restore.
- [ ] Malformed or missing outlines never fail a scan or a screen.
- [ ] Backfill is debounced, skips busy server and videos, and never blocks the UI.
- [ ] Contract fixtures regenerate byte-identically and validate; Flutter fixture test parses them.
- [ ] GPU timings recorded; three debug PNGs show outlines hugging the real face/body edges.
- [ ] `flutter analyze` 0 issues, full `flutter test` green, Python tests green, counts in
      the handoff.
- [ ] None of the user's unrelated uncommitted files were modified or committed.
