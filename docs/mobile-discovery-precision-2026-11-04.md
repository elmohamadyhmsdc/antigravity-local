# Mobile discovery and identity review — 2026-11-04

The discovery screens now use conservative pose and area matching and provide a visual comparison flow. Clothing colour similarity stays in discovery and cannot establish a person's identity in mobile Review or automatic body assignment.

## Matching changes

- Pose scoring combines weighted squared joint error with the worst arm, leg or torso error. Five face points cannot conceal a different limb. The default sigma is 0.22, with minimum similarity 0.65 and shared-point coverage 0.70 for search.
- Strict search is the default. Conflicting posture, arm and camera-direction tags are rejected. Named poses retain their tags after their reference is deleted. Old automatic category matches are re-evaluated; manual inclusions and exclusions stay intact.
- Group poses maximise the weakest member's match, preserving one-to-one assignment and allowing reflection only for the entire group. Member posture and orientation are also checked.
- Area embeddings must have the correct dimension, finite values and a non-zero norm; comparison uses normalised cosine similarity with a default minimum of 0.85. Search respects person scope.
- Area clusters enforce pairwise agreement rather than accepting a chain of neighbours. Rebuilding retains cluster IDs, custom names and assignments where membership still substantially overlaps. Explicitly excluded examples stay out of rebuilt groups. Cross-area bridge suggestions count distinct photos rather than repeated detections.
- The Python evaluation implementation and shared golden cases use the same scoring as Dart, including a bending case.

## Review changes

The phone ignores `appearance` and `event_outfit` identity proposals when applying automatic plans, storing review plans, listing questions and counting badges. This also hides stale clothing-only questions already stored on the phone. Face evidence and explicitly enabled region-review features remain available. Existing user-confirmed identity links are preserved; the existing grouping round clears obsolete automatic outfit links.

## UI changes

- Consistent discovery headings, searchable saved examples, equipment and area groups, preserved tab state, and direct reference-selection actions.
- Larger, scrollable results with a reference preview, visual similarity scores and side-by-side zoomable comparison.
- Skeleton and area-guide toggles. Overlays account for padded crop bounds, image dimensions and image fitting instead of stretching keypoints over the container.
- Larger inspection previews, clear region selection, visible removal actions in saved categories, and review/compare/remove actions for every area-group example.
- Layout verified on a 320 × 640 viewport with 1.8× text scaling.

## Verification and limits

Regression coverage includes changed limbs, a different member inside a six-person group, invalid descriptors, normalised area vectors, person scope, density chains, persistent exclusions, stale outfit questions, and preserved manual decisions. The affected Flutter suite passes all 186 tests. The Python golden-case runner passes all six tests. Flutter analysis reports no errors or warnings; two existing style information messages are in unrelated curation files. Phone-sized rendered previews are in [the review directory](reviews/discovery-2026-11-04/).

The previews use synthetic test skeletons and placeholder images. Similarity values are visual matching scores, not calibrated identity probabilities. Real-world precision still needs evaluation on representative labelled photos from the user's library. No device installation is performed by this change.
