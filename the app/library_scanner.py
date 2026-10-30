"""
Library scanner - turns photos and videos into gallery records.

Per file it stores three things:
  faces  - one record per distinct face, with the identity embedding and the
           quality metadata from face_quality
  bodies - person detections (box + keypoints + an outfit descriptor), each tied
           to its face when the face is usable
  media  - the file itself, with every detection in it, so the gallery can say
           who appears in which photo or video (and where, in a video)

What changed vs the old face_miner:
  * detection runs at several scales, so a face filling the frame (close-up
    selfie) and a small face in a big photo both get found - at the single 640
    scale the app used, 119 of 290 existing crops weren't even re-detectable
  * quality is the calibrated face_quality score, not det_score * size ratio
  * a face that's already in the gallery is linked instead of re-added, so the
    photo still shows up under that person
  * video frames get a frame number and timestamp, and near-identical faces from
    the same video are linked rather than piled up as duplicates
  * scanning is resumable: media records track the file signature and the last
    scanned frame, so an interrupted scan picks up where it stopped
"""

import os
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Callable, Dict, List, Optional, Sequence, Tuple

import cv2
import numpy as np

import analysis
import face_quality
import person_linking as pl
from database import JsonDatabase, norm_path

SCAN_VERSION = 2

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp", ".gif"}
VIDEO_EXTS = {".mp4", ".avi", ".mkv", ".mov", ".wmv", ".flv", ".webm", ".m4v"}
MEDIA_EXTS = IMAGE_EXTS | VIDEO_EXTS

FACE_CROP_DIR = Path("extracted_faces")
BODY_CROP_DIR = Path("extracted_bodies")


def imread(path) -> Optional[np.ndarray]:
    """cv2.imread that survives non-ASCII paths on Windows."""
    try:
        data = np.fromfile(str(path), dtype=np.uint8)
        if data.size == 0:
            return None
        return cv2.imdecode(data, cv2.IMREAD_COLOR)
    except Exception:
        return None


def imwrite(path, image, quality: int = 95) -> bool:
    path = Path(path)
    try:
        ok, buf = cv2.imencode(path.suffix or ".jpg", image, [cv2.IMWRITE_JPEG_QUALITY, quality])
        if not ok:
            return False
        path.parent.mkdir(parents=True, exist_ok=True)
        buf.tofile(str(path))
        return True
    except Exception:
        return False


def is_media(path) -> bool:
    return Path(path).suffix.lower() in MEDIA_EXTS


def is_video(path) -> bool:
    return Path(path).suffix.lower() in VIDEO_EXTS


def collect_media(folder, include_subfolders: bool = True, videos: bool = True) -> List[Path]:
    folder = Path(folder)
    if not folder.exists():
        return []
    exts = IMAGE_EXTS | (VIDEO_EXTS if videos else set())
    it = folder.rglob("*") if include_subfolders else folder.iterdir()
    return sorted(f for f in it if f.is_file() and f.suffix.lower() in exts)


def file_signature(path) -> Dict:
    st = os.stat(path)
    return {"size": st.st_size, "mtime": int(st.st_mtime)}


@dataclass
class ScanOptions:
    frame_interval: float = 1.0          # seconds between sampled video frames
    min_face_quality: float = face_quality.DEFAULT_MIN_QUALITY
    detect_bodies: bool = True
    body_score: float = 0.5
    duplicate_distance: float = 0.05     # same face crop already in the gallery
    video_similar_distance: float = 0.08  # near-identical face from the same video
    max_bodies_per_media: int = 40
    save_body_crops: bool = True
    rescan: bool = False                 # redo files that were already scanned

    @classmethod
    def from_env(cls, **kw):
        return cls(frame_interval=float(os.getenv("FRAME_INTERVAL", "1.0")),
                   min_face_quality=float(os.getenv("FACE_MIN_QUALITY", face_quality.DEFAULT_MIN_QUALITY)),
                   **kw)


