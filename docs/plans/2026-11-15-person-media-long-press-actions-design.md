# Person & Character Media Long-Press Actions Design

**Date**: 2026-11-15  
**Scope**: Mobile Application (`mobile/lib/features/people/`)  
**Status**: Validated & Approved  

---

## 1. Problem Statement & User Goal

In the mobile app, when viewing a person or character (`PersonDetailScreen`), users view photos in which that entity appears (`_PersonMedia`). Previously, long-pressing on a photo did nothing. Users lacked a direct, intuitive way to understand *why* a particular photo was associated with that person (e.g. was their face detected? was only their body linked by outfit/manual link? or both face and body?). 

Furthermore, when an association was wrong or needed adjusting, users had to navigate through separate tabs or deep menus. They need a single, immediate long-press action sheet that:
1. Clearly displays the association reason: **Face & Body**, **Face only**, or **Body only**, with visual crop previews.
2. Provides instant corrections:
   - **"Not this person" (لا ده مش نفس الشخص)**: Rejects the face from this person so the engine never re-clusters it here.
   - **"Not this body" (لا ده مش نفس الجسم)**: Unlinks the body from this person without altering face assignments.
   - **"Another person (and navigate there)" (شخص تاني ويوديك عليه)**: Reassigns the detection(s) to another person and immediately opens that person's screen.
   - **"Move to Characters / Move to People" (تحويل لشخصيات كرتونية / أناس)**: Corrects detection kind.
3. Provides quick secondary shortcuts: Set as cover avatar, view full photo, edit with AI / Studio Reface, and share.

---

## 2. Architecture & Data Flow

```
[PersonDetailScreen] (Person / Character)
       │
       ▼ Tab 0: _PersonMedia
  [MediaGrid] ──► [MediaTile] (onLongPress)
                         │
                         ▼
           [PersonMediaActionSheet.show]
                         │
        ┌────────────────┴────────────────┐
        ▼                                 ▼
[watchDetections(mediaId)]      [PersonSummary]
        │                                 │
        ▼                                 ▼
Filter detections for personId:
  • faceDetection (isFace && personId == person.id)
  • bodyDetection (isBody && personId == person.id)
  • otherPersons (co-occurring people in media)
        │
        ▼
Resolve AssociationStatus:
  • both: Face & Body
  • faceOnly: Face only
  • bodyOnly: Body only
```

### Components

1. **`PersonMediaActionSheet` (`mobile/lib/features/people/person_media_action_sheet.dart`)**:
   - Modal bottom sheet displaying the `Hero Detection Card` and categorized action tiles.
   - Uses `SheetScaffold`, `ActionSection`, and `theme.colorScheme` tokens.

2. **`MediaGrid` & `MediaTile` (`mobile/lib/features/library/media_grid.dart`)**:
   - Added `onLongPress: ValueChanged<MediaListItem>?` callback passed down to `MediaTile`.

3. **`_PersonMedia` (`mobile/lib/features/people/person_detail_screen.dart`)**:
   - Hooks up `onLongPress` to invoke `showPersonMediaActionSheet(context, ref, person: p, item: item)`.

---

## 3. UI/UX Specifications

### Hero Detection Card
- Container: `theme.colorScheme.surfaceContainerLow` with `0.8px` border (`outlineVariant`) and `16dp` border radius.
- Leading: Thumbnail of photo (`56x56dp`, rounded `8dp`).
- Center/Details:
  - Header: Association badge pill:
    - `both`: Indigo accent pill (`Icons.people_alt`) — *"Linked by Face & Body (وجه وجسم معاً)"*
    - `faceOnly`: Primary/Teal pill (`Icons.face`) — *"Linked by Face only (الوجه فقط)"*
    - `bodyOnly`: Secondary pill (`Icons.accessibility_new`) — *"Linked by Body only (الجسم فقط)"*
  - Interactive Previews:
    - Face crop avatar chip (if face present).
    - Body crop avatar chip (if body present, with indicator for `outfit` or `manual`).

### Action Groups

1. **Identity & Link Corrections (تصحيح الهوية والربط)**:
   - **Not this person (لا ده مش نفس الشخص)**: Visible when `faceDetection != null`. Calls `repo.rejectFaces([faceDetection.refId], fromPersonId: person.id)`. Shows SnackBar with undo.
   - **Not this body (لا ده مش نفس الجسم)**: Visible when `bodyDetection != null`. Calls `repo.rejectBody(bodyDetection.refId, personId: person.id)`. Shows SnackBar with undo.
   - **Another person... (شخص تاني ويوديك عليه)**: Opens quick-picks for co-occurring people + `pickPerson`. On selection, reassigns face/body and pushes route `${Routes.people}/$targetPersonId`.
   - **Move to Characters / People**: Toggles figure kind via `moveToOtherKind`.

2. **Quick Shortcuts (إجراءات سريعة)**:
   - **Set as Cover (تعيين كصورة الغلاف)**: Visible when face is present. Calls `repo.setAvatar(person.id, faceDetection.refId)`.
   - **View Full Photo (عرض الصورة كاملة)**: Navigates to `MediaViewerScreen`.
   - **AI Edit / Studio Reface**: Direct deep-links to Photo Edit / Reface with face preselected.
   - **Share (مشاركة)**: Shares media via `share_plus`.

---

## 4. Verification Plan

1. **Widget / Unit Tests**:
   - `mobile/test/features/person_media_action_sheet_test.dart`:
     - Test long press on `MediaTile` in `PersonDetailScreen`.
     - Test Hero card displays correct badge for `both`, `faceOnly`, and `bodyOnly`.
     - Test "Not this person" calls `rejectFaces`.
     - Test "Not this body" calls `rejectBody`.
     - Test "Another person" reassigns and navigates to the target person route.
     - Test "Move to characters/people" triggers kind migration.
2. **Static Analysis**:
   - `flutter analyze` clean on all touched files.
3. **Regression Tests**:
   - Rerun `people_test.dart`, `people_simplified_ux_test.dart`, `entity_card_test.dart`.
