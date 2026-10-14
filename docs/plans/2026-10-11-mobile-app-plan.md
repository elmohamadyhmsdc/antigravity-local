# Antigravity Mobile — Flutter app + stateless GPU API

## Context

`the app/` (Antigravity Local) is a Streamlit dashboard that mines faces/bodies from photos and videos, groups them into people, face-swaps them (Reface), restyles clothes (Magic Undress) and trains/generates character LoRAs. All of it runs on one Windows PC with a CUDA GPU and keeps its data in `the app/data/*.json`.

The goal is a **phone app that exposes all of these features, where every piece of user data lives on the phone** and the PC is only a compute engine reached as an API.

Decisions already made with the user:

| Decision | Choice |
|---|---|
| Mobile stack | **Flutter** (Android first; iOS possible later) |
| Where compute runs | **The user's PC, same Wi-Fi only** (no Tailscale, no cloud) |
| Languages | **English only** — strings still go through ARB files so Arabic can be added later |

Decisions I'm making (flag if you disagree):

1. **New API package inside `the app/` (`the app/mobile_api/`)**, not an extension of `python-services/`. The real engines (V3 swap, undress, LoRA, scanner) live in `the app/`; `python-services/` is path-based (stateful), uses different clustering (DBSCAN), and has none of those engines. It stays untouched.
2. **Grouping stays in Python, exposed as a stateless pure-function endpoint.** `person_linking.py` is already pure NumPy and was tuned/measured (98% auto-match, 0 wrong). Porting ~650 lines to Dart would fork the thresholds. The phone sends embeddings, the server returns decisions, nothing is stored.
3. **Face-swap sources are embeddings, not images.** `identity.py` documents that inswapper consumes only a 512-d `normed_embedding`. The phone sends 2 KB per face instead of uploading photos.
4. **Magic Undress is exposed as a thin client of the existing `undress_image` job** (same params, no new capabilities). The phone adds privacy defaults: app lock, results private by default, no auto-save to the system gallery.
5. **Legacy Reface V1 is not exposed**; V3 (HD) is the default, V2 sits under an "Advanced → Legacy" toggle, DFM ("Pro") appears only if the server reports trained `.dfm` models.

## 1. Architecture

```
┌────────────── Phone (Flutter) ──────────────┐   same Wi-Fi    ┌─────────── PC (GPU) ───────────┐
│ UI (Riverpod, go_router)                    │  HTTPS, pinned  │ mobile_api (FastAPI, NEW)      │
│ Domain: scan / grouping glue / job tracker  │  cert + bearer  │  /v1/analyze  /v1/grouping     │
│ Data:  Drift + SQLCipher, private file store│ ──────────────▶ │  /v1/jobs     /v1/blobs        │
│ Sync:  persistent upload + job queues       │ ◀────────────── │ Imports existing engines       │
│ = SOURCE OF TRUTH for all user data         │  JSON/multipart │ NO user DB, ephemeral workdir  │
└─────────────────────────────────────────────┘   + SSE         └────────────────────────────────┘
```

### The statelessness contract (what "data lives on the phone" means precisely)