@dataclass
class ScanSummary:
    files_scanned: int = 0
    files_skipped: int = 0
    faces_new: int = 0
    faces_linked: int = 0
    faces_updated: int = 0
    bodies_new: int = 0
    frames: int = 0
    errors: List[str] = field(default_factory=list)
    seconds: float = 0.0

    def as_text(self) -> str:
        return (f"{self.files_scanned} files scanned ({self.files_skipped} already up to date) - "
                f"{self.faces_new} new faces, {self.faces_linked} linked to faces already in the gallery, "
                f"{self.bodies_new} bodies")


class LibraryScanner:
    def __init__(self, db: Optional[JsonDatabase] = None, options: Optional[ScanOptions] = None,
                 face_app=None, body=None, log: Callable[[str], None] = print,
                 face_crop_dir: Path = FACE_CROP_DIR, body_crop_dir: Path = BODY_CROP_DIR):
        self.db = db or JsonDatabase()
        self.options = options or ScanOptions.from_env()
        self.log = log
        self._face_app = face_app
        self._body = body
        self.face_crop_dir = Path(face_crop_dir)
        self.body_crop_dir = Path(body_crop_dir)

    # --- models -----------------------------------------------------------

    @property
    def face_app(self):
        if self._face_app is None:
            from cuda_dll_dirs import add_nvidia_dll_dirs
            add_nvidia_dll_dirs()
            from insightface.app import FaceAnalysis
            app = FaceAnalysis(name="buffalo_l",
                               allowed_modules=["detection", "recognition", "landmark_3d_68"],
                               providers=["CUDAExecutionProvider", "CPUExecutionProvider"])
            app.prepare(ctx_id=0, det_size=[(128, 128), (640, 640)])
            self._face_app = app
        return self._face_app

    @property
    def body(self):
        if self._body is None and self.options.detect_bodies:
            from body_detector import BodyAnalyzer
            self._body = BodyAnalyzer(log=self.log)
        return self._body

    # --- detection --------------------------------------------------------

    # The detection logic lives in analysis.py (shared with the mobile API); these
    # stay as methods because tests and callers override them per instance.

    @staticmethod
    def det_sizes(img) -> List[Tuple[int, int]]:
        return analysis.det_sizes(img)

    def detect_faces(self, img) -> list:
        """insightface's FaceAnalysis.get, but with per-image detector scales."""
        return analysis.detect_faces(self.face_app, img)

    def assess_face(self, img, face) -> Dict:
        return analysis.assess_face(img, face)

    # --- public API -------------------------------------------------------

    def scan_paths(self, paths: Sequence, progress: Optional[Callable[[int, int, Path, ScanSummary], None]] = None,
                   should_stop: Optional[Callable[[], bool]] = None) -> ScanSummary:
        """Scan files (already-scanned unchanged files are skipped unless
        options.rescan). Progress is reported per file; the database is flushed
        as we go so an interrupted scan can resume."""
        summary = ScanSummary()
        started = time.time()
        paths = [Path(p) for p in paths]
        last_flush = time.time()
        with self.db.batch():
            for i, path in enumerate(paths):
                if should_stop is not None and should_stop():
                    self.log("[scan] stopped by request")
                    break
                if progress is not None:
                    progress(i, len(paths), path, summary)
                try:
                    self.scan_file(path, summary)
                except Exception as e:  # one unreadable file shouldn't end the scan
                    summary.errors.append(f"{path.name}: {e}")
                    self.log(f"[scan] {path.name}: {e}")
                if time.time() - last_flush > 3:
                    self.db.flush()
                    last_flush = time.time()
        summary.seconds = time.time() - started
        if progress is not None:
            progress(len(paths), len(paths), None, summary)
        return summary

    def scan_file(self, path: Path, summary: Optional[ScanSummary] = None) -> ScanSummary:
        summary = summary or ScanSummary()
        path = Path(path)
        if not path.exists() or not is_media(path):
            return summary
        sig = file_signature(path)
        record = self.db.get_media_by_path(str(path))
        if (record and not self.options.rescan
                and record.get("scan_version") == SCAN_VERSION
                and record.get("scan_status") == "done"
                and record.get("size") == sig["size"] and record.get("mtime") == sig["mtime"]):
            summary.files_skipped += 1
            return summary
        if is_video(path):
            self._scan_video(path, sig, record, summary)
        else:
            self._scan_image(path, sig, summary)
        summary.files_scanned += 1
        return summary

    # --- images -----------------------------------------------------------

    def _scan_image(self, path: Path, sig: Dict, summary: ScanSummary):
        img = imread(path)
        if img is None:
            raise IOError("could not read image")
        h, w = img.shape[:2]
        media_id = self.db.upsert_media(str(path), {
            "type": "image", "width": w, "height": h, **sig,
            "scan_version": SCAN_VERSION, "scan_status": "scanning",
            "scanned_at": datetime.utcnow().isoformat(), "detections": [],
        })
        state = _FileState(self.db, str(path), media_id, is_video=False)
        detections = self._scan_frame(img, state, frame_number=None, timestamp=None, summary=summary)
        self.db.upsert_media(str(path), {
            "scan_status": "done", "detections": detections,
            "face_count": sum(1 for d in detections if d[2] == "f"),
            "body_count": sum(1 for d in detections if d[2] == "b"),
            "frames_scanned": 1,
        })
        summary.frames += 1

    # --- videos -----------------------------------------------------------

    def _scan_video(self, path: Path, sig: Dict, record: Optional[Dict], summary: ScanSummary):
        cap = cv2.VideoCapture(str(path))
        if not cap.isOpened():
            raise IOError("could not open video")
        try:
            fps = cap.get(cv2.CAP_PROP_FPS) or 0.0
            total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
            w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
            h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
            step = max(1, int(round((fps or 30.0) * self.options.frame_interval)))

            resume_from = 0
            detections: List[list] = []
            same_file = (record and record.get("size") == sig["size"] and record.get("mtime") == sig["mtime"])
            if same_file and not self.options.rescan and record.get("scan_status") == "scanning":
                resume_from = int(record.get("last_frame") or 0)
                detections = list(record.get("detections") or [])
                self.log(f"[scan] resuming {path.name} at frame {resume_from}")

            media_id = self.db.upsert_media(str(path), {
                "type": "video", "width": w, "height": h, "fps": round(fps, 3),
                "frame_count": total, "duration": round(total / fps, 2) if fps else None, **sig,
                "scan_version": SCAN_VERSION, "scan_status": "scanning",
                "scanned_at": datetime.utcnow().isoformat(),
                "detections": detections, "last_frame": resume_from,
            })
            state = _FileState(self.db, str(path), media_id, is_video=True)
            frame_number, frames_done = 0, 0
            if resume_from:
                cap.set(cv2.CAP_PROP_POS_FRAMES, resume_from)
                frame_number = resume_from
            while True:
                ok, frame = cap.read()
                if not ok or frame is None:
                    break
                if frame_number % step == 0:
                    t = round(frame_number / fps, 2) if fps else None
                    detections.extend(self._scan_frame(frame, state, frame_number, t, summary))
                    frames_done += 1
                    summary.frames += 1
                    if frames_done % 20 == 0:
                        self.db.upsert_media(str(path), {"last_frame": frame_number, "detections": detections})
                frame_number += 1
        finally:
            cap.release()
        self.db.upsert_media(str(path), {
            "scan_status": "done", "detections": detections, "last_frame": frame_number,
            "frames_scanned": frames_done,
            "face_count": len({d[3] for d in detections if d[2] == "f"}),
            "body_count": sum(1 for d in detections if d[2] == "b"),
        })

    # --- one frame --------------------------------------------------------

    def _scan_frame(self, img, state: "_FileState", frame_number: Optional[int],
                    timestamp: Optional[float], summary: ScanSummary) -> List[list]:
        detections: List[list] = []
        # detect/assess go through the overridable methods above (the tests stub them)
        result = analysis.analyze_frame(self._face_app, self.body, img, self.options,
                                        detect=self.detect_faces, assess=self.assess_face)
        faces, quality, bodies = result.faces, result.quality, result.bodies
        face_of_body = result.face_of_body

        face_ids: Dict[int, Optional[int]] = {}
        ignored_faces = set()
        for i, (face, q) in enumerate(zip(faces, quality)):
            if not result.passes_gate[i]:
                face_ids[i] = None
                continue
            fid, kind = state.store_face(self, img, face, q, frame_number, timestamp)
            face_ids[i] = fid
            if kind == "suppressed":
                ignored_faces.add(i)
                continue
            if kind == "new":
                summary.faces_new += 1
            else:
                summary.faces_linked += 1
                if kind == "updated":
                    summary.faces_updated += 1
            x1, y1, x2, y2 = [int(v) for v in face.bbox[:4]]
            detections.append([frame_number, timestamp, "f", fid, x1, y1, x2 - x1, y2 - y1])

        for bi, body in enumerate(bodies):
            fi = face_of_body.get(bi)
            fid = face_ids.get(fi) if fi is not None else None
            weak = None
            if fi is not None and fi not in ignored_faces and fid is None and faces[fi].embedding is not None:
                weak = (faces[fi].normed_embedding, quality[fi]["quality_score"])
            bid = state.store_body(self, img, body, result.appearances[bi], fid, weak, frame_number, timestamp)
            if bid is None:
                continue
            summary.bodies_new += 1
            x1, y1, x2, y2 = [int(v) for v in body.bbox[:4]]
            detections.append([frame_number, timestamp, "b", bid, x1, y1, x2 - x1, y2 - y1])
        return detections


