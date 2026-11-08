# Multi-evidence identity resolution for the mobile gallery

Date: 2026-11-05
Status: proposed design following source audit; not implemented or calibrated.

## Objective

Use the visual information already extracted from photos and videos to reduce identity fragmentation, incorrect merges, and incorrect face/body attribution. Every field needs an explicit role: identification, association, candidate retrieval, comparability, quality, context, exclusion, or provenance. Merely increasing the number of similarity scores is not success.

Preserve the phone as the source of truth and the PC as stateless compute. Extend existing grouping, review, corrections, and backup systems. A graph of evidence can be stored in SQLite; a graph database or an LLM identity judge is unnecessary.

## Verified current source

- mobile/lib/data/db/tables.dart: face vectors, quality components, pose angles and landmarks; body boxes, 17 scored keypoints, extent, appearance, weak-face quality; regional DINOv2 vectors and morphology; per-occurrence geometry and outlines; timestamps and tracks; clothing tags; user-marked patches; equipment; confirmations, exclusions, ownership and distinct pairs.
- mobile/lib/domain/grouping/grouping_inputs.dart already builds a robust face model with outlier trimming and diverse exemplars. This is a starting point, not a missing feature.
- mobile/lib/data/api/dtos/grouping.dart and the app/grouping_core.py send/use a much narrower body representation: media/frame, owner, outfit descriptor, weak face, time and rejections. Richer evidence is not jointly consumed there.
- mobile/lib/domain/grouping/identity_evidence.dart deliberately excludes clothing-only links from automatic identity assignment/review. Preserve that rule in the new policy.
- mobile/lib/domain/scan/video_tracks.dart uses greedy matching and bounded stored views; a high identity similarity can qualify without the temporal proximity test.
- mobile/lib/domain/grouping/plan_applier.dart propagates a sole assigned person through a face track. Track reliability and decision lineage need to participate in that propagation.
- mobile/lib/domain/pose/exposed_matching.dart already offers regional similarity, optional gated clusters, consistency checks, and bridge suggestions. Regional appearance is not a validated biometric probability.
- mobile/lib/domain/marks/body_marks.dart already searches geometrically aligned, mirror-aware patches; results are suggestions. General identity fusion is additional work.
- mobile/lib/domain/pose/pose_descriptor.dart already handles shared visible points and comparability. Pose resemblance is not an identity measurement.
- mobile/lib/domain/pose/equipment_library.dart stores labels, boxes and body association; its detection pass currently targets photos. It does not provide a cross-file object-instance identity vector.
- the app/body_embeddings.py produces regional vectors and heuristic morphology. Its dark-spot detector is not a verified mole recognizer, and its color/shape measurements are not established identity evidence. OSNet is explicitly not integrated in this module.
- FaceBodyPair in analyze.dart carries an association score. The Bodies schema has a face reference but no dedicated face/body association-evidence record. Audit storage before introducing propagation confidence.

These findings describe source, not actual feature coverage or accuracy on the user's phone. Nullable fields and optional passes mean not every item contains every signal.

## Evidence inventory and intended use

