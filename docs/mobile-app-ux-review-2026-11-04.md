# Mobile application UI/UX review — 2026-11-04

The application now groups secondary actions by task, exposes working Studio library categories, and preserves predictable discovery and review navigation. This pass follows the [discovery and identity precision changes](mobile-discovery-precision-2026-11-04.md).

## Walkthrough scope

Rendered the actual Flutter widgets with an in-memory library, synthetic images, two people, a result, a model and a dataset. Each of these 24 destinations was checked at the regular phone size and at 320 × 640 with 1.8× text scaling:

- Gallery, People, Explore and Studio.
- Settings, Library & scanning, Privacy, Storage, Backup and Background execution.
- Review hub, detailed Review and Activity.
- Person details, Poses, Outfits, Areas, Equipment and Group poses.
- Reface, Restyle, Train, Generate and the original photo viewer.

Also exercised Studio Results/Models/Datasets, the person's action menu, discovery tab selection, review queue navigation and Back, and exclusion/Undo from the original photo.

The [before](reviews/app-ux-2026-11-04/before/) and [after](reviews/app-ux-2026-11-04/after/) directories contain the rendered evidence. The baseline covers the first 12 destinations; the final walkthrough covers all 24. Synthetic placeholders make these layout and interaction checks reproducible; they do not measure photographic detection accuracy.

## Findings fixed

| Area | Observed problem | Resulting behavior |
| --- | --- | --- |
| Context menus | Long, undifferentiated action lists; the close control could scroll away. | Common actions stay visible. Named sections group identity corrections, search, creation, organization/export and removal. Sheet headers and close controls stay in place while content scrolls. |
| Detection actions | Some menu options had no viewer implementation. False detections had no working exclusion action in this menu. | Each detection exposes supported actions. Exclusion targets the correct entity type and offers Undo. A body action cannot accidentally delete a face with the same database ID. |
| Excluded bodies | Hidden false detections could still appear in pose, colour, outfit, group or area discovery. | Discovery queries and shared previews exclude hidden bodies; area clustering and group composition also respect the correction. Undo restores eligibility. |
| Studio library | Category chips changed selection without showing the corresponding collection. Several links led to the same hub. | Results, Models and Datasets display their actual collections and open their own detail destinations. Empty states provide relevant next actions. |
| Results and accessibility | Fixed controls consumed the viewport and overflowed with large text. | Results use one scrolling surface. Filters remain reachable; expanded text can scroll. |
| Explore | Duplicate app bars, an ineffective owner filter, and sparse singleton grid rows. | One app bar, no ineffective filter, a compact secondary list and responsive natural-height rows. Cover-image taps open the destination. |
| Areas navigation | Opening Areas while its optional grouping was off could land on Equipment. | The Areas tab remains available with an explanation and an explicit enable action. Opening it does not enable grouping automatically. |
| Review | Queue cards opened the wrong detailed tab or replaced the hub state. | New people, duplicates and body identity links select their own tabs. Back returns to the hub. Clothing-only identity questions stay suppressed. |
| Library settings | Sources, scan controls, grouping, file organization and maintenance formed one long list. | Five named sections organize the controls; albums open initially when none are selected. The scan action stays reachable at the bottom. |
| Settings hub | Duplicate routes and a hardcoded version label. | One library/scanning entry, a clear Activity destination, and removal of the inaccurate hardcoded version. |
| Person details | App-bar actions crowded the person's name on narrow displays. | Media activities live in the person's action menu; existing tabs remain available. |
| Activity | Paused jobs disappeared from both Now and History; completed scans appeared active. | Paused jobs remain in Now with Resume. Completed scans no longer appear active. |
| Storage and empty states | Long labels and large text overflowed horizontally or vertically. | Labels wrap within the available width; empty states scroll when needed. |

## Selected evidence

- [Explore](reviews/app-ux-2026-11-04/after/03-explore.png) and [large text](reviews/app-ux-2026-11-04/after/03-explore-large-text.png).
- [Studio results](reviews/app-ux-2026-11-04/after/04b-studio-library.png), [models](reviews/app-ux-2026-11-04/after/04c-studio-models.png), [datasets](reviews/app-ux-2026-11-04/after/04d-studio-datasets.png).
- [Library sections](reviews/app-ux-2026-11-04/after/06-library-settings.png).
- [Person action menu](reviews/app-ux-2026-11-04/after/12b-person-actions.png).
- [Storage with large text](reviews/app-ux-2026-11-04/after/19-storage-large-text.png).
- [Exclusion with Undo](reviews/app-ux-2026-11-04/after/25-exclude-feedback.png).

## Verification

- The final focused regression run passes 68 tests, including all 24 rendered destinations, navigation/exclusion interactions, saved-area naming and immediate removal of groups with no visible members. Existing action tests now open the relevant category before choosing an action.
- Static analysis reports no errors or warnings. Two existing informational brace-style findings remain in `auto_dataset_curator.dart:221` and `curation_review_screen.dart:93`.
- The final full-suite run passed 1,136 tests, skipped seven and exposed three failures. One was an empty saved-area fixture: it now seeds visible members, and its rename checks pass in the final focused run. Earlier outdated expectations affected by the new menus or clothing-only identity suppression were also corrected and pass.
- The two remaining failures are scan-engine pause tests, also reproduced in an isolated run (33 pass, two fail). They expect the current photo to finish before pausing, while the unchanged engine races the request against its pause signal. Neither the engine nor those tests was changed in this UI pass. The full suite is therefore not entirely green.

No Android device was connected during this review, and no app was installed. Device gestures, system permission sheets, keyboard behavior on hardware, and precision on a representative labelled photo library still require a device/real-data check.
