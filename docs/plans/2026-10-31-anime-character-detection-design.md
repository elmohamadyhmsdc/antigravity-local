# Anime & Character Unified Detection Architecture Design

> **Date:** 2026-10-31  
> **Status:** Validated  
> **Target:** Your Gallery (Unified Mobile + PC Server)  
> **Reference:** Face Gallery Architecture (`d:\test\face gallary`)

---

## 1. Goal & Requirements
- **Unified Media Scanning:** Eliminate manual folder tagging ("Illustrated/Anime Album"). All selected folders/media are scanned uniformly for both real human faces and anime/cartoon characters.
- **Accurate Routing & Baby-Face Veto:** Real humans go to `People`. Anime/cartoon characters go to `Characters`. Zero real infants/babies leaked into `Characters`; zero anime faces leaked into `People`.
- **Face & Body Detection:** Detect both the face and body for anime characters as well as real people.
- **Character Profiles & Clustering:** Group detected anime characters into distinct, identifiable profiles in the `Characters` tab with naming, merging, and full photo/video browsing.

---

## 2. Server-Side Detection Architecture (`the app/`)

### 2.1 Dual-Detector Routing Pipeline (`analysis.py`)
1. **Human Face Detector (`SCRFD` / InsightFace):**
   - Runs with dual thresholds:
     - `SCRFD_SCAN_THRESH = 0.70` (admission to `faces` / People)
     - `SCRFD_VETO_THRESH = 0.40` (sensitivity floor for vetoing false anime detections)
2. **Anime Face Detector (`AnimeFaceDetector`):**
   - Model: `deepghs/anime_face_detection` (YOLOv8 ONNX: `anime_face_detect.onnx`, 44.5 MB, available locally at `d:\test\face gallary\app\src\main\assets\models\anime_face_detect.onnx`).
   - Runs on the input image on CUDA via ONNX Runtime.
   - Geometry gates:
     - Aspect ratio: $0.35 \le w/h \le 1.8$ (rejects text banners like "WAIFU" or UI graphics).
     - Minimum dimension: $\min(w, h) \ge 20\text{ px}$.
     - Confidence floor: $0.55$.
3. **Baby-Face & Overlap Veto (`FaceDedup`):**
   - If an anime detection overlaps with any SCRFD detection at $\ge 0.40$:
     $$\text{IoU} \ge 0.50 \quad \text{OR} \quad \text{Containment} \ge 0.60$$
   - The anime detection is **vetoed** (discarded) and the face remains in the human `faces` path.
4. **Tie-Breaker for Realistic Manga (`IllustrationClassifier`):**
   - Model: `photo_vs_illustration.onnx` (3.8 MB).
   - Runs **only** on the ambiguous overlap set (`SCRFD \ge 0.70 \cap AnimeFace \ge 0.55`).
   - If probability of illustration $\ge 0.85$, the face is demoted from `faces` to `characters`.
5. **Character Feature Embedding (`CCIP`):**
   - Model: `deepghs/ccip` (`ccip_character.onnx`, 150 MB, caformer-24).
   - Extracts a 768-d character identity embedding.
   - Combined with outfit hue (16-d) and hat/hair hue (8-d) to produce a 792-d character appearance vector.
6. **Body Association:**
   - Character face detections are paired with body detections (from HumanArt / YOLOX) so that both face and body boundaries are captured.

---

## 3. Mobile Client & Database Architecture (`mobile/`)

### 3.1 Scanner & Folder Selection (`scan_engine.dart`, `sources_screen.dart`)
- Remove the requirement that an album must be marked in `character_albums` to scan for characters.
- Every photo/video frame scanned sends `detect_characters: true` to the PC server.
- The UI setting for folder selection simply selects folders to scan; character detection is always active.

### 3.2 Storage & Database (`photo_result_store.dart`, `character_repository.dart`)
- `PhotoResultStore`:
  - Receives `response.faces` (humans) $\to$ stored in `faces` table, indexed in `embedding_index`.
  - Receives `response.characters` $\to$ stored in `character_samples` linked to `character_identities`.
  - Stored character rows maintain face bbox, body bbox, face crop path, and appearance vector.
- Clustering:
  - `CharacterRepository` clusters incoming character appearances into profiles:
    - $\tau_{\text{form}} = 0.80$ to establish a new character profile.
    - $\tau_{\text{assign}} = 0.70$ to add a sample to an existing character profile.
  - Multi-sample representation ensures stable identities across different poses and expressions.

### 3.3 UI & Navigation (`characters_screen.dart`, `character_detail_screen.dart`)
- **Characters Navigation:**
  - Distinct and easily accessible from the `People` screen and/or bottom navigation.
- **Character Grid & Profiles:**
  - Displays character cards: cover face, name (editable), and count of photos and videos.
- **Character Detail Screen:**
  - View all photos and videos featuring the character.
  - Rename character (e.g., "Luffy", "Goku").
  - Merge characters (merge duplicate profiles).
  - Media viewer shows face circle and body bounding box.

---

## 4. Error Handling & Safety
1. **Graceful Degradation:** If anime models are absent on the PC, the server logs a warning and gracefully continues standard face scanning.
2. **OOM Safety:** Character grid queries only retrieve IDs and metadata (preventing materialization of large vectors in heap).
3. **Video Track Limiting:** Character detections in video tracks are capped to avoid database inflation.