class _FileState:
    """Per-file bookkeeping: which gallery faces already come from this file, and
    which bodies we've kept, so re-scans link instead of duplicating."""

    def __init__(self, db: JsonDatabase, source_path: str, media_id: int, is_video: bool):
        self.db = db
        self.source_path = source_path
        self.media_id = media_id
        self.is_video = is_video
        existing = db.get_faces_by_source(source_path)
        self.candidate_ids = [f["id"] for f in existing]
        self.candidate_vecs = pl.normalize_rows(db.get_embeddings_for(self.candidate_ids)) if existing else None
        self.kept_body_appearance: List[np.ndarray] = []
        self.kept_bodies = len(db.get_bodies_by_media(media_id))

    # -- faces --

    def _iou(self, a, b) -> float:
        ax1, ay1, aw, ah = a
        bx1, by1, bw, bh = b
        ax2, ay2, bx2, by2 = ax1 + aw, ay1 + ah, bx1 + bw, by1 + bh
        inter = max(0.0, min(ax2, bx2) - max(ax1, bx1)) * max(0.0, min(ay2, by2) - max(ay1, by1))
        union = aw * ah + bw * bh - inter
        return inter / union if union > 0 else 0.0

    def _existing_match(self, scanner: "LibraryScanner", emb: np.ndarray, bbox) -> Optional[int]:
        """A face from this same file that this detection is: the same box (photo
        re-scan) or a near-identical embedding (same person, neighbouring frames)."""
        if not self.candidate_ids:
            return None
        if not self.is_video:
            for fid in self.candidate_ids:
                face = self.db.get_face(fid)
                if face and face.get("bbox_width"):
                    box = (face.get("bbox_x") or 0, face.get("bbox_y") or 0,
                           face["bbox_width"], face.get("bbox_height") or 0)
                    if self._iou(bbox, box) >= 0.5:
                        return fid
        sims = self.candidate_vecs @ emb
        best = int(np.argmax(sims))
        if 1.0 - float(sims[best]) <= scanner.options.video_similar_distance:
            return self.candidate_ids[best]
        return None

    def _remember(self, fid: int, emb: np.ndarray):
        self.candidate_ids.append(fid)
        row = pl.normalize_rows(emb)[None]
        self.candidate_vecs = row if self.candidate_vecs is None else np.vstack([self.candidate_vecs, row])

    def store_face(self, scanner: "LibraryScanner", img, face, q: Dict,
                   frame_number: Optional[int], timestamp: Optional[float]) -> Tuple[Optional[int], str]:
        emb = face.normed_embedding
        x1, y1, x2, y2 = [float(v) for v in face.bbox[:4]]
        bbox = (x1, y1, x2 - x1, y2 - y1)
        if self.db.is_face_suppressed(self.source_path, emb, bbox, frame_number, self.is_video,
                                     scanner.options.duplicate_distance, scanner.options.video_similar_distance):
            return None, "suppressed"
        meta = {
            "media_id": self.media_id,
            "frame_number": frame_number,
            "timestamp": timestamp,
            "kps": None if face.kps is None else [[round(float(v), 1) for v in p] for p in face.kps],
            **q,
        }

        fid = self._existing_match(scanner, emb, bbox)
        kind = "linked"
        if fid is None:
            dup = self.db.find_duplicate(emb.tolist(), scanner.options.duplicate_distance)
            if dup:
                fid = dup[0]  # same face already mined from another copy of this file
        if fid is not None:
            existing = self.db.get_face(fid) or {}
            if (existing.get("quality_version") or 0) < face_quality.QUALITY_VERSION or \
                    float(q["quality_score"]) > float(existing.get("quality_score") or 0):
                update = dict(meta)
                if existing.get("media_id") not in (None, self.media_id):
                    # it was first mined from another file: keep that as its home
                    for key in ("media_id", "frame_number", "timestamp"):
                        update.pop(key, None)
                self.db.update_face(fid, update)
                kind = "updated"
            return fid, kind

        crop = self._face_crop(img, face)
        name = f"face_{datetime.now().strftime('%Y%m%d_%H%M%S_%f')}.jpg"
        crop_path = scanner.face_crop_dir / name
        imwrite(crop_path, crop)
        fid = self.db.add_face(
            embedding=emb,
            source_path=self.source_path,
            bbox={"x": round(x1, 1), "y": round(y1, 1), "w": round(bbox[2], 1), "h": round(bbox[3], 1)},
            quality_score=q["quality_score"],
            image_path=str(crop_path),
            extra={k: v for k, v in meta.items() if k != "quality_score"},
        )
        self._remember(fid, emb)
        return fid, "new"

    _face_crop = staticmethod(analysis.face_crop)

    # -- bodies --

    def store_body(self, scanner: "LibraryScanner", img, body, appearance: Optional[np.ndarray],
                   face_id: Optional[int], weak: Optional[Tuple[np.ndarray, float]],
                   frame_number: Optional[int], timestamp: Optional[float]) -> Optional[int]:
        if face_id is None:
            # Faceless bodies: only keep ones that look different from what we
            # already kept for this file, so a static video doesn't fill up with
            # the same shot
            if self.kept_bodies >= scanner.options.max_bodies_per_media:
                return None
            if appearance is not None and any(
                    pl.appearance_similarity(appearance, kept) >= 0.9 for kept in self.kept_body_appearance):
                return None
        x1, y1, x2, y2 = [float(v) for v in body.bbox[:4]]
        record = {
            "media_id": self.media_id,
            "source_path": self.source_path,
            "frame_number": frame_number,
            "timestamp": timestamp,
            "bbox": {"x": round(x1, 1), "y": round(y1, 1), "w": round(x2 - x1, 1), "h": round(y2 - y1, 1)},
            "score": round(float(body.score), 3),
            "face_id": face_id,
            "extent": pl.body_extent(body.kpt_scores),
            "appearance": None if appearance is None else [round(float(v), 4) for v in appearance],
            "kpts": None if body.kpts is None else
                    [[round(float(x), 1), round(float(y), 1), round(float(s), 3)]
                     for (x, y), s in zip(body.kpts, body.kpt_scores)],
        }
        if weak is not None:
            record["weak_face_embedding"] = [round(float(v), 5) for v in weak[0]]
            record["weak_face_quality"] = weak[1]
        if scanner.options.save_body_crops:
            crop_path = self._body_crop_path(scanner, frame_number)
            if imwrite(crop_path, self._body_crop(img, body.bbox)):
                record["crop_path"] = str(crop_path)
        bid = self.db.add_body(record)
        self.kept_bodies += 1
        if appearance is not None and face_id is None:
            self.kept_body_appearance.append(appearance)
        return bid

    def _body_crop_path(self, scanner: "LibraryScanner", frame_number: Optional[int]) -> Path:
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        suffix = "" if frame_number is None else f"_f{frame_number}"
        return scanner.body_crop_dir / f"body_{stamp}{suffix}.jpg"

    _body_crop = staticmethod(analysis.body_crop)