| Existing information | Intended use | Conditions and limits |
| --- | --- | --- |
| Face embedding and model ID | Retrieve people and compare identity against diverse trusted exemplars | Same compatible model/version; valid finite nonzero vector; avoid treating auto-assigned faces as ground truth |
| Face size, sharpness, detection score, embedding norm, yaw/pitch/roll | Select usable exemplars and condition the reliability of a face comparison | They are quality/context inputs, not independent votes for identity; the aggregate quality score overlaps these fields |
| Five face landmarks and face/body boxes | Align crops and score face-to-body association | Normalize coordinate transforms, rotation and source dimensions; ambiguity remains unknown |
| Body keypoints and per-point confidence | Align comparable body parts, determine visibility and track motion | Restore pixel aspect ratio before geometry; same pose does not mean same person |
| Body extent and detection score | Gate partial/full-body comparisons and association confidence | A hidden or cropped part is missing evidence, not disagreement |
| Outlines | Reduce background contamination where reliable; assess overlap/visible support | Verify whether outline is measured or a geometric fallback; never assume every outline is a precise segmentation mask |
| Clothing histogram, garment tags, outfit categories | Retrieve contextual candidates and describe an event-specific appearance | Related clothing signals are one family; same clothing alone cannot establish identity, changed clothing cannot disprove it |
| Regional DINOv2 embeddings | Region-specific visual candidate retrieval and review ranking | Compare the same visible region using compatible extraction versions; qualify accuracy before any identity use |
| Morphology, color and local dark spots | Experimental comparability/quality checks or review ranking | Must demonstrate incremental value; lighting, projection, crop and compression confound measurements; no standalone automatic identity or hard exclusion |
| User-marked distinctive patch and geometric match result | Additional candidate evidence with anatomical location and mirroring | Keep inlier statistics, spatial support and visibility; no absent-mark penalty if the location is obscured |
| Frame/time, track and source media | Establish continuous appearances and independent observations | Split at cuts/gaps/ambiguity; sparse sampling cannot establish uninterrupted movement |
| taken_at and duration | Propose event context and scheduling | Current taken_at is MediaStore creation time, not guaranteed capture time; edits/imports can invalidate event assumptions |
| Equipment labels, boxes and body association | Context and candidate prioritization | Same label is not the same physical object; proximity is not ownership; current photo-only timing limits remain explicit |
| Co-occurrence and geometry | Check competing assignments and physical consistency | Use every media_detections occurrence, not only the canonical face row; handle duplicate detections, reflections, screens and collages before deriving exclusions |
| Confirmations, manual links, rejections, distinct pairs, locks, hidden/ownership settings | Trusted anchors and application constraints | Manual corrections outrank automatic proposals; new evidence cannot silently undo exclusions |
| Human/character kind and character descriptors | Separate human and illustrated identity profiles | No cross-model vector comparison or cross-kind automatic merging; geometric/context helpers may be shared |
| IDs, asset versions, crop paths, model/scan versions, backups | Trace origin, invalidate caches and reconstruct explanations | Paths, names, folder/group membership and generated results do not establish visual identity |

Generated/edited images must not multiply confidence in their own source identity. Where derivation metadata exists, retain it and group derivatives with their original evidence source. Otherwise provenance is unknown rather than assumed independent.

GPS, scene embeddings, generic object-instance vectors, reliable capture-time provenance, scene-cut scores, and full-body OSNet identity vectors are not assumed available. These would be separate additions if evaluation justifies them.

## Data model: distinguish observation, appearance, and identity

1. Observation: one detected face/body/part in a particular media occurrence and frame.
2. Appearance: a bounded continuous tracklet in a video or a supported short photo sequence. It has its own reliability and boundaries.
3. Identity: a person/character linked to one or more appearances by validated evidence.
4. Context: event, outfit, co-occurring items and temporal neighborhood. Context is connected to appearances; it does not become a permanent trait of a person.

A person profile retains multiple trusted face exemplars by view and independent source. Event-specific body/outfit templates stay separate. Useful confirmed marks retain anatomical location, visibility and source.

Candidate evidence must identify the exact observation and feature version, not merely a face/body database row. Existing deduplication can make multiple observations point to one stored exemplar.

Proposed records, adapted to actual schema during implementation:

- observations/observation_features: occurrence IDs; source media/version; frame/time; coordinate transform; feature family, model and preprocessing versions; source region; quality/visibility; validity and missing reason.
- appearance_tracks/appearance_members: source scope, boundaries, continuity/association evidence and ambiguous transitions.
- identity_evidence: endpoints; relationship type; raw comparison; quality; dependency family; exact supporting observation IDs; calibration version; state and explanation.
- identity_decisions/decision_support: candidate identity; competing identity margin; decision state; library snapshot revision; supporting edges; origin (manual/automatic); reversible application state.

Missing states distinguish not extracted, model unavailable, not visible, invalid, and genuinely observed mismatch. Do not convert null into a zero similarity or invent missing morphology.

## Decision pipeline

### 1. Recover trustworthy input

Validate vectors, model compatibility, coordinate conventions and provenance. Build occurrence-level links from media_detections. Recover existing features without rescanning.

Make additional requests only for a named missing feature; do not rerun all models against every original. Preserve scan, correction and backup semantics.

### 2. Build local appearance tracks

Use global one-to-one assignment within each frame with an explicit unmatched option, candidate gating and deterministic tie handling. Combining face evidence, motion and body association is preferable to taking the first best pair.

