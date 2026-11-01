# Gallery-first mobile implementation — 2026-11-01

The approved mobile redesign is implemented in Flutter. The app enters the local Gallery, with Photos and Folders, and uses Gallery / People / Discover / Studio as its four roots. The 68 design surfaces are mapped to actual routes, sheets and shared components in [implementation-ui-status.md](implementation-ui-status.md); they are not 68 separate routes.

## Implemented behavior

- Gallery enumerates the device library with paged MediaStore access before pairing or analysis. Opening an unindexed original creates a browsable record without automatically starting a scan. Folder browsing and folder scan scope are distinct; access denial and limited selection are explicit.
- The viewer keeps the image central, supports horizontal paging, zoom and chrome toggling, and opens people/details with an upward swipe or button. The image resizes above its details sheet. The selected occurrence and original media are passed explicitly to tools; no face is silently guessed.
- Identity profiles begin with original photos/videos and expose Identity and Models. LoRAs, datasets, saved face selections, tasks and results remain distinct. New Studio jobs persist local source/target/model provenance, and results link only when there is recorded evidence. Old results do not acquire invented provenance.
- Identity merging preserves models, datasets, jobs, results, marks and related source/target references. Saved identity editing is atomic. Artifact deletion previews describe actual files and related model/dataset deletion.
- Running Scan is reachable through Gallery/Activity and includes scope, preview, video stages, pause/resume and failed-item retry. Folder-scoped scanning uses the existing queue and never silently changes saved source choices.

## Shared people and anime track

People and anime Characters share the collection, profile, media, Actions, body/mark tools and Studio entry points. The main collection defaults to All types; People / Anime Characters are in-place filters. The older /characters URL remains an alias into the same filtered component. Compatible mixed-kind bulk operations remain available, including organization, flags and export. Identity merging and recognition still respect embedding-model compatibility.

Both kinds use the same Track, assignTracks and placeInTrack body tracking rules and caps in video. Explicit rescans upgrade older character body rows to stable tracks. Pose, group and equipment candidate queries include both kinds. Geometric action matching is independent of identity kind and never compares CCIP identity vectors to ArcFace vectors.

Engine capability is still real: the installed Reface source identity contract expects the connected model's embeddings. A CCIP anime identity is not an ArcFace identity. The shared Reface workflow reports an incompatible selection and refuses invalid submission; this UI change does not add or validate an anime-specific face-swap engine. Shared entry points do not certify every installed generative model on anime inputs.

## Dynamic photo/video actions

The user names an action through an example in an analyzed photo or a video segment. One catalog stores multiple photo and video examples under the same label. Examples and reviewed matches reference media, segment times and selected participants rather than turning an activity into a permanent person attribute.

- Photos compare normalized single-person pose or whole-group geometry for up to six participants.
- Videos compare actual sequential pose samples with monotonic temporal alignment, modest tempo variation and a fixed actor assignment. Mirror matching is an explicit option. A still photo does not establish temporal motion; photo examples search photos, and video examples search videos in the shared catalog.
- Per-frame keypoints are now saved alongside the compact identity tracks. Repeating one saved track crop/pose across later timestamps would invent motion, so old videos without actual frame evidence request an explicit rescan. Scan version 5 makes the next explicit library scan requeue older completed records from their start, including photos affected by the former outfit-only suppression. Merely browsing the gallery does not trigger that work.
- Video examples require at least three usable consecutive sampled frames, stable actor tracks, gaps no larger than 10 seconds and a segment no longer than two minutes. Missing/ambiguous evidence is refused. Fast unsampled motions and occluded keypoints can remain unmatched.
- Similarity is a ranking score, not calibrated accuracy. Results are suggested until the user confirms or rejects them. Rejections survive subsequent searches; overlapping windows are suppressed. Results can be filtered by participant, source media, photo/video and review state.
- Explicit exemplar snapshots survive missing originals. New source-version mismatches are excluded from match display/review. Identity merges remap stored participant references. Catalog and frame evidence live in the encrypted local database and travel with library backups. Removed/changed media have their disposable frame evidence removed; named exemplar snapshots remain user data.

No new model, inference endpoint, package or schema-code generation was needed for this extension. It uses existing observed COCO keypoints. Automatic extraction of intimate measurements or personal sexual preferences was not implemented.

## Adjacent-body regression

Two separate source-level problems were fixed:

1. Mobile scan storage discarded a new faceless body if its outfit matched another body in the photo. Clothing is no longer a duplicate-person test. Distinct boxes remain distinct; spatial rescan matching and the existing per-frame cap remain.
2. Backend face/body association could accept a neighbouring face from overlapping boxes despite several confident head keypoints contradicting it. The association now rejects that contradiction when at least three sufficiently confident head points all lie outside the padded face. Missing, sparse and low-confidence pose keep the prior geometric fallback.

No model box is fabricated or split, and detector NMS/weights were not changed. These fixes address demonstrated retention/association bugs; they are not an accuracy claim that the detector always separates adjacent or occluded people. Actual model outputs for a reported example still need device/GPU acceptance.

## Validation

- Final combined cycle: **861 Flutter tests passed**; analyzer **No issues found** (5.6 s). This includes the All-types collection, compatible mixed-kind bulk actions, review chooser, old character rescan upgrade, shared photo/video Actions, body retention, and backup regressions. Logs: mobile/build/gallery-first-final-tests.log and gallery-first-final-analysis.log.
- Python CPU: **8 new body-association/retention regressions passed** and **2 existing association regressions passed**. No model loading, package changes or product server start.
- Widget tests cover navigation, contextual source selection, model/result lineage, original fallbacks, swipe/zoom/sheet interaction, permissions, narrow/large text, Actions creation/review/filtering and shared character entry points. Integration fixtures exercise actual Flutter HTTPS/ACK/local-commit behavior without GPU inference.
- Actual widget previews use synthetic media/names. They were inspected and are retained in [implemented](implemented/); reference artwork remains separately in screens and wireframes.

## Actual Flutter previews

| Surface | Current widget capture |
|---|---|
| Gallery photos | [01-gallery-photos.png](implemented/01-gallery-photos.png) |
| Folders | [02-gallery-folders.png](implemented/02-gallery-folders.png) |
| Shared identity collection | [03-people.png](implemented/03-people.png) |
| Discover | [04-discover.png](implemented/04-discover.png) |
| Viewer | [05-photo.png](implemented/05-photo.png) |
| People and models sheet | [06-photo-details.png](implemented/06-photo-details.png) |
| Identity media | [07-person-media.png](implemented/07-person-media.png) |
| Identity models | [08-person-models.png](implemented/08-person-models.png) |
| Studio | [09-studio.png](implemented/09-studio.png) |
| Scan details (paused fixture) | [10-running-scan.png](implemented/10-running-scan.png) |
| Narrow dark / large text | [11-discover-dark-large.png](implemented/11-discover-dark-large.png) |
| Actions catalog | [12-actions-catalog.png](implemented/12-actions-catalog.png) |
| Action details | [13-action-details.png](implemented/13-action-details.png) |

No APK was built or installed, no product server restarted, and no GPU/model environment changed in this implementation session. Native MediaStore permission/share/move behavior, gesture feel, long-library performance and model accuracy require physical-device acceptance. Existing model installation/readiness is distinct from tested inference.
