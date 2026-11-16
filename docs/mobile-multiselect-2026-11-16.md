# Mobile collection actions — 2026-11-16

The app's actionable collections now offer a visible **Select multiple** control and a contextual sheet on long press. Selecting an item only changes selection. The selection bar shows a count, close, select all / loaded items, invert and clear; **Actions (count)** opens the available batch operations. Existing individual controls remain available outside selection.

## Screen audit and implemented actions

| Collection / entry points | Useful batch actions |
| --- | --- |
| Gallery photos, videos and album contents | Share originals in one request; queue chosen files for scanning |
| Gallery folders | Scan chosen folders together |
| Filtered Gallery and identity-group media | Shared media actions, scoped to loaded matching items |
| Person / Character photo and video albums | Share, queue scanning, remember “not this identity” for selected media; the existing evidence/correction sheet also offers Select multiple |
| People / Characters, including identity-group member views | Existing multi-identity actions retained: merge, group membership, flags, export and grouping removal |
| Faces and Unsorted | Existing face selection, assignment/move/rejection, export and detection actions retained |
| Saved identity groups | Remove selected group labels while preserving people and files |
| Person / Character Bodies tab | Assign/move with one destination picker, reject the current owner, share crops, hide detections |
| Person / Character saved source identities | Remove selected source sets without deleting identity records or assignments |
| Person / Character models, datasets, results and tasks | Share models; export datasets; shared result and task actions |
| Explore → All bodies, pose/outfit/colour/similarity results | Assign bodies with one picker, share crops, hide detections |
| Explore → Saved poses / outfits | Refresh selected match groups; delete saved labels |
| Saved pose / outfit members | Remove chosen matches; shared body actions |
| Explore → Group poses | Media actions for examples/results; remove selected saved labels or selected result memberships |
| Explore → Equipment | Confirm, apply one shared label or reject the equipment in chosen photos; the same actions on individual objects in a photo |
| Explore → Areas | Assign selected regional groups with one picker; share their unique body crops |
| Explore → Marks | Share/delete selected saved marks; accept/reject selected search hits |
| Explore → Activities | Delete selected saved activities; remove selected examples; accept/reject selected suggested matches |
| Results and Studio results | Explicit add/remove favourite state, one share request, save to Gallery, delete selected private outputs |
| Activity active tasks, history and legacy Jobs list | Pause compatible tasks, resume/retry compatible tasks, remove selected task records while retaining saved results |
| Activity failed scan files | Queue selected failed files for retry or skip selected currently failed files |
| LoRA library | Export selected datasets and model files together |
| Dataset editor | Include/exclude selected images independently of selection; share chosen images; captions preserved |
| Smart training curation | Exclude selected candidates from the prepared training set |
| Detailed Review duplicates | Mark selected identity pairs as different; identity merges still require their normal review |
| Detailed Review doubtful assignments and body links | Confirm/remove chosen batches; accept/reject chosen body links |
| Photo / video Inspector | Select mixed detection types and explicitly hide false detections; other detections and originals remain |

Face-match and new-group review already use per-face checkboxes. Those decisions retain the checked/unchecked exclusion semantics implemented in the preceding Review UX change. Quick Review remains a focused decision about one question. Training source pickers, scan source albums, identity editors, organize previews and participant pickers retain their existing multiple-choice controls. Home / Explore / Review hubs and insights are navigation or summaries; Settings, pairing, backup, storage maintenance, comparison/editing targets and generation configuration retain their appropriate individual controls.

## Behaviour and boundaries

- One input or confirmation applies to the selected snapshot. Sharing sends one request containing all selected files.
- Pending actions paint a spinner and action label, disable repeat execution and consume Back until completion. Cancelled input leaves selection intact. Back exits ordinary selection before leaving the screen.
- Database-only grouped updates use transactions. External operations that can partially succeed keep only failed items selected, report the partial failure and refresh completed items.
- Selection follows stable IDs, prunes items leaving a filtered collection, and distinguishes paginated **loaded items** from the entire phone library. Existing 400-body, 200-group-photo and 50-failure display caps remain explicit through loaded-item wording.
- Background database refreshes in the paginated media grid are deferred during selection, then applied when selection ends.
- Moving bodies detaches a wrong face/body association and remembers the old owner exclusion while keeping that face's own identity. Album corrections affect only the album owner, including aliased detections, and preserve other identities in a shared photo.
- Destructive private-result actions explain when their associated dataset/model is also removed. Group-label, task-record and source-set removal explain the narrower scope. No bulk merge bypasses identity review.

## Validation environment

The installed Flutter SDK changed externally from 3.44 / Dart 3.12 to 3.50 / Dart 3.14 during this work. The root app dependency manifests and Android build configuration are preserved. Validation uses an ignored copy at `mobile/.dart_tool/multiselect-validation`, with an offline SDK-compatible lockfile and copied contract fixtures. Flutter 3.50 also emits new Material import deprecation information for the existing app imports.

Final test counts, analyzer result and build outcome are recorded in the latest section of `ANTIGRAVITY_HANDOFF.md`. No phone installation or real-library performance acceptance is implied by widget tests or a debug build.
