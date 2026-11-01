# Visual poses, group actions and equipment — 2026-11-01

The mobile Bodies screen now offers visual single-person pose choices, named
multi-person actions and editable automatic equipment detection.

## Using it

- **Poses** shows named groups first, with their example crop. The illustrated
  Posture / Arms / Camera direction choices show each pose and its body count.
  Naming a pose shows the reference crop before the name is entered.
- **Group poses** lists photos with two to six detected people. Choose an example,
  find similar group poses, or give the pose/action a name. Results retain the
  reference photo or its skeleton, and can be filtered by detected equipment.
  Saved groups support removing a result and deleting the category.
- **Equipment** filters photos by tool name. Open a photo to detect equipment,
  correct its label, change its associated person, remove a false detection, or
  add missed equipment manually. An ambiguous association stays shared/unassigned.
  Manual additions have no invented object box.
- Body action sheets and the photo viewer provide the same group/equipment entry
  points. Area searches distinguish Chest from Lower body, show the reference
  and a diagram of the selected area. Existing experimental area clustering
  remains controlled by its existing switch.

## How matching works

Group descriptors use all detected people in the photo, with a common hip-centred
origin and median torso scale. This preserves spacing, overlap and relative size.
A one-to-one assignment handles changed detection order; only mirroring the whole
group is allowed. Person identity is not a matching input. Photos with different
person counts do not match. At least eight visible joints, shoulders and hips
are required for every member. The entire detected group is compared; selecting
only a pair from a larger crowd is not implemented. Video groups are excluded
because tracked poses may come from different frames.

The action name is supplied by the user; no semantic action recognition or
physical-contact classifier is claimed. The initial group similarity threshold
is 0.65, pending evaluation on a labelled library. Candidate reads are batched
and ranking runs in an isolate. No large-library/device benchmark was performed.

Group categories use `pose_categories.kind = group_pose` with a versioned JSON
descriptor in `exemplar_feature`; ordinary single-body rescoring skips them.
The copied descriptor survives deletion of the reference body. Group-result
removals use rejected body-match rows. Matching is recomputed when a saved group
is opened, so new photos can appear without a separate rescore job.

## Equipment recognition

`POST /v1/analyze/equipment` runs Florence's `<OD>` task in a separate, hidden
`venv_ai` process. The existing local Florence weights/code are reused. No new
model, package or CUDA configuration was installed. A different compatible local
model can be selected through `AG_EQUIPMENT_MODEL`. Object labels are normalized
against the equipment vocabulary in `equipment_detection.py`. The task and
bounding-box format follow the [Microsoft Florence model documentation](https://huggingface.co/microsoft/Florence-2-base).

Wrist proximity and object/body overlap suggest an associated person. These
suggestions do not establish that the object is in use. Ambiguous ownership
remains unassigned. No numerical model confidence is invented. Images travel
through anonymous pipes; this endpoint does not write input photos or results.
Authentication, compute admission, upload limits, geometry validation, worker
timeout and retryable errors are covered by the API path.

Recognition runs after an idle scan pass when the PC advertises the optional
`equipment` capability. Existing photos can also be processed from Equipment,
and a single photo can be processed explicitly. Automatic recognition is skipped
for illustrated albums and videos. Corrected/rejected objects survive repeated
detection, including small box movements. Rescanning a photo clears automatic
suggestions and its detection checkpoint while retaining corrections/removals.

Schema v17 adds `equipment_objects` and `equipment_photos` without rewriting
library records or queuing rescans. Both tables travel in backups in foreign-key
order. Deleting a photo removes its equipment records; deleting a body leaves
the object unassigned.

## Verification

- **124 focused Flutter tests passed**: group geometry/persistence, equipment
  corrections, v16→v17 upgrade, group/equipment UI, 320dp/180% text layout,
  existing bodies/area workflows, categories/index/matching, database/backup and
  shared wire fixtures.
- **17 photo-result-store tests passed**, including invalidating automatic
  equipment results while preserving user corrections after a rescan.
- The three new UI workflows were rendered with cached fonts and inspected.
  Preview PNGs are in `mobile/build/body-pose-previews/` (synthetic fixture data;
  absent originals intentionally exercise skeleton fallbacks).
- Focused Flutter analysis: **no issues**. Generated Drift/localization files
  and the shared equipment response fixture are included.
- Python: **4 equipment tests**, **31 API contract tests**, **5 stateless tests**
  passed; OpenAPI/fixture validation passed. The actual capability probe reports
  the installed model. Python compilation passed.
- A real CPU Florence worker completed on the repository's `full_body.png`
  fixture and returned no equipment. This verifies loading, generation and the
  response path; it does **not** measure equipment detection accuracy. Precision,
  recall, association quality and group thresholds still require real examples.
- Debug APK build succeeded (51.8s): `mobile/build/app/outputs/flutter-apk/app-debug.apk`.
- No physical phone acceptance, live API restart, dependency installation or
  GPU inference was performed. A new APK and a server restart are needed to use
  the new UI and equipment endpoint on a phone.
