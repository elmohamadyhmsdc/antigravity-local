# People actions and visual review — 1.3.0

Long press on a person or face opens contextual actions. An overflow button opens
the same sheet. Opening an item and selecting several items are separate actions;
selection provides select-all, inverse selection and batch operations.

People actions include merge from the grid, rename, cover selection, automatic
best cover, pin, favorite, hide/restore, adding faces, splitting a new person,
reviewing suggestions, marking two people distinct, locking automatic matching,
Studio, exports, details and deletion of person groupings. Merge reviews the final
person, name and cover. Face actions include opening the source at its video
timestamp, assign/create/reject/unassign, cover, similarity search, Studio using
that specific face, gallery save, export, details, hide/restore and permanent
detection suppression. Deleting a grouping or detection preserves original media.

Schema v9 adds persistent person visibility/favorite/pin/matching-lock flags and
face visibility. These columns travel through the existing backup format. The v8
migration preserves existing rows with visible/unlocked defaults. A matching lock
blocks automatic face assignment, including stale plans, and preserves existing
derived body links; explicit manual corrections remain available. Hiding a face
does not delete its crop or assignment and removes it from avatar candidates.
Visibility and preference edits and renaming offer Undo. Merge history/undo,
aliases, tags and dated person collections remain the later additions discussed
in the action proposal; no inactive menu entries are exposed for them.

## Review

- Each card asks a concrete question: is this a named person, are these one new
  person, or does this body belong to the proposed person?
- Tapping a thumbnail opens an inspection viewer. A separate checkbox includes
  or excludes the face, including while inspecting full photos.
- Every group image is available, including images after the old 14-image limit.
  The viewer has swipe navigation, previous/next buttons, a thumbnail strip,
  photo zoom and a close-up toggle. Known-person/reference photos and both sides
  of duplicate comparisons can be inspected as complete galleries.
- Original photos show a yellow box and label on the exact face/body; the rest
  of the photo is dimmed. Linked/deduplicated faces use the box from each source
  occurrence, rather than reusing the canonical crop's coordinates.
- Video review seeks to the occurrence timestamp and highlights the requested
  face/body. If an original is unavailable, the viewer explicitly identifies
  the saved-crop fallback.
- Body matches have named Yes/No actions both on the card and in the full-photo
  viewer. Closing a face gallery preserves inclusion choices on the parent card.

## Verification

Final full Flutter suite: **496 passed**. Final static analysis: **no issues**.

People-only full suite: 489 tests passed before the additional Review work.
Review-focused repository, widget and rendering checks: 24 passed, including
swiping originals, selecting photo 21 of a 22-photo group, excluding it before
creation, and rejecting a body from the highlighted original. Source-coordinate
tests cover linked occurrences, mixed face/body IDs and legacy fallback rows.
Schema migration, preferences/Undo, split corrections, bulk merging, matching
locks and the existing library/backup regressions are exercised as well.

Review cards and face/body highlights were rendered and visually inspected with
a synthetic two-person image. Native Android share/save and a new physical-phone
video review run still require device acceptance; no phone was installed or live
PC service restarted by this change.

Release package: `com.antigravity.antigravity_mobile`, version **1.3.0**, code **6**.
This update also includes the detailed video scan progress from 1.2.1.
Signed APK: `mobile/build/people-review-1.3.0.apk`, **45,993,439 bytes**.
APK signature verification passed, and Android metadata confirms the version/code.
SHA-256: `eee9b22f0265b0555b423653c139781f66dc66006e4ffeff80119dd467089740`.
