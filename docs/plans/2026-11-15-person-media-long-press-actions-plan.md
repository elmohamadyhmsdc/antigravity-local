# Person & Character Media Long-Press Actions Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement a context-aware Long Press Action Sheet on photos inside a Person or Character's album, showing whether the photo is linked by face and body, face only, or body only, and providing instant one-tap corrections ("Not this person", "Not this body", "Another person & navigate there", "Move to characters/people") and quick media tools.

**Architecture:** 
1. Pass an `onLongPress: ValueChanged<MediaListItem>?` callback down through `MediaGrid` to `MediaTile`.
2. Connect `_PersonMedia` in `PersonDetailScreen` to intercept the long press and trigger `showPersonMediaActionSheet`.
3. Inside `PersonMediaActionSheet`, resolve detections for `mediaId` and match against the current `personId` to display the Hero Detection Card (visual previews of face/body crops with association badges) and categorized action tiles.
4. Execute mutations via `PeopleRepository` and navigate to the target person upon reassignment.

**Tech Stack:** Flutter, Flutter Riverpod, GoRouter, SQLite / Drift (`AppDatabase`), Material 3 (`SheetScaffold`, `ActionSection`, `ThemeData`).

---

### Task 1: Add Localization Strings

**Files:**
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_localizations.dart`
- Modify: `mobile/lib/l10n/app_localizations_en.dart`

**Step 1: Write/Update localization entries in `mobile/lib/l10n/app_en.arb`**
Add:
```json
  "notThisBody": "Not this body",
  "linkedByFaceAndBody": "Linked by face & body",
  "linkedByFaceOnly": "Linked by face only",
  "linkedByBodyOnly": "Linked by body only",
  "reassignToOtherPerson": "Another person...",
  "setAsPersonCover": "Set as cover photo",
  "viewFullMedia": "View full photo",
  "reassignedToPerson": "Moved to {name}",
  "@reassignedToPerson": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  }
```

**Step 2: Update Dart getters in `app_localizations.dart` and `app_localizations_en.dart`**
Add getters:
- `String get notThisBody;`
- `String get linkedByFaceAndBody;`
- `String get linkedByFaceOnly;`
- `String get linkedByBodyOnly;`
- `String get reassignToOtherPerson;`
- `String get setAsPersonCover;`
- `String get viewFullMedia;`
- `String reassignedToPerson(String name);`

**Step 3: Verification**
Run: `flutter analyze mobile/lib/l10n/`
Expected: 0 issues.

---

### Task 2: Add `onLongPress` to `MediaGrid` and `MediaTile`

**Files:**
- Modify: `mobile/lib/features/library/media_grid.dart:18-35` and `155-200`
- Test: `mobile/test/features/media_grid_test.dart` (or focused widget check)

**Step 1: Write test for `onLongPress` in `MediaTile`**
Verify that a long-press gesture on `MediaTile` triggers `onLongPress` callback with the corresponding `MediaListItem`.

**Step 2: Update `MediaGrid` and `MediaTile`**
- Add `final ValueChanged<MediaListItem>? onLongPress;` to `MediaGrid` and pass it to `MediaTile`.
- In `MediaTile`, update `GestureDetector`:
```dart
    return GestureDetector(
      key: Key('media-${item.id}'),
      onTap: () { ... },
      onLongPress: onLongPress == null ? null : () => onLongPress!(item),
      child: ...
```

**Step 3: Verification**
Run: `flutter test test/features/library_screen_test.dart` (or existing library tests) to verify zero regressions.

---

### Task 3: Build `PersonMediaActionSheet` Component

**Files:**
- Create: `mobile/lib/features/people/person_media_action_sheet.dart`
- Test: `mobile/test/features/person_media_action_sheet_test.dart`

**Step 1: Implement `PersonMediaActionSheet`**
The component should:
1. Load `watchDetections(item.id).first`.
2. Find `faceDetection` (`d.isFace && d.personId == person.id`).
3. Find `bodyDetection` (`d.isBody && d.personId == person.id`).
4. Find `otherPeople` (distinct `d.personId != null && d.personId != person.id`).
5. Render the Hero Card:
   - Photo thumbnail (`item.assetId` via `thumbnailServiceProvider`).
   - Association Badge (Face & Body, Face only, or Body only).
   - Face crop preview and Body crop preview.
6. Render Actions:
   - If `faceDetection != null`: "Not this person" (`notThisPerson` icon `person_off_outlined`) -> `repo.rejectFaces`.
   - If `bodyDetection != null`: "Not this body" (`notThisBody` icon `accessibility_new`) -> `repo.rejectBody`.
   - "Another person..." (`reassignToOtherPerson` icon `drive_file_move_outline`) -> opens `pickPerson`, reassigns face & body, and calls `context.push('${Routes.people}/$targetId')`.
   - If co-occurring people exist: quick chips with their avatars to reassign and jump in 1 tap.
   - "Move to characters/people" (`toCharacters` / `toPeople`) -> calls `moveToOtherKind`.
   - "Set as cover photo" (if `faceDetection != null`) -> calls `repo.setAvatar`.
   - "View full photo" -> `context.push('${Routes.media}/${item.id}?personId=${person.id}')`.
   - "AI Photo Edit" -> `context.push('${Routes.photoEdit}?mediaId=${item.id}')`.
   - "Studio Reface" (if `person.kind == 'person' && faceDetection != null`) -> `context.push('${Routes.reface}?face=${faceDetection.refId}')`.
   - "Share" -> shares media file.

**Step 2: Write failing unit/widget test in `mobile/test/features/person_media_action_sheet_test.dart`**
Verify rendering of badges and triggering of actions.

**Step 3: Verification**
Run: `flutter test test/features/person_media_action_sheet_test.dart`
Expected: PASS.

---

### Task 4: Connect `_PersonMedia` in `PersonDetailScreen`

**Files:**
- Modify: `mobile/lib/features/people/person_detail_screen.dart:750-795`

**Step 1: Wire `onLongPress` in `_PersonMediaState`**
Pass `onLongPress: (item) => showPersonMediaActionSheet(context, ref, person: p, item: item)` to `MediaGrid`.

**Step 2: Verification**
Run: `flutter test test/features/people_test.dart test/features/people_simplified_ux_test.dart`
Expected: PASS.

---

### Task 5: Static Analysis & Full Regression Testing

**Files:**
- All modified files

**Step 1: Run Flutter Analyze**
Run: `cd mobile; flutter analyze`
Expected: `No issues found!`.

**Step 2: Run Full Targeted Test Suites**
Run: `cd mobile; flutter test test/features/person_media_action_sheet_test.dart test/features/people_test.dart test/features/people_simplified_ux_test.dart test/features/characters_test.dart test/features/bodies_screen_test.dart`
Expected: All tests pass.

---

### Task 6: Update `ANTIGRAVITY_HANDOFF.md`

**Files:**
- Modify: `docs/ANTIGRAVITY_HANDOFF.md`

**Step 1: Record additions, tests run, exact verification passes and remaining work.**