Allow one person to have several separate appearances in one video. Track re-identification is a separate hypothesis, not unlimited continuation. Cut detection and dense local sampling are targeted additions where existing sparse observations cannot support continuity.

Check identity consistency across a track before propagation. A strong contradictory face or ambiguous crossing splits or quarantines the affected segment. One erroneous anchor must not relabel an entire video.

### 3. Retrieve a union of candidates

Retrieve independently from compatible face exemplars, regional appearance, confirmed marks, local tracks and event context. Take a bounded union so a faceless query is not discarded by a face-only first stage.

Keep source-specific indices and rerank exactly. Choose approximate search only after measuring scale/latency; do not build an all-pairs matrix for the whole library.

Context-only retrieval may broaden candidates, but cannot make a candidate identity eligible for automatic assignment by itself.

### 4. Compare usable evidence

For each candidate compute separate comparisons, availability, visibility and provenance. Compare shared visible parts in compatible views. Distinguish an obscured arm from a visibly different mark.

All normalized geometry must use the correct image dimensions and transforms. A stored 2D ratio does not imply an invariant physical body measurement.

Pool repeated observations within a track/source family. Duplicate exports and nearby frames have limited additional weight. Cap influence from correlated families: face aggregate quality and its components; outfit histogram/tags/appearance; patch vector and color statistics from that same crop.

### 5. Fuse with calibrated uncertainty

Use a small interpretable ranker/calibrator as the initial candidate (regularized logistic model or empirical score tables, chosen by validation). Inputs include usable comparison scores, quality, missingness, independent support, context and contradictions.

Do not concatenate incompatible embeddings, average arbitrary cosine scores, multiply independent probabilities for dependent cues, or call a similarity of 0.93 a 93% identity probability.

Calibrate separately where supported: human/character, face-present/faceless, same-event/cross-event, and comparable visibility patterns. Sparse or out-of-domain strata remain review-only.

Until sufficient independent labels exist, retain deterministic conservative rules and expose scores as rankings. Context and visual-region resemblance alone must remain unable to trigger automatic person identity.

### 6. Resolve consistency across the evidence graph

Use manual constraints and trustworthy co-occurrence to rule out incompatible assignments. Require group-level consistency; A resembles B and B resembles C is insufficient for automatic A/B/C merging.

Every automatic decision must trace to trusted observations or independently validated identity support. Derived decisions cannot count as fresh independent anchors for their own ancestors. Removing an anchor invalidates dependent decisions.

Do not turn every weak disagreement into a hard exclusion. Distinguish an explicit user rejection from a low-quality face or projection-distorted body ratio.

Do not create permanent person identities from only unvalidated body similarity. Keep anonymous appearance groups available for later evidence or review.

### 7. Apply atomically and explain

Return a versioned plan with supporting and opposing evidence. Recheck the current phone revision, entity existence, kind/model, hidden/ownership flags, locks, all rejections/distinct constraints and track validity in the application transaction.

Use accepted / suggested / unresolved / blocked states. A suggestion includes a concise reason and exact crops/frames for review. No displayed accuracy percentage without matching calibration.

Undo and reassignment follow dependency links and recompute only affected records. Persist decisions and provenance through backup and sidecar round trips; rebuilding features must not erase manual decisions.

### 8. Ask for the most informative next observation

For an unresolved candidate, estimate which existing or additional observation is likely to distinguish the leading identities:

- another stored view in the same track;
- a short extra sample around the last clear face before an occlusion;
- a higher-resolution crop of a currently usable region;
- a single human question that resolves several dependent appearances.

Bound GPU time, bytes, retries and total requests. Resume incrementally and record failed/unavailable evidence. Unknown remains a legitimate outcome.

## Example

A clear face anchors one appearance. Later frames show only the back. Reliable face-to-body association and a short unambiguous track connect those observations.

Another photo shares the outfit and time: retrieve it as a candidate. A compatible clear face or a validated additional identity cue can support linking; outfit/context alone produces a review suggestion.

A different person wears the same outfit in the same scene: competing face evidence and distinct appearances prevent clothing matches from merging them.

A distant image shows only a similar body region: rank visually related candidates, retain uncertainty, and seek a trustworthy bridge. Do not label the person merely because the patch vector is similar.

## Evaluation and rollout

### Baseline and truth

