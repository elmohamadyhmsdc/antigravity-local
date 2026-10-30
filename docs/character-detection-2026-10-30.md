# Cartoon and anime character detection — 2026-10-30

The user requested face-independent character detection on the PC with phone
support, then an in-place upgrade of the connected phone and an isolated test
using every image in Pictures/Anime Wallpaper, Pictures/background and Pictures/Pins.

## Behaviour and use

- Desktop Gallery has a **Characters** view and **Cartoon / anime sources** scan
  option. On the phone, open **People → the sparkle icon**, or the Characters
  link in Scan sources. Enable **Scan illustrated characters** after selecting
  illustrated albums. This mode replaces human face extraction for that scan.
  It starts disabled; it is not a classifier that automatically decides whether
  an arbitrary photograph is anime.
- The installed HumanArt YOLOX body detector supplies boxes. Character mode
  does not load or require the human face recognizer, and skips pose inference
  in a fresh character worker. No model or dependency downloads were made.
- `character-appearance@1` is a 160-float visual descriptor: head/hair colour,
  upper/lower clothing colour, spatial edge details and foreground silhouette.
  This is an appearance heuristic, not a trained character identity embedding
  or a model that supplies known character names.
- Similarity and its gates are implemented in Python and Dart. Auto assignment
  requires 0.93 similarity and a 0.06 lead over a competing identity. Different
  detected characters in the same image/frame cannot share an identity.
  Missing regions and different descriptor versions cannot supply a match.
- Identities and occurrences are separate from human people, 512-float face
  vectors, Reface source identities and the human grouping index. Groups can be
  named, and mistaken occurrences can be separated; rescanning preserves these
  assignments. The phone performs appearance matching locally.
- Phone schema **8** adds character identities/samples, media foreign keys and
  indexes. Crops and the scan setting are included in backups. A mode change
  invalidates completed scan versions for the next explicit album scan, without
  resuming paused work or rewriting an existing video request/checkpoint.
- **Test a character photo** opens a stateless one-photo check with boxes and
  character crops. It does not write library records. Photo/video API options,
  worker JSON IPC, video response import and scan progress carry character data.

## Isolated acceptance

All **328 phone images** were copied from the three folders into a temporary test
area. Three original illustrated samples were also generated using the built-in
imagegen tool, including rear views with no visible face and a different hair
colour with the same clothing. Generated samples and prompts remain at
`mobile/build/character-acceptance/samples/` and `generation-prompts.txt`.

| Source | Images decoded | Images with detections | Character detections |
| --- | ---: | ---: | ---: |
| Anime Wallpaper | 86 | 63 | 79 |
| background | 108 | 53 | 91 |
| Pins | 134 | 67 | 81 |
| Generated samples | 3 | 3 | 3 |
| Total | 331 | 186 | 254 |

The PC test used the real installed detector through an isolated authenticated
mobile API worker. Every file decoded successfully; no request failed. Total
PC batch time was **67.40 seconds**, including worker initialization and request
processing; this is not an inference-only benchmark.

A separate Android package, `com.antigravity.antigravity_mobile.characterqa`,
then exercised the same 331 inputs on the connected **Samsung A72**. It used a
fresh loopback-only HTTPS server on port 8447 over USB, fresh test credentials
and certificate pinning, the real HTTP DTOs, the production PhotoResultStore,
SQLCipher and an isolated in-memory database. Each result was stored twice to
check idempotency. The installed production app's data and pairing were never
opened by this QA package.

Phone results matched exactly: **331 processed, 254 detections in 186 images,
zero errors, zero same-frame identity conflicts, zero human face records**.
SQLCipher was present. Conservative matching produced **246 appearance groups**;
these are not verified distinct characters. The temporary QA app, server and USB
mapping were removed after the test. Copied personal input images and temporary
test credentials were removed; the original phone folders were not changed.

These are unlabelled detection counts, **not precision/recall or recognition
accuracy**. No-detection images need not all contain characters. The two red-haired
generated views scored **0.8768**, below the conservative auto-match threshold;
the red/green-haired pair scored **0**. Viewpoint changes, different clothing,
similar designs, partial bodies, busy backgrounds and non-human character shapes
still need review. There is no claim of reliable recognition of every anime or
cartoon character, and no automatic character-name classification.

Reports: `mobile/build/character-acceptance/results/report.json` and
`mobile/build/character-acceptance/device-server/phone-report.json`.

## Verification and delivery

- **167 affected Flutter tests passed**; full Flutter analyzer: **no issues**.
  Coverage includes isolated test-photo UI, naming/separating, persistence,
  rescan idempotency, same-frame conflicts, v1-v7 upgrades, scan/video import,
  human gallery regressions, backups and contract fixtures.
- Python: character regressions **12**, shared analysis **7**, worker/video
  **11**, API contract **28**, statelessness **5**, gallery **33**, desktop UI
  **9**, all passed. OpenAPI, **33 fixtures** and negative schema cases passed.
  Tests requiring the desktop database ran from an isolated working directory.
- Initial API shape failures were resolved by updating default/fake capability
  and response fixtures. An old desktop-view expectation now includes Characters.
  The photo UI test scrolls to the summary below its portrait preview. Initial
  sandbox/native access failures were rerun successfully outside the sandbox.
  Existing unrelated Restyle failures were not changed or rerun.
- Offline QA Debug and signed production Release builds succeeded. The release
  package was checked as the ordinary app, version **1.1.0 (2)**, with the same
  signing certificate as the installed release. It was installed with `adb install
  -r`, without uninstalling or clearing the production app. Package manager
  confirmed version 1.1.0 / code 2 afterward. The real encrypted library was not
  inspected; real-library migration will occur on its next normal launch.
- Delivered APK: `mobile/build/character-detection-1.1.0.apk`, **46,277,863 bytes**,
  SHA-256 `40a80328c73286ca91d970eb5d78ac824b6faae867452aa8b62039ce77765055`.
  Dart AOT targets the connected arm64 phone. Production app ID remains unchanged.
- The original PC server was already **failed/stopped** and contained **3 job
  directories and 3 blob files**. It was not started, wiped, replaced or restarted
  for this test. Its saved work, TLS/pairing and the phone's existing scan/queue
  state were preserved. The updated backend code takes effect on its next start.

Reproduction tools are opt-in: `the app/test_character_acceptance.py` for explicitly
selected local folders; `the app/character_device_server.py` plus
`mobile/tools/character_device_acceptance.dart` for a separately packaged phone
test. The latter must be built with `-PcharacterAcceptance=true` and a temporary
`CHARACTER_QA_CONFIG` define. These test routes are absent from production servers.
