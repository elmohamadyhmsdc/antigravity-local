# Reface target people and gallery source identities — 2026-10-25

The target is the media being edited. The source is the person whose face is
used as the replacement. Both are now selectable without a pre-existing person
in the phone library.

| Step | Behaviour |
|---|---|
| Target photo | Analyse the chosen photo, show face boxes and cropped face choices, select people to replace. |
| Target video | Decode up to 12 small frames from the selected trim range on the phone, analyse those JPEGs, group people and select identities from the video itself. No separate target reference photo. |
| Source identity | Select a library person or add multiple photos and videos from Gallery/Files. Analyse the selected media and choose one detected person as the replacement identity. Additional files can be added. |
| Submission | Photo targets send selected boxes. Video targets send selected identity embeddings/indices. Source embeddings come only from the selected source identity. |

## Video discovery and feedback

MediaPickerBridge supports multi-file gallery selection (up to 20 per batch) and
VideoFrameSampler uses MediaMetadataRetriever on an IO worker. Frame dimensions
are capped at 1920 pixels, JPEG quality 88, with individual bitmaps recycled.
Exact seeks fall back to sync frames and unreadable frames do not discard every
other usable frame. Changing the trim invalidates stale analysis and cancels
superseded native sampling. Activity shutdown settles pending requests.

The video scan reports whether it is reading frames or analysing faces, shows
errors beside the action, and can retry. A 90-second native read timeout gives a
visible failure rather than an indefinite spinner. **Find faces in the frame
shown** analyses the current preview position and adds its identity evidence
without replacing the selected trim or discarding existing selected people.
Sampling does not guarantee that every brief appearance in a long clip is seen;
the current-frame action covers a visible person missed by the interval samples.

Small preview frames previously excluded analysis.py's 1280 detector pass because
their longest side was below 1600 pixels. The phone now retains up to 1920 pixels.
The shared detector also makes one finer-grid retry when its normal lower-size
passes find no faces. It retains the confidence threshold, avoids duplicate work
for frames already checked at that scale and preserves original coordinates.

## One identity across frames

The first UI grouping implementation required 0.55 similarity and an 0.08 lead;
it could split pose changes and then treat the growing fragments as ambiguous
competitors. It has been replaced with normalized similarity, a quality-weighted
multi-pose prototype and the project's balanced 0.40 identity threshold, plus a
0.06 ambiguity margin.

The strongest matches are assigned first. Clear later views can consolidate
compatible identity fragments, and repeated consistent fragments are considered
after frame assignment. Co-occurrence records prevent merging people seen
together, including after copying groups or consolidating other fragments.
Ambiguous evidence against known distinct people stays separate. Selected
indices are remapped when a group is consolidated. Each identity card shows its
appearance count; a bounded pool keeps at most 20 distinct high-quality source
poses while occurrence evidence survives near-duplicate removal.

These thresholds are practical matching rules, not proof that all difficult
profiles, twins, heavy occlusions or low-resolution faces will group correctly.
The user reviews the displayed identities before rendering.

## Ownership and compatibility

Imported sources stay in the form; no person or face row is inserted into the
library. The selected source identity is encoded with model ID, embedding,
quality and pose. Existing source filtering and generated-portrait safeguards on
the server still apply. A changed embedding model requires re-analysis.

The server API is unchanged. Video references stay within its 32-embedding limit;
spare capacity includes extra poses. Legacy remains available for photo targets;
it is excluded for videos because its video engine cannot enforce selected-person
replacement. V3/DFM video continues to use identity selection.

Discovery sends JPEG frames to the existing stateless image endpoint, not whole
source videos. Personal inputs/results still follow verify → local commit → ACK
→ server purge. Full target video upload before rendering is unchanged. The
finer-grid server retry requires running the updated backend code.

## Verification

- **406 Flutter tests passed** including the existing real HTTPS stateless round
  trip. Log: mobile/build/reface-final-identities-tests.log.
- Flutter analyzer **no issues** (mobile/build/reface-final-identities-analyze.log).
- Eleven focused identity/flow regressions cover varied poses across nine frames,
  fragment consolidation and selection remapping, co-occurring lookalikes,
  ambiguous detections, bounded pools/reference counts, source photos plus video
  with an empty people library, selected target/source wire parameters, stale
  results, empty scans/current-preview recovery and visible error/retry behaviour.
- **7/7 analysis tests passed**, including finer-grid fallback, original-coordinate
  preservation, no redundant high-resolution retry and truly empty images.
  Log: mobile/build/reface-empty-scan-server.log.
- API contract **28/28**, stateless isolation **5/5** passed. Logs:
  mobile/build/reface-identities-{api-contract,stateless}.log.
- New native Kotlin code compiled in an offline Debug build. No new dependency,
  CUDA/model installation, phone installation, real-library mutation or user
  server restart was performed by this task. The user's later phone feedback
  confirmed faces were being returned, then exposed the grouping problem; the
  final clustering change still needs visual confirmation on their actual clip.

Main files: mobile/lib/features/reface/{reface_screen,reface_media,reface_faces,
reface_face_choices,reface_video_trimmer}.dart; Android MediaPickerBridge.kt and
VideoFrameSampler.kt; the app/{analysis,test_analysis}.py.

Final offline Debug build succeeded in **17 seconds**, 498 tasks/22 executed.
Latest APK: mobile/build/app/outputs/flutter-apk/app-debug.apk, also at
mobile/build/app/outputs/apk/debug/app-debug.apk, **225,571,223 bytes**. Build log:
mobile/build/reface-final-identities-build.log. The APK was not installed by this
task; the phone must be updated to use the final grouping behaviour.