Use confirmed/reviewed labels for evaluation, not existing automatic assignments treated as truth. Build difficult negatives (similar faces, uniforms, shared equipment) and positives across views, time, lighting and clothing.

Split by source event/video and derivative family; neighboring frames and duplicate exports must not cross train/test boundaries. Add unseen-identity evaluation where the sample size permits. User-facing review prioritization must not replace a representative held-out benchmark.

Measure:
- wrong assignments and wrong merges;
- fragmentation and missed matches;
- body attribution precision and coverage;
- track identity switches;
- calibration by modality availability;
- review questions per resolved identity;
- latency, memory, transfer size and additional inference cost.

Report confidence intervals and sample counts. An accuracy claim on a few correlated images is not evidence of deployment quality.

### Ablation

Compare the baseline with: occurrence/provenance fixes; improved tracks; quality-conditioned face profile; part visibility; marks; regional descriptors; context; then combined fusion. Add one family at a time and test its removal from the final system.

Only promote a cue if it increases useful coverage without unacceptable false-link regression. Some extracted fields may be most valuable for deciding when not to compare.

### Delivery sequence

1. Evidence inventory/coverage report and preservation of observation provenance; no reassignment.
2. Track consistency and calibrated face/body association; regression checks for propagation, cuts, competing people and sparse sampling.
3. Unified candidate retrieval plus shadow plans with explanations; keep corrections and clothing-only exclusion.
4. Fusion calibration and high-information review on existing data; targeted enrichment for missing evidence.
5. Qualified automatic application with an audited precision target, rollback and measured mobile performance.

The exact auto-apply precision target is a product/evaluation decision, not a claimed achieved number. Existing regional-cluster qualification gates are not evidence that broader automatic identity fusion is qualified.

## Implementation map

- Phone input/state: domain/grouping/grouping_inputs.dart; data/api/dtos/grouping.dart; data/db/tables.dart and migrations.
- Shared decision core: the app/grouping_core.py and person_linking.py; add a separate pure evidence/fusion module as needed.
- Contract: the app/mobile_api/contract/openapi.yaml, server schemas/fixtures and client capability negotiation. A new capability/version must permit old clients and servers to continue their current workflow.
- Video: domain/scan/video_tracks.dart, video_scan.dart, video_compactor.dart, photo_result_store.dart; preserve original occurrence links.
- Comparators: domain/marks/body_marks.dart, domain/pose/exposed_matching.dart, pose_descriptor.dart; reuse them behind typed evidence adapters.
- Apply/review: domain/grouping/plan_applier.dart, grouping_runner.dart, data/repositories/review_repository.dart and correction guards.
- Persistence: backup and organization/sidecar_metadata.dart, ingestion and dynamic organizer. New decision provenance must survive export/import without treating stale automatic assignments as new manual truth.

## Required verification when implementation starts

Contract round trips, migration and backup/sidecar round trips; stale-plan races; model-version mismatch; NaN/zero vectors; missing fields; duplicate occurrences; same-frame competition including reflection exceptions; cross-kind isolation; manual rejections/locks/ownership; track contamination; correlated-evidence saturation; missing-modality calibration; unchanged current behavior when the new capability is absent.

Use existing grouping, face-correction, video-track, exposed-matching, marks and review tests as regression baselines, then add only tests that exercise the new decisions and invariants.

## Research basis

- Pose-guided Visible Part Matching (CVPR 2020): https://openaccess.thecvf.com/content_CVPR_2020/html/Gao_Pose-Guided_Visible_Part_Matching_for_Occluded_Person_ReID_CVPR_2020_paper.html
- Learning To Know Where To See (ICCV 2021): https://openaccess.thecvf.com/content/ICCV2021/html/Yang_Learning_To_Know_Where_To_See_A_Visibility-Aware_Approach_for_ICCV_2021_paper.html
- Clothes-Changing Person Re-Identification With RGB Modality Only (CVPR 2022): https://openaccess.thecvf.com/content/CVPR2022/html/Gu_Clothes-Changing_Person_Re-Identification_With_RGB_Modality_Only_CVPR_2022_paper.html

These support the design principles, not accuracy claims for this application's existing models.

## Work performed in this task

Source/contract/schema inspection and design documentation only. No application code, model, package, data, settings, server or phone state was changed. No tests or benchmarks were executed. Real-library feature coverage, calibration, inference cost and accuracy remain unmeasured.
