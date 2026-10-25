# Reface improvements — 2026-10-25

Implemented the seven correctness findings from the [review](reviews/2026-10-25-reface-review.md), together with practical identity, preview and evaluation improvements.

Later requests added the [unified media picker, visual video trimmer and verified
stateless workflow](mobile-stateless-workflow-2026-10-25.md), plus [faster resumable
transfers](mobile-transfer-performance-2026-10-25.md). Latest full verification:
**395 Flutter tests passed**, analyzer **no issues**; the tables below record the
earlier engine-focused verification.

## Changed behaviour

- Encoder writes propagate errors, reject partial writes and have a bounded timeout. Encoder completion checks its exit status, retains a bounded error tail and releases processes, pipes and threads on failure. Odd frame dimensions are padded for H.264. Rendered parts and final videos are decoded and checked against the requested frame count and frame rate.
- Concatenation uses exact part durations derived from decoded frames, preserving fractional rates even for very short resumed segments. Parts remain available until the final video passes validation. Resumes warm up up to 12 preceding frames to rebuild temporal state.
- Tracks use global assignment with identity, predicted motion and box overlap. Short detection gaps retain tracks. Scene cuts reset tracking/compositing state, and track IDs are not reused across cuts. Selected identities are verified on every frame; ambiguous reference/photo-box matches are rejected rather than guessed.
- The current frame's protected mask limits temporal smoothing. Valid full occlusion skips a face. Invalid masks fail the face instead of bypassing protection. Full-frame swapper compatibility is recropped and passed through the protected compositor, preserving faces already processed. Original crops always come from the original frame.
- Outcomes count actual swapped/skipped/failed/degraded faces. Photos can report partial success accurately; complete no-op results fail. Video diagnostics stay bounded. Effective model names, masking availability, identity statistics and warnings accompany results.
- V3 source identity filtering now rejects outliers and duplicates across desktop and mobile. Real faces anchor mixed identities. Generated portraits are tagged (including desktop faceset save/load), downweighted, and together contribute at most one quarter of real-face weight when real sources are available.
- Legacy phone controls now configure its enhancement and occlusion components. Unsupported parser/realism controls are hidden, and unsupported explicit API options are rejected. DFM restoration controls are hidden because restoration is bypassed for that engine.
- Phone video jobs can select people using a reference photo. The API accepts reference embeddings and selected indices for V3/DFM video; photo selection continues to use boxes. A new deterministic golden fixture covers selected-person previews.
- Phone and desktop offer preview rendering with the current settings. Videos render at most three seconds starting at the chosen trim start. Phone preview navigation retains the form so the user can return and adjust settings. Job details show effective engines and outcome counts.
- The evaluation harness reports coverage, failure, skip and fallback rates alongside identity/sharpness/flicker/speed. Ranking prefers configurations with adequate coverage and few failed faces. Default photo splitting groups transitively near-duplicate images together; an explicit local case manifest supports session-separated build/held-out sets and labelled scenario clips. Identical inputs across an explicit split are rejected.

## Using the phone changes

1. Choose the target video. To replace selected people, choose a reference photo and tick their faces. The reference is used to recognize people in the video; the source identity is chosen separately in the next step. Legacy video still replaces all detected faces.
2. Choose the source person and source faces, then quality options. Identity strength is available for V3. Restoration can be disabled for comparison.
3. In Review, choose **Render a preview**. Open the private result, then return to the retained form to change settings or submit the full job.
4. Job details show successful, skipped and failed face counts, the actual swapper/restorer, selected identity quality and any degradation warnings.

## Verified results

| Check | Result |
|---|---|
| Flutter suite | **377 passed** |
| Flutter analyzer | **No issues** |
| New correctness regressions: test_reface_quality.py | **22 passed** |
| Compositor/helpers: test_compositor.py | **52 passed** |
| Legacy regressions: test_reface_v2.py | **41 passed** |
| Identity builder: test_identity_builder.py | **7 passed** |
| Desktop LoRA identity/persistence: test_lora_identity.py | **7 passed** |
| Studio API/adapters: test_mobile_studio.py | **13 passed** |
| API contract/lifecycle: test_mobile_api_contract.py | **28 passed** |
| Statelessness: test_mobile_stateless.py | **5 passed** |
| OpenAPI, 30 golden fixtures and negative cases | **All passed** |
| Python compilation of changed modules | **Passed** |
| Android Debug APK, Gradle offline assembleDebug | **Built successfully** |
| Real GPU API image round trip | **Passed**, analysis → V3 → verified PNG → ACK/purge |
| Real GPU selected-person photo | **Passed**, one swap; unselected person/background remained bit-identical in the PNG |
| Real GPU pause/resume video | **Passed**, 3 + 6 frames → 9 decoded frames at **29.97002997 fps** |

The short-segment GPU check initially exposed a container-duration rounding issue (29.8805 vs 29.9700 fps); exact concat durations fixed it. A permanent CPU regression now covers it.

The new Debug APK is [mobile/build/app/outputs/flutter-apk/app-debug.apk](../mobile/build/app/outputs/flutter-apk/app-debug.apk), **225,524,452 bytes**. The offline Gradle build succeeded in 2m 11s (498 tasks; 26 executed, 472 up-to-date). It has not been installed on a phone. Build log: mobile/build/reface-debug-build.log.

Logs and the GPU sample report are under mobile/build/reface-*.log and mobile/build/reface-acceptance/gpu-report.json. The opt-in GPU regression is the app/test_reface_gpu_acceptance.py; it accepts local --source and --target photos and writes only to its output folder.

Initial sandbox runs could not write OpenCV/FFmpeg files under the sandbox Temp directory or create asyncio's local socketpair; CPU media tests were rerun using a project-local temporary directory, and API/Flutter checks ran with the access needed by the existing runtimes. These were environment restrictions, not suppressed test failures. No dependencies, model weights or CUDA configuration were installed or changed. The eight listed Python suites total **175 passing tests**.

## Evaluation case manifest

Pass --cases path/to/cases.json to eval_reface.py. The JSON contains:

- people: an object keyed by identity name. Each entry has build and held_out arrays of local photo paths, chosen from different source sessions.
- clips: an array of objects with name, scenario, path, start (seconds, default 0), and seconds (maximum 30).

Relative paths resolve against the manifest folder. Include occlusion, profile, low-light, small-face, crossing-person and scene-cut cases. No network fetching is performed by this loader.

## Scope of the evidence

The GPU checks use copies of the existing local DeepFaceLab sample frames. They verify execution, selection and video integrity; they do not establish broad visual quality, long-video performance, arbitrary phone acceptance or universally optimal model settings. No real custom DFM model was available for an inference acceptance run. The historical HyperSwap/GPEN defaults were retained. LoRA inpainting refinement and training a new per-person DFM remain separate model experiments requiring identity-specific inputs and an A/B evaluation; they were not enabled as unmeasured defaults. No phone application, running server or real library/queue was altered. Existing recorded Restyle test failures are outside this change and were not relabelled or rerun.