1. Every request carries everything it needs, or references **content-addressed blobs** (`sha256`). If the server doesn't have a blob it answers `409 {missing:[sha…]}` and the phone uploads it. The server's blob store is a **size-capped, evictable cache**, never the only copy.
2. `mobile_api` never imports `database.JsonDatabase` and never reads `data/`. A test enforces this (greps the package's imports).
3. Server workspace `the app/mobile_workspace/` (gitignored) holds blobs + job dirs. Job dirs are deleted when the phone ACKs the download (`DELETE /v1/jobs/{id}`) or after a 24 h TTL. Wiped on server start.
4. The only thing the server persists is **paired devices + its own TLS cert** (`mobile_workspace/devices.json`) — not user data.
5. Every embedding is stamped with `model_id` (`buffalo_l@1`). The server rejects mixed models; the phone stores it per face so a future model change can trigger a re-scan instead of silent corruption.

## 2. Feature → screen → API map

| Dashboard feature (existing) | Mobile screen(s) | Runs on | Server API |
|---|---|---|---|
| Data Sources / Scan library (`library_scanner.py`) | Library → Sources, Scan sheet | Phone enumerates MediaStore; server detects | `POST /v1/analyze/image`, job `analyze_video` |
| Gallery → People | People grid, Person detail | Phone (local DB) | — |
| Gallery → Review (matches, new groups, duplicates, outfit links) | Review | Phone UI; server computes suggestions | `POST /v1/grouping/plan` |
| Gallery → Media inspector | Media viewer (boxes overlay, "who's in this") | Phone | — |
| Gallery → Insights / Dashboard stats | Home, Insights | Phone (SQL) | — |
| Merge People | Merge compare screen | Phone (DB op); suggestions from grouping plan | `POST /v1/grouping/plan` |
| Build Faceset / Saved Facesets | Person → "Identity set" (selected faces) | Phone (embeddings only) | — |
| Reface (image) V3 / V2 / DFM | Reface wizard + Result | GPU job | job `reface_image_v3` / `_v2` / `_dfm` |
| Reface (video) | same wizard, video target | GPU job (video uploaded as blob) | job `reface_video_*` |
| Reface with "Trained LoRA" identity (`lora_identity.py`) | Reface wizard → source = LoRA | **Phone**: identity set = real-face embeddings + embeddings of generated portraits (it runs `analyze/image` on them; keeps the 0.4 anchor-similarity gate). No LoRA blob goes to the reface job | job `reface_*` unchanged (`source_faces` only) |
| Magic Undress | Restyle wizard + Result | GPU job | job `undress_image` |
| Character LoRA → Dataset | LoRA dataset builder | Phone picks; server tags/crops | job `build_lora_dataset` |
| Character LoRA → Train | LoRA train (live loss/ETA) | GPU job | job `train_lora` |
| Character LoRA → Generate | LoRA generate | GPU job | job `generate_lora_images` |
| Export for LoRA | LoRA → "Export zip" | Phone (zip + share sheet) | — |
| Background Jobs / Queue (running/paused/queued/done) | Jobs, Job detail | Phone mirror of server jobs | `GET/POST /v1/jobs…` |
| Settings (thresholds, strictness, scan options) | Settings | Phone (sent per request) | `GET /v1/capabilities` |

## 3. Server API v1 (`the app/mobile_api/`)

**Auth/transport.** HTTPS with a self-signed cert generated on first run; the QR carries the cert's SHA-256 so the app **pins it** (Dio custom `HttpClient` + `badCertificateCallback` comparing fingerprints). `Authorization: Bearer <device token>` (tokens stored hashed in `devices.json`). Discovery: mDNS `_antigravity._tcp` (python `zeroconf` / Flutter `nsd`), with manual IP entry as fallback (some routers block multicast / isolate clients).

**Pairing.** PC shows a QR in a small window (`run_mobile_api.bat` opens `http://localhost:8443/pair`, localhost-only page): payload `agmobile://pair?h=<ip>&p=<port>&fp=<cert sha256>&c=<one-time code>`. Phone scans → `POST /v1/pair/complete {code, device_name}` → `{token, server_id}`.

**Conventions.** `/v1` prefix; JSON; embeddings = float32 little-endian base64 (2 KB) in v1; boxes returned as pixels of the *uploaded* image plus `image_w/h` (phone stores normalised 0‒1); errors `{error:{code,message,retryable}}`; `503 gpu_busy` + `Retry-After` when a heavy job is running (reuse `job_manager.gpu_heavy_job_running`, checked against **both** this API's queue and the Streamlit queue — 6 GB VRAM can't host both).

| Endpoint | Purpose | Notes / reuses |
|---|---|---|
| `GET /v1/health` (no auth) | liveness, `server_id`, `api_version` | |
| `GET /v1/capabilities` | engines present, `.dfm` models, restorers, base checkpoints for LoRA, GPU name/VRAM, upload limits, `embedding_model`, busy job | scans `models/`, `dfm_engine` model discovery |
| `POST /v1/pair/complete` | exchange one-time code for token | |
| `HEAD/PUT /v1/blobs/{sha256}` | exists? / upload (chunked via `Content-Range`, resumable) | cache with LRU cap |
| `POST /v1/analyze/image` | multipart `image` + JSON `options` → `{image_w,h, faces[], bodies[], pairs[]}` | new `analysis.analyze_frame()` extracted from `LibraryScanner._scan_frame`, `detect_faces`, `assess_face`, `BodyAnalyzer.analyze`, `pl.associate_faces_bodies`, `pl.appearance_descriptor` |
| `POST /v1/grouping/plan` | one call = `group_library` + `review_state` | new DB-free `grouping_core.py` (see §4) |
| `POST /v1/jobs` | `{type, params, inputs:{name:sha256}}` → `201 {job_id}` or `409 {missing}` | wraps `JobManager`/`add_job_to_queue` with `jobs_dir=mobile_workspace/jobs` |
| `GET /v1/jobs?ids=` / `GET /v1/jobs/{id}` | status batch / one | maps `Job` (status, progress, message, `last_frame`, `details`) |
| `GET /v1/jobs/{id}/events` | SSE progress (polling fallback) | |
| `POST /v1/jobs/{id}/stop` · `/resume` | pause/resume (video resume via `last_frame`) | `request_stop`, `resume_job` |
| `GET /v1/jobs/{id}/result` · `/result/{name}` | manifest `{files[{name,size,sha256,mime}]}`, file download with `Range` | |
| `DELETE /v1/jobs/{id}` | ACK + purge job dir | |

**Per-image analysis payload** (maps 1:1 to what the JSON store keeps today):
`faces[]: {bbox, kps(5×2), det_score, embedding, quality{quality_score,…v2 fields}, pose, crop_jpeg(optional, ≤256 px, 20 % pad like `_face_crop`)}`;
`bodies[]: {bbox, score, kpts(17×3), appearance, extent, crop_jpeg}`; `pairs[]: [face_idx, body_idx, score]`.
Server returns crops so the phone never decodes full-res images in Dart and video-derived detections (no frame on the phone) get crops uniformly.

**Job types and params** (all derived from `run_single_job` and its engines):

| `type` | Key params | Inputs (blobs) | Result files |
|---|---|---|---|
| `reface_image_v3` (+`_v2`, `_dfm`) | `source_faces[{embedding,quality,pose}]` (**new**, replaces `faceset_name`/`source_paths`), `target_faces[bbox]` (**bbox-matched** server-side, not indices), `restorer`, `restorer_weight`, `use_parser`, `use_occluder`, `realism_preset`, `realism_overrides`, `dfm_model` | `target` | `result.png` (+ `report.json`) |
| `reface_video_*` | same + `start_time`, `end_time` | `target` (video) | `result.mp4` (audio muxed — existing) |
| `analyze_video` | `frame_interval`, `min_quality`, `detect_bodies`, `video_similar_distance` | `video` | `detections.ndjson` + `crops.zip` (reuses `_scan_video`; resumable) |
| `undress_image` | `face_bbox`, `prompt`, `negative_prompt`, `seed`, `steps`, `guidance_scale`, `strength`, `init_color`, `controlnet_scale`, `ref_scale`, `refine`, `refine_strength`, `refine_steps` | `image`, `refs[]` | `result.png`, `mask.png`, `pose.png` |
| `build_lora_dataset` | `trigger_word`, `repeats` | `images[]` | `dataset.zip` (crops + captions) + `preview.json` (so the phone can show/edit captions) |
| `train_lora` | `output_name`, `base_checkpoint` (from capabilities), `epochs`, `network_dim`, `network_alpha`, `learning_rate`, `batch_size`, `max_resolution` | `dataset` | `<name>.safetensors`; live `details` (stage, epoch/step, loss, s/step) |
| `generate_lora_images` | `trigger_word`, `prompt`, `negative_prompt`, `num_images`, `seed`, `steps`, `lora_scale`, `guidance_scale`, `multi_angle`, `reference_mode` (`composition`/`style`/`both`), `reference_strength`, `reference_scale` | `lora`, `reference?` | `image_NN.png` streamed as produced |

## 4. Server-side work (behaviour-preserving refactors first)

New files in `the app/mobile_api/`: `app.py`, `auth.py`, `pairing.py`, `tls.py`, `discovery.py`, `workspace.py` (blob cache, TTL purge), `schemas.py`, `routes_analyze.py`, `routes_grouping.py`, `routes_jobs.py`, `gpu_guard.py`; plus `run_mobile_api.bat` and `requirements_mobile_api.txt` (`fastapi`, `uvicorn`, `python-multipart`, `zeroconf`, `cryptography`, `qrcode`, `httpx` for tests). Installing into the fragile `venv` is a separate, explicit step — never silently.

Refactors, each guarded by existing tests before/after:

1. **`analysis.py`** — extract pure `analyze_frame(face_app, body, img, options)` from `LibraryScanner`. `library_scanner.py` calls it, so the Streamlit app keeps working. Guard: `test_gallery.py`.
2. **`grouping_core.py`** — extract DB-free `plan(snapshot, strictness)` from `gallery_grouping.group_library` + `review_state` (they're thin glue over `person_linking`). `gallery_grouping.py` becomes a wrapper that builds the snapshot from `JsonDatabase`. Guard: `test_gallery.py`, `eval_grouping.py` must print **identical** numbers.
   Request/response are defined in `the app/mobile_api/contract/openapi.yaml` (`GroupingPlanRequest/Response`) and pinned by real-output fixtures. Shape: `mode: apply|review` (apply = `group_library` semantics, only confident decisions; review = `review_state` semantics, everything the Review screen shows) and `stages` ⊆ `[match, cluster, duplicates, bodies]`. `models[{pid, proto, members[≤cap], count}]` (phone precomputes `proto` = q²-weighted mean — mirrors `build_person_models`; members best-quality first; **cap must stay ≥ 50** because duplicate-person scoring reads the first 50), `pending[{id, embedding, quality, frame_key, rejected_person_ids}]`, `distinct_pairs`, `bodies[{…, anchor_person_id}]`. Response: `assignments[]`, `groups[{face_ids, cohesion, quality, auto_create}]`, `duplicates[]`, `body_links[]`, `unsorted_face_ids[]`.
   The phone orchestrates rounds so ids stay real: round 1 `apply [match, cluster]` → apply autos in one transaction (new people get real ids) → round 2 `apply [bodies]` (derived body links cleared first, as `relink_bodies` does) → round 3 `review [all]` → store suggestions. Member cap benchmarked in Phase 2 (300 → ~100) with `eval_grouping.py` to keep accuracy.
3. **`job_manager.run_single_job`** — add `source_faces` branch: build an in-memory `Faceset` from embeddings (**never unpickle anything received over the network**; `Faceset.load` is pickle-based and stays local-only).
4. **`lora_trainer.run_training`** — already skips `set_person_lora_info` when `person_id` is absent; mobile omits it. Verify `undress_core.OUTPUT_DIR` and `lora_generate_job` output dirs can point at the job dir (parameterise if hard-coded).
5. **GPU guard** — one `gpu_busy()` consulting both jobs dirs.

## 5. Mobile app (`mobile/` at repo root; add a row to the root `CLAUDE.md` table)

**Stack:** Flutter stable, Dart 3. `flutter_riverpod` (state/DI), `go_router`, `drift` + `sqlcipher_flutter_libs` (encrypted SQLite; key in Android Keystore via `flutter_secure_storage`), `dio` (+ pinning), `photo_manager` (MediaStore + change detection), `mobile_scanner` (QR), `nsd` (mDNS), `flutter_foreground_task` (scan/upload/job tracking survive backgrounding), `flutter_image_compress` (native downscale before upload), `crypto` (sha256), `archive` (zip), `local_auth` (app lock), `share_plus`, `media_kit` or `video_player`, `fl_chart`, `freezed`+`json_serializable`, `intl`/ARB. Exact versions pinned at scaffold time after checking pub.dev.

**Layers**
```
mobile/lib/
  main.dart  app.dart                 # theme, router, l10n
  core/        errors, logging, isolate_pool, hashing, result
  data/
    db/        drift tables, DAOs, migrations
    files/     FileStore (faces/, bodies/, results/, loras/, datasets/, tmp/, backups/)
    api/       client, pinning, pairing, DTOs, sse, resumable_upload, blob_sync
    index/     EmbeddingIndex (Float32List matrix in an isolate; dedupe ≤0.05, similar-face search)
    repositories/
  domain/      entities + use cases: ScanLibrary, ApplyGroupingPlan, MergePeople,
               StartReface, StartRestyle, BuildLoraDataset, TrainLora, GenerateLora, BackupLibrary
  features/    onboarding/ home/ library/ people/ review/ media/ merge/ reface/ restyle/
               lora/ jobs/ results/ settings/ backup/
  l10n/        app_en.arb
```

**Local schema** (mirrors the JSON store so `person_linking` inputs are always available): `persons`, `faces` (embedding BLOB, `model_id`, quality fields, normalised bbox, `kps`, `pose`, `media_id`, `frame_number`, `timestamp`, `crop_path`, `review_dismissed`), `bodies` (appearance BLOB, `kpts`, `extent`, `face_id`/`person_id`, `link_method`, `link_confidence`, `weak_face_embedding`, `crop_path`), `media` (MediaStore `asset_id`, kind, size, modified, duration, scan_status/version, `last_scanned_frame`), `face_rejections`, `body_rejections`, `person_distinct`, `identity_sets`, `loras`, `lora_dataset_items`, `jobs` (local mirror of server jobs), `results`, `upload_queue`, `blob_hints`, `servers`, `settings`. Detections need no table — faces/bodies already carry `media_id` + box. Originals are **referenced** (MediaStore asset id), never copied.

**Key pipelines**
- **Scan:** enumerate selected albums → diff vs `media` (asset id + modified + size) → persistent work queue → per photo: downscale ≤2560 px JPEG → `analyze/image` → on-device dedupe vs `EmbeddingIndex` (≥ 0.95 cosine ≈ the 0.05 distance rule) → insert faces/bodies + crops → per batch call `grouping/plan` → apply autos in one transaction. Videos: resumable upload → `analyze_video` job → import ndjson + crops. Everything idempotent so a killed app resumes.
- **Job tracker:** local `jobs` row is the source of truth; foreground service polls/SSEs; on reconnect `GET /v1/jobs?ids=` re-syncs. Phone leaving the Wi-Fi never loses a job (server keeps it until ACK/TTL).
- **Backup/restore (mandatory, because the phone is the only copy):** export one `.agbackup` zip (DB dump + crops + results + LoRAs, optional) via share sheet / Files; import restores. Early, not last.

**Privacy/security:** SQLCipher DB; `allowBackup=false` + `dataExtractionRules` excluding the app; app lock (biometric/PIN) with relock on background; `FLAG_SECURE` on media/result screens; results private by default (explicit "Export to gallery"); no analytics; permissions only `READ_MEDIA_IMAGES/VIDEO`, `CAMERA` (QR), `POST_NOTIFICATIONS`, foreground-service data-sync, multicast for mDNS; network security config forbids cleartext (pinned HTTPS only; emulator dev uses `10.0.2.2` with the same pinning).

## 6. Screens

**Navigation:** bottom bar — **Home · People · Library · Studio · Jobs**; Settings from Home's app bar. Studio = hub for Reface / Restyle / LoRA.

| # | Screen | Purpose / contents |
|---|---|---|
| S01 | Welcome / Pair | connect to PC: scan QR or enter IP; shows server name, GPU, models found |
| S02 | Permissions | media, camera (QR), notifications — explains why |
| S03 | Home | server status chip, library stats (people/faces/photos/videos), unsorted + pending-review counts, "Scan library", running jobs, recent results |
| S04 | Library | media grid (photos/videos), filters: person, scanned/unscanned, has faces; tap → S06 |
| S05 | Sources & Scan | choose albums/folders, scan options (video frame interval, min quality, bodies on/off), progress sheet (files, faces found, ETA, pause/resume) |
| S06 | Media viewer | full photo/video with face/body boxes, "who's in this", tap box → assign/reject/open person |
| S07 | People | grid of person cards (avatar, name, face count), search, sort, "unsorted" card |
| S08 | Person detail | tabs: Faces · Photos & Videos · Bodies · Suggestions; rename, set avatar, delete, "Use in Studio" |
| S09 | Face picker | multi-select faces: assign, move, reject, delete, set as avatar |
| S10 | Review | tabs: Matches (confirm/reject per person) · New groups · Duplicates · Outfit links; bulk accept; shows "N need a decision" |
| S11 | Merge people | side-by-side A/B with similarity score, merge/keep distinct |
| S12 | Studio hub | cards: Reface, Restyle, Character LoRA; server busy banner |
| S13 | Reface wizard | ① target (library/camera roll, photo or video + trim) ② pick faces to swap (boxes) ③ pick person / identity set / LoRA ④ engine (HD default, Legacy, Pro/DFM if available) + quality & realism presets ⑤ review & submit |
| S14 | Reface result | before/after slider, play video, save privately / export / share, re-run with tweaks |
| S15 | Restyle wizard | pick photo (or from a person), auto face-protect box (adjustable), prompt/negative/strength/steps/seed/refs (advanced collapsed), submit |
| S16 | Restyle result | before/after, mask/pose debug toggle, export |
| S17 | LoRA hub | per person: dataset status, trained LoRAs, "Generate" |
| S18 | LoRA dataset | pick photos/videos for a person → server builds crops + captions → editable grid (include/exclude, edit caption, trigger word) → export zip or continue |
| S19 | LoRA train | base model, epochs/dim/lr/batch/resolution presets; live stage, epoch/step, loss, s/step, ETA; stop/resume |
| S20 | LoRA generate | prompt presets, count, seed, optional reference image (pose / style / both), results grid |
| S21 | Jobs | sections: Running · Paused · Queue · Completed/Failed; progress, stop/resume/delete |
| S22 | Job detail | params, server log tail, error, result preview, retry |
| S23 | Results | private gallery of all outputs, filter by type/person, favourite, export, delete |
| S24 | Settings | server (re-pair, test, capabilities), grouping strictness (strict/balanced/loose), quality gate, scan defaults, app lock, storage manager |
| S25 | Storage manager | sizes of crops/results/LoRAs/blobs-cache hints; bulk delete |
| S26 | Backup & restore | export/import `.agbackup`, last backup date, reminder |
| S27 | Insights | quality tiers, faces per source, coverage (angles per person), duplicates |

**Wireframes (key screens)**

```
HOME                          PEOPLE                        REVIEW
┌────────────────────────┐    ┌────────────────────────┐    ┌────────────────────────┐
│ Antigravity   ● PC-Home⚙│    │ People        🔍  ⇅   │    │ Review (14)            │
│ ┌─────┬─────┬─────┬────┐│    │ ┌───┐┌───┐┌───┐┌───┐  │    │ Matches|Groups|Dups|Fit│
│ │ 42  │1.2k │3.4k │ 87 ││    │ │ ◉ ││ ◉ ││ ◉ ││ ? │  │    │ ── Sara (3 faces) ──── │
│ │ppl  │faces│photo│vids││    │ │Sara││Omar││Lina││Uns│  │    │ ◻◻◻  [Accept][Reject]  │
│ └─────┴─────┴─────┴────┘│    │ │120││ 98││ 64││ 31│  │    │ ── New group (5) ───── │
│ [ Scan library      ▶ ]│    │ └───┘└───┘└───┘└───┘  │    │ ◻◻◻◻◻ [Name…][Create]  │
│ Needs review: 14  ›    │    │ ┌───┐┌───┐             │    │ ── Possible duplicate ─│
│ Running ▓▓▓░ Reface 63%│    │ │ … ││ … │             │    │ Sara ↔ Sarah  0.52 [⇄] │
│ Recent results  ▢▢▢▢   │    │ └───┘└───┘             │    │                        │
├────────────────────────┤    ├────────────────────────┤    ├────────────────────────┤
│Home People Library Studio Jobs│                          │
└────────────────────────┘

REFACE WIZARD (step 2)        JOBS
┌────────────────────────┐    ┌────────────────────────┐
│ ← Reface   ②/⑤ Faces  │    │ Jobs                   │
│ ┌────────────────────┐ │    │ Running                │
│ │  photo             │ │    │ ▶ Reface V3  ▓▓▓▓░ 63% │
│ │   ┌──┐     ┌──┐    │ │    │   frame 410/650  [■]   │
│ │   │✓1│     │ 2│    │ │    │ Queue                  │
│ │   └──┘     └──┘    │ │    │ ◔ Train LoRA (waiting) │
│ └────────────────────┘ │    │ Paused                 │
│ Tap faces to swap      │    │ ⏸ Reface video  41% [▶]│
│ [ Select all ] [Next ›]│    │ Completed              │
└────────────────────────┘    │ ✓ Restyle   2m ago  ›  │
                              └────────────────────────┘
```

**Core flows**
- *Scan:* S05 → progress sheet → auto-grouping → S03 shows "N need review" → S10.
- *Reface:* S12 → S13 (target → faces → identity → engine) → submit → S21 (progress) → notification → S14.
- *LoRA:* S17 → S18 (server builds + captions → edit) → S19 (train, live) → LoRA saved on phone → S20 or S13 (source = LoRA).

## 7. Phases (relative size: S ≈ days, M ≈ 1–2 wks, L ≈ 2–4 wks, one dev + Claude)

| Phase | Scope | Exit criteria |
|---|---|---|
| **P0 Foundations (S)** | Save this plan to `docs/plans/2026-10-11-mobile-app-plan.md`; add `mobile/` row to root `CLAUDE.md`; verify Flutter/Android toolchain (`flutter doctor`); write `mobile_api` OpenAPI contract + golden JSON fixtures; scaffold Flutter app (theme, router, l10n, CI-less scripts) | `flutter run` shows empty shell; contract + fixtures committed |
| **P1 Server core + pairing (M)** | `mobile_api` skeleton, TLS, pairing QR, auth, health/capabilities, blob store + workspace purge, GPU guard, `analysis.py` refactor + `analyze/image`; Flutter: pairing, pinned client, DB setup, S01–S03 | Phone pairs over Wi-Fi; analyzes a photo and shows detected faces; `test_gallery.py` still green |
| **P2 Library & People (L)** | Scan pipeline (photos), EmbeddingIndex + dedupe, `grouping_core.py` + `grouping/plan`, People/Person/Face picker/Review/Merge screens, manual ops (assign/reject/distinct), **backup/restore v1** | Scan 200 photos → people appear → review works; `eval_grouping.py` numbers identical; backup→restore round-trips |
| **P3 Videos & bodies (M)** | `analyze_video` job + resumable upload, body links, media viewer with overlays, Insights | A 2-min video scans, resumes after app kill; outfit suggestions appear |
| **P4 Reface (L)** | Jobs infra (queue mirror, SSE, stop/resume, foreground service, notifications), `source_faces` branch, Reface wizard + result (image V3, V2 legacy, video, DFM), Results gallery | Image swap end-to-end < ~1 min on LAN; video pause/resume works; result stored only on phone |
| **P5 Restyle (S)** | `undress_image` job, wizard + result, privacy defaults | Job round-trips with refs; output private by default |
| **P6 Character LoRA (L)** | `build_lora_dataset`, dataset editor, `train_lora` live view + resume, `generate_lora_images`, LoRA as Reface identity source, export zip | Train a small LoRA from the phone; safetensors lands on phone; reuse in Reface (re-upload via blob cache) |
| **P7 Hardening (M)** | App lock, FLAG_SECURE, storage manager, perf (100k-face budget, isolates), error/empty states, release build/signing, README + docs | Cold start < 2 s on mid phone; all screens handle offline/busy/error; release APK installs |

## 8. Critical files

- Reuse (read-only unless noted): `the app/library_scanner.py` (**refactor** → `analysis.py`), `face_quality.py`, `body_detector.py`, `person_linking.py` (unchanged), `gallery_grouping.py` (**refactor** → `grouping_core.py`), `reface_engine_v3.py`, `identity.py`, `job_manager.py` (**add** `source_faces`), `undress_core.py`, `lora_trainer.py`, `lora_generate_job.py`, `lora_dataset.py`, `dfm_engine.py`, `ffmpeg_utils.py`, `cuda_dll_dirs.py`.
- New: `the app/mobile_api/**` (contract already in `contract/`), `the app/mobile_workspace/` (gitignored), `the app/requirements_mobile_api.txt`, `the app/run_mobile_api.bat`, `mobile/**`, `docs/plans/2026-10-11-mobile-app-plan.md`.
- Unchanged: `python-services/`, `DeepFaceLab_NVIDIA_RTX3000_series/`, `RTM WF faceset/`.

## 9. Verification

*Server (repo convention: standalone scripts that print results and `exit(1)` on failure):*
- `test_mobile_api_contract.py` — FastAPI `TestClient` with fake engines (no GPU): auth, pairing, blob 409/upload, job lifecycle, error envelope, response shapes vs golden fixtures.
- `test_grouping_core.py` — `grouping_core.plan()` equals old `group_library`/`review_state` on the `test_gallery.py` fixture library; `eval_grouping.py` unchanged.
- `test_mobile_stateless.py` — `mobile_api` imports no `database`; running the contract suite leaves `data/` byte-identical; workspace purged after ACK/TTL.
- `test_mobile_api_gpu.py` (opt-in, needs models): real `analyze/image` on a fixture photo; a V3 image swap from an embedding-only source; undress/LoRA smoke on tiny settings.
- Existing suites stay green: `test_gallery.py`, `test_gallery_ui.py`, `test_compositor.py`, `test_undress.py`, `test_v3_smoke.py`.

*Mobile:* `flutter analyze`; unit tests (DAOs, migrations, `EmbeddingIndex` dedupe, grouping-plan apply, DTO parsing against the **same golden fixtures** the server tests use); widget tests for each screen state (loading/empty/error/busy); integration test on emulator against a fake server, then against the real PC.

*End-to-end manual checklist (per phase exit):* pair → scan 50 photos → people appear → review → reface image → restyle → short LoRA train → export backup → wipe app data → restore → everything intact; kill app mid-scan and mid-job → both resume; turn Wi-Fi off mid-job → job finishes on PC and syncs on reconnect.

## 10. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Phone is the only copy → data loss | Backup/restore in P2, periodic reminder, SQLCipher-safe export |
| Router blocks mDNS / client isolation | Manual IP + QR carries host; Windows Firewall rule added by `run_mobile_api.bat` (with prompt); clear connection diagnostics screen |
| Windows PC IP changes (DHCP) | mDNS re-discovery by `server_id`; QR re-pair as fallback |
| 6 GB VRAM contention (API + Streamlit + jobs) | single `gpu_busy()` across both queues, `503 gpu_busy` + client retry |
| Large payloads (grouping, video upload) | gzip, resumable chunked uploads, member cap benchmarked against `eval_grouping.py`; 100k-face budget gate in P7 |
| FFmpegKit for Flutter is retired | Frame sampling stays server-side (`analyze_video`) |
| Embedding model upgrade | `model_id` per face; rescan flow instead of mixing |
| Android background limits | foreground service for scan/upload/job tracking; idempotent resumable queues |
| Fragile CUDA/venv setup | no new packages in `venv` without an explicit go-ahead; API runs in the existing `venv`; undress/LoRA keep their own envs via existing workers |
| Sensitive content on a pocket device (real people's photos, swap/restyle outputs) | encrypted DB, app lock, FLAG_SECURE, private-by-default results, no cloud, no analytics |

## 11. Open items (non-blocking)

- Import the existing PC library into the phone (an exporter script producing a bundle the app imports)? The repo's `the app/data/` is currently empty, so skipped unless you have a library elsewhere (e.g. `D:\AndroidScan\gallaryData`).
- iOS later: Flutter keeps it possible; `photo_manager` works but background limits are harsher.
- Minimum Android version: proposing API 26 (Android 8)+.

## 12. P1 outcome (2026-10-11) - deviations from the plan above

P1 is built and verified on a real phone; where it differs from sections 3-5:

- **Pairing page** is a second, plain-HTTP listener on `127.0.0.1:8444/pair` (the HTTPS API on 8443 never serves it), not `http://localhost:8443/pair`. It also lists paired phones with a Revoke button.
- **Blob protocol** gained the resumable details the contract left open: `HEAD` 404 carries `Upload-Offset`; `PUT` with `Content-Range: bytes a-b/total` answers 202 (+`Upload-Offset`), 201 when the SHA-256 verifies, 409 `offset_mismatch`, 422 `hash_mismatch`, 413 `too_large`. Documented in `openapi.yaml`.
- **Extra security**: pairing refuses non-LAN addresses; a tapped `agmobile://pair` link always asks first; the pairing code is single use, expires after 5 min and is burned after 5 wrong guesses; mDNS carries no certificate fingerprint (it is unauthenticated); the app refuses to open its database unless SQLCipher is really active; `allowBackup=false` + extraction rules.
- **DTOs are hand-written** (not freezed/json_serializable) and parsed against the shared golden fixtures; revisit when the job DTOs arrive in P4.
- **Not in P1**: phone-side mDNS browsing (`nsd`) - the server advertises `_antigravity._tcp` already, the phone re-discovers by `server_id` in a later phase; QR scanning was not exercised on a device (needs a person holding the camera to the PC screen).
- **Android build**: `compileSdk 37`, `kotlin.incremental=false` (pub cache on C:, project on D:), `minSdk 26` - see the root `CLAUDE.md`.
- **Keep-alive bug found on the real phone**: uvicorn closes idle connections after 5 s while dart:io keeps them pooled, so the first request after a pause failed with "Connection closed before full header was received". Fixed on both sides (server `timeout_keep_alive=75`, client retries a stale connection once) and pinned by a test.

## 13. P2 outcome (2026-10-11) - what was built, and where it differs from sections 3-7

Built (statically verified: `flutter analyze` = 0 issues, `flutter build apk --debug` OK, `py_compile`; the tests are written and handed to the user to run - see the checklist in the P2 report):

- **Server**: `grouping_core.py` (DB-free; `gallery_grouping.py` is now a wrapper over it and `person_linking.py` is untouched), `POST /v1/grouping/plan` (gzip request/response, size caps, 400 on malformed input, CPU only so never `gpu_busy`), `make_fixtures.py` calls `grouping_core.plan_request`, `test_grouping_core.py`, grouping tests in `test_mobile_api_contract.py`, `eval_member_cap.py`.
- **Phone data**: schema **v3** (migration tested from v1 and v2): `media.taken_at/scan_attempts/scan_error`, `media_detections` (every face/body in a photo, including faces linked to an earlier copy), `review_matches/groups/duplicates/body_links`, indexes. The scan queue is the `media` table itself (`scan_status`), not a separate table.
- **Scan** (photos): `photo_manager` album listing -> diff by (asset id, modified time, pixel size) -> `flutter_image_compress` -> `/v1/analyze/image` -> dedupe in an isolate-held `EmbeddingIndex` (cosine >= 0.95; same file: IoU >= 0.5 or cosine >= 0.92) -> one transaction. Foreground service (`dataSync`). 503 `gpu_busy` is waited out with the PC's Retry-After and pauses after ~5 min; an unreachable PC is retried 3 s/6 s/12 s/24 s then paused; a revoked token, a model mismatch or a missing permission pause with an explanation. Everything resumes after an app kill (`scan.active` + `resetScanning`).
- **Grouping rounds** on the phone: round 1 `apply [match, cluster]`, round 2 `apply [bodies]` (derived links re-derived, manual ones kept), round 3 `review [all]` stored in the `review_*` tables. Applied in single transactions; whatever the user did meanwhile wins. Run every 25 new faces / 60 photos and at the end, and from "Sort faces now".
- **Screens**: S04 Library (paged grid + person/scanned/has-faces filters), S05 Sources & scan (+ progress card, also on Home), S06 photo viewer (face/body boxes, who is here, assign / not them / delete / open person), S07 People, S08 Person (Faces / Photos / Bodies / Suggestions), S09 face picker (multi-select assign / move / not them / delete / cover), S10 Review (4 tabs, bulk accept), S11 Merge, S24 Settings (library part), S26 Backup & restore, S03 Home (scan, review count, backup reminder).
- **Backup & restore v1**: `.agbackup` zip, share sheet out / file picker in; restore is all-or-nothing for the database (one transaction; crops are staged and swapped in after the commit), verified by per-file SHA-256 and row counts; round-trip tested to be lossless. The file is NOT encrypted (the user is told); a passphrase option is a candidate for P7.

Deviations / decisions:

- **Member cap**: the phone sends at most `groupingMemberCap = 100` members per person (the PC's own gallery uses 300). The cap only affects the "3 most similar members" half of the matching score; the prototype uses every face and duplicate scoring reads `members[:50]`. `eval_member_cap.py` measures 300/200/150/100/75/50 on a curated library; the repo's `the app/data/` is empty, so the choice of 100 is a default to be confirmed by the user's run - change the one constant if it says otherwise.
- `anchor_person_id` semantics (contract doc updated): round 2 sends derived links as null; the review round sends every current link, exactly like `review_state`. Apply mode also lists `suggest` body links; the phone applies only `auto`.
- Only photos that share a media row with a faceless body that has evidence (outfit or weak face) are sent in the body rounds, so the payload does not grow with the number of identified bodies.
- Bodies of a re-scanned photo are matched by IoU >= 0.5 and updated in place (the PC's scanner adds them again); a face the user deleted is not resurrected for an unchanged photo.
- Not in P2 (as scoped): videos (P3), video media viewer, Insights, passphrase-protected backups, storage manager.

## 14. P3 implementation (2026-10-14)

- Added device-owned, idempotent `analyze_video` jobs and status/stop/resume/result/ACK endpoints. Inputs are pinned in each ephemeral workspace so blob eviction cannot break active work; another paired device cannot read or control a job. Jobs expire after 24 hours when the API next checks for expired work. No changes to CUDA, model packages or the dashboard job worker.
- Video sampling reuses `analysis.analyze_frame` and its existing face/body/pair serializers, with OpenCV decoding. The GPU guard reports mobile video work; a heavy dashboard job pauses video processing at the next frame boundary.
- Phone uses common photo/video albums, an include-videos switch and a sampling interval. It streams 4 MB upload chunks, saves the idempotency key before POST, polls progress, verifies result size/SHA-256 before importing, and commits each sampled frame plus the next-frame checkpoint atomically. Lost POST responses, app closure and PC restarts are recoverable.
- Results are **one self-contained detections.ndjson**, with inline crops and `frame_number`/`timestamp_ms` on each AnalyzeImageResponse, replacing the earlier proposed crops.zip. Dedupe stays on the phone. A restarted server rounds the first uncommitted frame up to the original sampling grid.
- No DB migration: v3 already has frame/timestamp fields and media.last_scanned_frame. Private `video.job.*` settings hold ephemeral PC references; backups exclude these references, but include video scan preferences and local detections/checkpoints. Restore also discards this phone’s stale PC job references, so an older checkpoint cannot accidentally reuse a newer job.
- Added local video playback, seeking to detection timestamps, boxes only near their sample (150 ms), photo/video filtering, duration badges, body-only person/media queries and offline Insights. General Jobs/Studio screens, SSE and Reface remain P4.
- Fixed existing small-screen overflow in face selection, person suggestions and review actions, and a disposed text-controller crash in rename/create-person dialogs. Updated stale tests to scroll before tapping off-screen controls, compare nested collections separately and avoid settling infinite scan animations. Fixed Git ignore exceptions for mobile source folders named media.
- Validation: Flutter analyzer, the full Flutter suite (314 tests) plus a backup/video-checkpoint regression, 9 CPU-only video server tests including a real MJPEG decode, 28 existing API contract tests, 5 statelessness tests and contract schema/fixture validation. Android debug APK builds successfully at mobile/build/app/outputs/flutter-apk/app-debug.apk. **No real-phone or real-GPU acceptance is claimed.**

## 15. P4–P6 implementation and P7 progress (2026-10-14)

- Studio is wired to a device-owned serial compute queue: V3/V2/DFM Reface, clothes restyle, identity-matched dataset building, LoRA training and portrait generation. Jobs use stable client IDs, pinned inputs, bounded requests, SSE/polling, pause/resume, verified manifests and explicit ACK/purge. GPU inference is serialized with analysis/video work. The mobile API still never imports the desktop database or accepts uploaded pickle state.
- The phone persists jobs and private inputs before submission. Schema v5 adds Results, Datasets, DatasetItems and LoRAs. Result size/SHA-256 are checked before local commit and ACK. Dataset captions/inclusion are editable, datasets export as ZIP, LoRAs stay local and generated portraits can augment a model-stamped Reface identity after matching the real person.
- Reface offers per-face photo selection, source quality selection, V3/V2/available DFM and video trim. Results offer photo comparison, local video original/result playback, favourites, share and explicit gallery export. Restyle offers prompts, a padded protected face box, references, strength/steps/seed and refine.
- P7 work includes app lock via Android device credentials, private viewer screenshot protection, job completion notifications, storage cleanup and expanded backup/restore. Both scan and Studio writes are awaited before backup/restore. Backups include saved artifacts and omit active work and PC credentials; archives remain unencrypted.
- Automated validation: zero Flutter analyzer issues, 343 Flutter tests; server Studio/video/artifact/contract/stateless suites and OpenAPI fixture validation. Real GPU API round trips passed for V3 Reface, dataset building/captioning, a tiny one-epoch training run and LoRA portrait generation. The tiny train is an integration check, not an identity-quality evaluation.
- Restyle acceptance stopped at incomplete local weights, not a missing environment: both `venv_ai` and `venv_lora` are installed with working CUDA. The user declined downloads and explicitly prohibited Internet downloading on the current mobile connection. A full offline search of `D:/AndroidScan` identified reusable SD1.5, IP-Adapter and OpenPose body/hand files, but no complete replacement inpainting/ControlNet/SDXL set. See `docs/local-model-audit-2026-10-14.md`. Restyle is reported unavailable by capabilities until its real weights are present.

Remaining acceptance/scope: the new workflows have not been installed and exercised on the phone during this pass; Android export/device credentials/notifications and long-video background recovery need device checks. Video Reface swaps all detected faces, with individual target selection limited to photos. Training resumes from complete epoch state. Named identity presets, passphrase-encrypted backups, a log-tail/ETA UI and per-person video tracking remain possible additions. P7 performance targets and a production release signing key/configuration are still outstanding; do not label the debug APK as a production release.

## 16. Dashboard mobile administration (2026-10-14)

The regular Streamlit dashboard now exposes **Mobile Devices** at `?page=mobile`. Its local PC owner can start/stop the existing-venv server, show or invalidate a single-use QR, choose the PC address, view paired phones with last activity and active job counts, rename a phone and disconnect one/all phones. Activity is explicitly described as contact in the last 2 minutes, not a live socket claim.

The controller talks only to `127.0.0.1` using a per-run admin secret in an ephemeral workspace control descriptor. PC controls stay on the separate pairing listener and are absent from the phone-facing API. UI authorization uses the server-side WebSocket peer. Device revocation pauses its work, closes future SSE events and invalidates access and the current pairing code. Pair completion and disconnect-all are serialized. Startup reserves both listener ports before wiping scratch space, avoiding data loss on duplicate launch. Persistent auth/cert records survive stop/restart.

Validation includes Streamlit widget tests and a complete dashboard route against a fixture library, PC/LAN/admin-secret isolation, QR decoding and single-use/cancel semantics, rename/revoke persistence, pause-on-revoke, and a real temporary loopback server with certificate-verified HTTPS pairing, denial after revocation and clean shutdown. No downloads, dependency installation or GPU configuration changes are required.

## 17. Scan process isolation and Android background setup (2026-10-14)

Windows recorded a native `0xc0000005` access violation for the stopped Mobile API process. The final InsightFace deprecation warning was not an exception. The faulting library's root cause is not established: real local face/body/pose scans succeeded before and after isolation. Scan inference now uses a persistent, disposable child process with plain JSON and raw pixel bytes over anonymous pipes. Native exit/timeout becomes a retryable API error; another request starts a fresh worker, retaining pairing, health and controls. Tests inject worker exit and verify HTTP recovery, preserved auth, equivalent response/crops and shutdown cleanup. Both image and video scan share this engine path. Native tracebacks are enabled, controller exit codes are recorded, stale control descriptors produce a failed state and the dashboard exposes diagnostics. The mobile model loaders refuse network downloads.

Android Permissions/Settings now offer **Background work**, plus a one-time optional prompt at scan/Studio start. Notifications and battery exemption are requested after the user's tap. The screen refreshes on resume and exposes notification/battery/service status. Scan and Studio service leases are serialized and service failures are visible/retried. The main Flutter engine survives Activity removal; its security-window state is restored on reattachment. A service guard suppresses stale progress after process death, and the ongoing notification opens the app. OS force stop, shutdown, vendor rules and Android foreground-service timeouts remain platform limits; the saved queue resumes when the app reopens.

Validation: 348 Flutter tests, zero analyzer issues; server contract/video/Studio/stateless/dashboard/worker suites pass. Real GPU scan acceptance covers 512/1600/2560 pixel face/body/pose responses without downloads. Android debug build and real pinned HTTPS scan acceptance are recorded in the current session logs. Device installation and screen-lock/task-removal acceptance remain separate from build verification. No dependency installation, Python/CUDA modification or Internet downloading was performed.
