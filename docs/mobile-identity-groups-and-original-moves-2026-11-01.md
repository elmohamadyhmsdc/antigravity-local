# Mobile identity groups and original-file organization — 2026-11-01

This feature is entirely on the phone: Flutter, its encrypted local database and
an Android MediaStore bridge. No PC server or inference code changes are needed.

## Groups

- People and anime Characters can belong to a named organizing **Group**, such
  as Family or One Piece. Each identity has one organizing group; visual identity
  matching remains separate from this metadata.
- Assign a group to one or multiple selected identities, or create a group from
  the picker. The People/Characters list can filter by group or show ungrouped
  identities. Group names appear on cards and the identity detail page.
- Groups can be renamed/deleted. Deleting a group keeps its members and their
  media. A merge retains the target's group, inheriting the source's only if the
  target has none.
- The group overview offers People, Characters, all linked photos/videos, and
  bulk original-file organization for the whole group.
- Group or identity renames change library metadata immediately. Physical
  folders/files change only through an explicit reviewed organization operation.

## Move and rename originals

The destination is public phone storage:

```text
DCIM/Your Gallery/One Piece/Luffy/Luffy_image_0001.jpg
DCIM/Your Gallery/One Piece/Luffy/Luffy_video_0001.mp4
```

There is no intermediate PC transfer or duplicate export. Android updates the
original item's `DISPLAY_NAME` and `RELATIVE_PATH`; its MediaStore ID remains the
app's reference. The implementation follows the [Android shared-media guide](https://developer.android.com/training/data-storage/shared/media).

- Image and video numbering are separate. Existing extensions are retained,
  with a MIME-derived extension for extensionless files. No transcoding occurs.
- Names remain readable in non-Latin scripts, with invalid path characters
  removed and UTF-8 component lengths bounded. Identities/groups whose names
  sanitize to the same folder are distinguished by their database IDs.
- Destination collisions get a distinct `_m<mediaId>` filename during preview.
  The alternate name is checked before it is shown. Unresolved collisions are
  excluded. No existing destination item is replaced.
- Shared photos/videos have one physical destination. When several selected
  identities occur in a file, the user chooses its owner in the preview. Every
  other identity retains its link to the same MediaStore item.
- Users can exclude individual files. Changing a shared file's owner preserves
  those exclusions and scroll position, and disables Apply until the updated
  preview is ready.
- Files changed since their detection are excluded until rescanned. Missing,
  inaccessible or unsupported files are reported individually.
- Android 10+ is required for physical organization. Android 11+ requests batch
  write consent, in batches of at most 1000 originals. Android 10 uses recoverable
  per-item consent. The app requests no broad storage-management permission.
- Source name, location, timestamp and size are rechecked after consent and
  immediately before each update. If Android adjusts a destination name, the
  result and journal record the actual name/location.

## Recovery and scanning

Schema v18 adds `identity_groups`, nullable `persons.group_id`, and a
`person_media_moves` journal. The migration is additive and queues no rescans.
Groups precede identities in backups; the move journal follows both its parents.

The journal commits before MediaStore changes. An interrupted operation can be
reviewed and reconciled using the unchanged asset ID: already moved files are
recognized without another physical move. Cancelling queued work reconciles
completed items and leaves remaining originals where they are. This is not an
automatic undo of completed moves.

Organization waits for an active scan to pause and settle, and blocks new scan
starts during the move. It refreshes plugin/thumbnail caches afterwards and
updates the library's modification timestamp without deleting detections.

Moving an anime file out of its original Android album retains its existing
illustrated scan mode. Pending/completed move records prevent the next library
sync from treating the new folder as a deliberate anime-mode change and deleting
characters. Existing per-detection kind corrections still apply. Filenames are
organizational labels; they do not improve visual recognition accuracy by
themselves. Newly added files/folders still use the normal Sources selection.

## Verification and delivery

- 168 focused Flutter tests passed across groups, v17→v18 migration, people/media
  queries, movement/recovery, backup/restore, scan lifecycle and existing
  People/Characters/Library interfaces. Focused analysis reported no issues.
- Cases include shared originals, permission cancellation, app interruption after
  a simulated native update, backup restoration of pending moves, preserved anime
  mode, collisions, duplicate names and 320dp/180% text layouts.
- A native Debug build succeeded in 42.7s during development. The user subsequently
  requested **no new version**. No final APK was built or delivered after that
  instruction; the pre-existing build output is not a delivery artifact for the
  completed source changes.
- No app installation or original-file move was performed on a physical phone.
  MediaStore consent, provider-specific behavior and real-device acceptance still
  need validation on Android. Tests used synthetic data and a fake native bridge.
