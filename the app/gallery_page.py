"""
Gallery page - people, review queue, media library and insights.

Rendered by dashboard.py (`render(...)`). The page only does presentation and
user actions; detection lives in library_scanner, grouping in gallery_grouping.

Layout:
  People  - person cards -> one person's faces, photos/videos, body shots and
            suggestions
  Review  - the decision queue: faces that look like someone you know, new
            groups, possible duplicate people, unidentified bodies
  Media   - every photo/video, who is in it, with an inspector that draws the
            detections
  Insights- quality and coverage of the library
"""

import base64
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

import numpy as np
import streamlit as st

import face_quality
import gallery_grouping as gg
import person_linking as pl
from database import JsonDatabase, norm_path
from character_gallery import render_characters

VIEWS = ["People", "Characters", "Review", "Media", "Insights"]
VIEW_SLUGS = {"People": "people", "Characters": "characters", "Review": "unassigned", "Media": "media", "Insights": "insights"}
SLUG_VIEWS = {"people": "People", "person": "People", "unassigned": "Review", "review": "Review",
              "triage": "Review", "media": "Media", "all": "Media", "photos": "Media",
              "insights": "Insights", "analytics": "Insights", "stats": "Insights", "characters": "Characters"}

FACES_PER_PAGE = 48
MEDIA_PER_PAGE = 24
PEOPLE_PER_PAGE = 60

QUALITY_COLORS = {"great": "#34d399", "good": "#fbbf24", "fair": "#fb923c", "poor": "#fb7185"}
LINK_LABELS = {"appearance": "same outfit", "weak_face": "partial face", "manual": "set by you"}


# ---------------------------------------------------------------------------
# Cached data
# ---------------------------------------------------------------------------

@st.cache_resource(show_spinner=False)
def _scanner_models(detect_bodies: bool, detect_characters: bool = False):
    """Face analyzer + body analyzer, loaded once per session."""
    from cuda_dll_dirs import add_nvidia_dll_dirs
    add_nvidia_dll_dirs()
    app = None
    if not detect_characters:
        from insightface.app import FaceAnalysis
        app = FaceAnalysis(name="buffalo_l", allowed_modules=["detection", "recognition", "landmark_3d_68"],
                           providers=["CUDAExecutionProvider", "CPUExecutionProvider"])
        app.prepare(ctx_id=0, det_size=[(128, 128), (640, 640)])
    body = None
    if detect_bodies or detect_characters:
        from body_detector import BodyAnalyzer
        body = BodyAnalyzer(log=lambda m: st.session_state.setdefault("gal_model_log", []).append(m),
                            allow_downloads=False, use_pose=not detect_characters)
    return app, body


def _file_stamp(path: str) -> float:
    try:
        return os.path.getmtime(path)
    except OSError:
        return 0.0


@st.cache_data(show_spinner=False, max_entries=4096)
def _thumb(path: str, stamp: float, size: int = 256, ratio: float = 1.0) -> Optional[bytes]:
    """Center-cropped JPEG thumbnail (ratio = width / height)."""
    import cv2
    from library_scanner import imread
    img = imread(path)
    if img is None:
        return None
    h, w = img.shape[:2]
    target_w, target_h = (size, int(size / ratio)) if ratio >= 1 else (int(size * ratio), size)
    scale = max(target_w / w, target_h / h)
    img = cv2.resize(img, (max(1, int(round(w * scale))), max(1, int(round(h * scale)))),
                     interpolation=cv2.INTER_AREA)
    h, w = img.shape[:2]
    x, y = max(0, (w - target_w) // 2), max(0, (h - target_h) // 2)
    img = img[y:y + target_h, x:x + target_w]
    ok, buf = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 82])
    return buf.tobytes() if ok else None


@st.cache_data(show_spinner=False, max_entries=1024)
def _video_poster(path: str, stamp: float, frame: int = 0, size: int = 320,
                  ratio: float = 1.0) -> Optional[bytes]:
    import cv2
    cap = cv2.VideoCapture(str(path))
    try:
        if frame:
            cap.set(cv2.CAP_PROP_POS_FRAMES, int(frame))
        ok, img = cap.read()
        if not ok or img is None:
            return None
    finally:
        cap.release()
    h, w = img.shape[:2]
    target_w, target_h = (size, int(size / ratio)) if ratio >= 1 else (int(size * ratio), size)
    scale = max(target_w / w, target_h / h)
    img = cv2.resize(img, (max(1, int(round(w * scale))), max(1, int(round(h * scale)))),
                     interpolation=cv2.INTER_AREA)
    h, w = img.shape[:2]
    x, y = max(0, (w - target_w) // 2), max(0, (h - target_h) // 2)
    ok, buf = cv2.imencode(".jpg", img[y:y + target_h, x:x + target_w], [cv2.IMWRITE_JPEG_QUALITY, 82])
    return buf.tobytes() if ok else None


def thumb_for(path: Optional[str], size: int = 256, ratio: float = 1.0,
              video_frame: int = 0) -> Optional[bytes]:
    if not path or not os.path.exists(path):
        return None
    from library_scanner import is_video
    stamp = _file_stamp(path)
    if is_video(path):
        return _video_poster(path, stamp, video_frame, size, ratio)
    return _thumb(path, stamp, size, ratio)


def data_uri(payload: Optional[bytes]) -> Optional[str]:
    return None if not payload else "data:image/jpeg;base64," + base64.b64encode(payload).decode("ascii")


@st.cache_data(show_spinner=False, max_entries=2048)
def _body_thumb_cached(crop_path: str, stamp: float, bbox: Tuple[float, float, float, float],
                       kpts: Tuple[Tuple[float, float, float], ...],
                       size: int = 200, ratio: float = 0.75, highlight: bool = True) -> Optional[bytes]:
    """Target-centered thumbnail with a neon focus reticle isolating the subject."""
    import cv2
    from library_scanner import imread
    img = imread(crop_path)
    if img is None:
        return None
    crop_h, crop_w = img.shape[:2]
    bx, by, bw, bh = bbox

    target_w, target_h = (size, int(size / ratio)) if ratio >= 1 else (int(size * ratio), size)

    if not highlight or bw <= 0 or bh <= 0:
        scale = max(target_w / crop_w, target_h / crop_h)
        resized = cv2.resize(img, (max(1, int(round(crop_w * scale))), max(1, int(round(crop_h * scale)))),
                             interpolation=cv2.INTER_AREA)
        rh, rw = resized.shape[:2]
        x, y = max(0, (rw - target_w) // 2), max(0, (rh - target_h) // 2)
        ok, buf = cv2.imencode(".jpg", resized[y:y + target_h, x:x + target_w], [cv2.IMWRITE_JPEG_QUALITY, 85])
        return buf.tobytes() if ok else None

    # Calculate padding used when crop was created in library_scanner._body_crop
    pad_x = int(bw * 0.06)
    pad_y = int(bh * 0.04)
    crop_x0 = max(0.0, bx - pad_x)
    crop_y0 = max(0.0, by - pad_y)

    top_pad = by - crop_y0
    unscaled_h = top_pad + bh + pad_y
    scale_to_crop = crop_h / max(1.0, unscaled_h)

    # Use RTMPose keypoints if available to isolate target person from adjacent bodies
    valid_kpts = [pt for pt in kpts if len(pt) >= 3 and pt[2] >= 0.25]
    if valid_kpts:
        kxs = [pt[0] for pt in valid_kpts]
        kys = [pt[1] for pt in valid_kpts]
        min_kx, max_kx = min(kxs), max(kxs)
        min_ky, max_ky = min(kys), max(kys)
        kw = max_kx - min_kx
        kh = max_ky - min_ky
        tgt_x1 = max(bx, min_kx - kw * 0.08)
        tgt_y1 = max(by, min_ky - kh * 0.04)
        tgt_x2 = min(bx + bw, max_kx + kw * 0.08)
        tgt_y2 = min(by + bh, max_ky + kh * 0.04)
    else:
        tgt_x1, tgt_y1, tgt_x2, tgt_y2 = bx, by, bx + bw, by + bh

    # Projected coordinates inside crop
    rx1 = int(round((tgt_x1 - crop_x0) * scale_to_crop))
    ry1 = int(round((tgt_y1 - crop_y0) * scale_to_crop))
    rx2 = int(round((tgt_x2 - crop_x0) * scale_to_crop))
    ry2 = int(round((tgt_y2 - crop_y0) * scale_to_crop))

    rx1 = max(0, min(crop_w - 1, rx1))
    ry1 = max(0, min(crop_h - 1, ry1))
    rx2 = max(rx1 + 4, min(crop_w, rx2))
    ry2 = max(ry1 + 4, min(crop_h, ry2))

    tgt_cx = (rx1 + rx2) // 2
    tgt_cy = (ry1 + ry2) // 2

    # Aspect ratio cropping centered on target person
    if (crop_w / crop_h) < ratio:
        slice_w = crop_w
        slice_h = min(crop_h, int(crop_w / ratio))
        slice_x = 0
        slice_y = max(0, min(crop_h - slice_h, tgt_cy - slice_h // 2))
    else:
        slice_h = crop_h
        slice_w = min(crop_w, int(crop_h * ratio))
        slice_y = 0
        slice_x = max(0, min(crop_w - slice_w, tgt_cx - slice_w // 2))

    cropped = img[slice_y:slice_y + slice_h, slice_x:slice_x + slice_w]
    ch, cw = cropped.shape[:2]

    bx1 = rx1 - slice_x
    by1 = ry1 - slice_y
    bx2 = rx2 - slice_x
    by2 = ry2 - slice_y

    scale_disp = target_h / max(1.0, ch)
    disp = cv2.resize(cropped, (target_w, target_h), interpolation=cv2.INTER_AREA)

    fx1 = max(0, min(target_w - 2, int(round(bx1 * scale_disp))))
    fy1 = max(0, min(target_h - 2, int(round(by1 * scale_disp))))
    fx2 = max(fx1 + 4, min(target_w, int(round(bx2 * scale_disp))))
    fy2 = max(fy1 + 4, min(target_h, int(round(by2 * scale_disp))))

    # Dim area outside the target so the target person immediately stands out
    mask = np.zeros((target_h, target_w), dtype=np.float32)
    mask[fy1:fy2, fx1:fx2] = 1.0
    mask = cv2.GaussianBlur(mask, (15, 15), 0)
    mask = np.clip(mask[:, :, None], 0.0, 1.0)
    disp = (disp.astype(np.float32) * mask + (disp.astype(np.float32) * 0.65) * (1.0 - mask)).astype(np.uint8)

    neon_bgr = (252, 132, 192)  # Bright neon violet
    # Subtle inner border
    cv2.rectangle(disp, (fx1, fy1), (fx2, fy2), neon_bgr, 1, cv2.LINE_AA)

    # High-contrast corner brackets [ ]
    arm = max(8, min(20, (fx2 - fx1) // 4, (fy2 - fy1) // 6))
    for cx, cy, dx, dy in [(fx1, fy1, 1, 1), (fx2, fy1, -1, 1), (fx1, fy2, 1, -1), (fx2, fy2, -1, -1)]:
        cv2.line(disp, (cx, cy), (cx + dx * arm, cy), (0, 0, 0), 3, cv2.LINE_AA)
        cv2.line(disp, (cx, cy), (cx, cy + dy * arm), (0, 0, 0), 3, cv2.LINE_AA)
        cv2.line(disp, (cx, cy), (cx + dx * arm, cy), neon_bgr, 2, cv2.LINE_AA)
        cv2.line(disp, (cx, cy), (cx, cy + dy * arm), neon_bgr, 2, cv2.LINE_AA)

    # Top indicator badge
    badge_w = min(fx2 - fx1, 52)
    cv2.rectangle(disp, (fx1, max(0, fy1 - 14)), (fx1 + badge_w, fy1), neon_bgr, -1)
    cv2.putText(disp, "TARGET", (fx1 + 3, max(10, fy1 - 3)), cv2.FONT_HERSHEY_SIMPLEX, 0.30,
                (0, 0, 0), 1, cv2.LINE_AA)

    ok, buf = cv2.imencode(".jpg", disp, [cv2.IMWRITE_JPEG_QUALITY, 85])
    return buf.tobytes() if ok else None


def body_thumb_for(body: Optional[Dict], size: int = 200, ratio: float = 0.75,
                   highlight: bool = True) -> Optional[bytes]:
    """Generates or retrieves a cached body thumbnail with target highlighting."""
    if not body:
        return None
    crop_path = body.get("crop_path")
    if not crop_path or not os.path.exists(crop_path):
        return None
    b = body.get("bbox")
    if isinstance(b, dict):
        bbox = (float(b.get("x", 0)), float(b.get("y", 0)), float(b.get("w", 0)), float(b.get("h", 0)))
    elif isinstance(b, (list, tuple)) and len(b) >= 4:
        bbox = (float(b[0]), float(b[1]), float(b[2]), float(b[3]))
    else:
        bbox = (0.0, 0.0, 0.0, 0.0)
    raw_kpts = body.get("kpts") or ()
    kpts_tuple = tuple(tuple(float(v) for v in pt[:3]) for pt in raw_kpts if len(pt) >= 3)
    stamp = _file_stamp(crop_path)
    return _body_thumb_cached(crop_path, stamp, bbox, kpts_tuple, size, ratio, highlight)


@st.cache_data(show_spinner=False, max_entries=8)
def _people_overview(version: int) -> List[Dict]:
    """One row per person with the counts the cards show."""
    db = JsonDatabase()
    rows = {p["id"]: {"id": p["id"], "name": p.get("name") or f"Person {p['id']}",
                      "auto_created": bool(p.get("auto_created")),
                      "updated_at": p.get("updated_at") or "", "created_at": p.get("created_at") or "",
                      "lora": bool(p.get("lora_path") and os.path.exists(p.get("lora_path", ""))),
                      "trigger_word": p.get("trigger_word"),
                      "faces": 0, "bodies": 0, "media": set(), "quality": [], "best": None}
            for p in db.get_all_persons()}
    for face in db.faces.values():
        row = rows.get(face.get("person_id"))
        if row is None:
            continue
        row["faces"] += 1
        row["quality"].append(float(face.get("quality_score") or 0))
        if face.get("media_id") is not None:
            row["media"].add(("m", face["media_id"]))
        elif face.get("source_path"):
            row["media"].add(("p", norm_path(face["source_path"])))
    for body in db.bodies.values():
        row = rows.get(db.body_person_id(body))
        if row is None:
            continue
        row["bodies"] += 1
        if body.get("media_id") is not None:
            row["media"].add(("m", body["media_id"]))
    out = []
    for pid, row in rows.items():
        avatar = db.get_person_avatar_face(pid)
        row["avatar_path"] = (avatar or {}).get("image_path")
        row["avg_quality"] = float(np.mean(row["quality"])) if row["quality"] else 0.0
        photos = videos = 0
        for kind, key in row["media"]:
            record = db.get_media(key) if kind == "m" else None
            if record is None:
                photos += 1
            elif record.get("type") == "video":
                videos += 1
            else:
                photos += 1
        row["photos"], row["videos"], row["media_count"] = photos, videos, len(row["media"])
        for key in ("media", "quality", "best"):
            row.pop(key, None)
        out.append(row)
    out.sort(key=lambda r: -r["faces"])
    return out


@st.cache_data(show_spinner=False, max_entries=8)
def _media_overview(version: int, extra_paths: tuple = ()) -> List[Dict]:
    """Scanned media plus any files on disk that haven't been scanned yet."""
    db = JsonDatabase()
    index = db.media_index()
    names = {p["id"]: (p.get("name") or f"Person {p['id']}") for p in db.get_all_persons()}
    rows = []
    seen = set()
    for mid, record in db.media.items():
        entry = index.get(mid, {})
        people = sorted(entry.get("people", set()))
        rows.append({
            "media_id": mid, "path": record.get("path"), "name": record.get("name") or "",
            "type": record.get("type") or "image", "faces": entry.get("faces", 0),
            "bodies": entry.get("bodies", 0), "people": people,
            "people_names": [names.get(p, "?") for p in people],
            "body_only": sorted(entry.get("body_only_people", set())),
            "duration": record.get("duration"), "scanned": record.get("scan_status") == "done",
            "mtime": record.get("mtime") or 0, "detections": len(record.get("detections") or []),
        })
        seen.add(norm_path(record.get("path", "")))
    for path in extra_paths:
        if norm_path(path) in seen:
            continue
        from library_scanner import is_video
        rows.append({"media_id": None, "path": path, "name": os.path.basename(path),
                     "type": "video" if is_video(path) else "image", "faces": 0, "bodies": 0,
                     "people": [], "people_names": [], "body_only": [], "duration": None,
                     "scanned": False, "mtime": _file_stamp(path), "detections": 0})
    rows.sort(key=lambda r: (-(r["mtime"] or 0), r["name"]))
    return rows


@st.cache_data(show_spinner=False, max_entries=64)
def _disk_media(sources_key: tuple) -> List[str]:
    from library_scanner import collect_media
    files = []
    for path, subfolders, videos in sources_key:
        files.extend(str(f) for f in collect_media(path, subfolders, videos))
    return files


@st.cache_data(show_spinner="Looking for people to group…", max_entries=4)
def _review_state(version: int, strictness: str) -> gg.ReviewState:
    return gg.review_state(JsonDatabase(), strictness)


def clear_caches():
    _people_overview.clear()
    _media_overview.clear()
    _review_state.clear()


# ---------------------------------------------------------------------------
# Small render helpers
# ---------------------------------------------------------------------------

def _esc(text) -> str:
    return (str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace('"', "&quot;"))


def quality_chip(quality: Optional[float]) -> str:
    key, label = face_quality.tier(quality)
    return (f'<span class="gal-chip gal-chip-q gal-q-{key}">'
            f'<span class="gal-dot" style="background:{QUALITY_COLORS[key]}"></span>{label}</span>')


def chip(text: str, kind: str = "") -> str:
    return f'<span class="gal-chip {kind}">{_esc(text)}</span>'


def duration_text(seconds: Optional[float]) -> str:
    if not seconds:
        return ""
    seconds = int(seconds)
    return f"{seconds // 60}:{seconds % 60:02d}"


def empty_state(title: str, body: str, icon: str = "🖼️"):
    html = (
        f'<div class="gal-empty">'
        f'<div class="gal-empty-icon">{icon}</div>'
        f'<h4>{_esc(title)}</h4>'
        f'<p>{_esc(body)}</p>'
        f'</div>'
    )
    st.markdown(html, unsafe_allow_html=True)


def tile(image: Optional[bytes], title: str = "", subtitle: str = "", chips: str = "",
         overlay: str = "", ratio: str = "1 / 1", selected: bool = False, placeholder: str = "👤"):
    """One card: picture, title, subtitle, chips. Actions go below it in Streamlit widgets."""
    uri = data_uri(image)
    picture = (f'<img class="gal-thumb" style="aspect-ratio:{ratio}" src="{uri}">' if uri else
               f'<div class="gal-thumb gal-thumb-empty" style="aspect-ratio:{ratio}">{placeholder}</div>')
    sel_cls = " gal-card-sel" if selected else ""
    title_html = f'<div class="gal-title">{_esc(title)}</div>' if title else ""
    sub_html = f'<div class="gal-sub">{_esc(subtitle)}</div>' if subtitle else ""
    chips_html = f'<div class="gal-chips">{chips}</div>' if chips else ""
    html = (
        f'<div class="gal-card{sel_cls}">'
        f'<div class="gal-media">{picture}{overlay}</div>'
        f'{title_html}'
        f'{sub_html}'
        f'{chips_html}'
        f'</div>'
    )
    st.markdown(html, unsafe_allow_html=True)


def avatar_strip(person_ids: Sequence[int], db: JsonDatabase, limit: int = 4) -> str:
    """Little round faces of everyone in a photo."""
    parts = []
    for pid in list(person_ids)[:limit]:
        face = db.get_person_avatar_face(pid)
        uri = data_uri(thumb_for((face or {}).get("image_path"), 64))
        person = db.get_person(pid) or {}
        title = _esc(person.get("name") or f"Person {pid}")
        parts.append(f'<img class="gal-mini" src="{uri}" title="{title}">' if uri else
                     f'<span class="gal-mini gal-mini-empty" title="{title}">👤</span>')
    if len(person_ids) > limit:
        parts.append(f'<span class="gal-mini gal-mini-more">+{len(person_ids) - limit}</span>')
    return f'<div class="gal-strip">{"".join(parts)}</div>' if parts else ""


def section(title: str, caption: str = "", count: Optional[int] = None):
    badge = f'<span class="gal-count">{count}</span>' if count is not None else ""
    st.markdown(f"""
    <div class="gal-section">
        <div class="gal-section-title">{_esc(title)}{badge}</div>
        {f'<div class="gal-section-caption">{_esc(caption)}</div>' if caption else ''}
    </div>""", unsafe_allow_html=True)


def paginate(items: Sequence, page_size: int, key: str):
    total_pages = max(1, (len(items) + page_size - 1) // page_size)
    page = min(int(st.session_state.get(key, 0)), total_pages - 1)
    st.session_state[key] = page
    if total_pages > 1:
        left, middle, right = st.columns([1, 3, 1])
        with left:
            if st.button("← Previous", key=f"{key}_prev", disabled=page == 0, width="stretch"):
                st.session_state[key] = page - 1
                st.rerun()
        with middle:
            st.markdown(f"<div class='gal-pagelabel'>Page {page + 1} of {total_pages} "
                        f"· {len(items)} items</div>", unsafe_allow_html=True)
        with right:
            if st.button("Next →", key=f"{key}_next", disabled=page >= total_pages - 1,
                         width="stretch"):
                st.session_state[key] = page + 1
                st.rerun()
    return items[page * page_size:(page + 1) * page_size]


# ---------------------------------------------------------------------------
# Context
# ---------------------------------------------------------------------------

@dataclass
class GalleryContext:
    db: JsonDatabase
    navigate_to: Callable[[str], None]
    data_sources: List[Dict]
    set_query: Callable[[str, Optional[str]], None]

    @property
    def strictness(self) -> str:
        return st.session_state.get("gal_strictness", "balanced")

    def strictness_control(self, key: str, label: str = "How eager should grouping be?",
                           label_visibility: str = "visible"):
        """Streamlit keys must be unique, so each place gets its own widget key
        and writes back to the one shared value."""
        def _sync():
            st.session_state["gal_strictness"] = st.session_state[key]
        st.segmented_control(label, ["strict", "balanced", "loose"], default=self.strictness,
                             key=key, on_change=_sync, label_visibility=label_visibility,
                             help="Strict asks you more often; loose groups more on its own.")

    @property
    def detect_bodies(self) -> bool:
        return bool(st.session_state.get("gal_detect_bodies", True))

    def people(self) -> List[Dict]:
        return _people_overview(self.db.version)

    def review(self) -> gg.ReviewState:
        return _review_state(self.db.version, self.strictness)

    def after_change(self, message: str = "", icon: str = "✅"):
        clear_caches()
        if message:
            st.toast(message, icon=icon)


# ---------------------------------------------------------------------------
# Scanning
# ---------------------------------------------------------------------------

def _source_files(ctx: GalleryContext) -> List[str]:
    key = tuple((s["path"], bool(s.get("include_subfolders", True)), bool(s.get("process_videos", True)))
                for s in ctx.data_sources if s.get("path"))
    return _disk_media(key) if key else []


def scan_with_ui(db: JsonDatabase, paths: Sequence[str], strictness: str = "balanced",
                 detect_bodies: bool = True, rescan: bool = False, regroup: bool = True,
                 detect_characters: bool = False):
    """Scan files with a live progress panel, then group. Returns
    (ScanSummary, GroupingSummary | None). Used by the Gallery and by
    Data Sources, so both ingest media exactly the same way."""
    from library_scanner import LibraryScanner, ScanOptions

    with st.status(f"Scanning {len(paths)} files…", expanded=True) as status:
        bar = st.progress(0.0)
        current = st.empty()
        tally = st.empty()
        current.caption("Loading models…")
        face_app, body = (_scanner_models(detect_bodies, True) if detect_characters
                          else _scanner_models(detect_bodies))
        if detect_bodies and body is not None and not body.available:
            st.warning(f"Body detection is off: {body.error}")
        options = ScanOptions.from_env(detect_bodies=detect_bodies, rescan=rescan,
                                       detect_characters=detect_characters)
        scanner = LibraryScanner(db=db, options=options, face_app=face_app, body=body,
                                 log=lambda m: current.caption(m))

        def progress(index, total, path, summary):
            bar.progress(index / max(total, 1))
            current.markdown(f"**{index}/{total}** · {_esc(path.name) if path else 'finishing…'}")
            tally.caption(f"{summary.faces_new} new faces · {summary.faces_linked} already known · "
                          f"{summary.bodies_new} bodies · {summary.files_skipped} unchanged")

        summary = scanner.scan_paths(paths, progress=progress)
        grouping = None
        if regroup and not detect_characters:
            status.update(label="Grouping people…")
            grouping = gg.group_library(db, strictness, log=lambda m: current.caption(m))
        status.update(label=f"Done · {summary.as_text()}", state="complete", expanded=False)
    clear_caches()
    if summary.errors:
        with st.expander(f"{len(summary.errors)} files could not be read"):
            for err in summary.errors[:50]:
                st.caption(err)
    return summary, grouping


def run_scan(ctx: GalleryContext, paths: Sequence[str], rescan: bool = False, regroup: bool = True):
    """Scan files into the gallery, then group what was found."""
    if not paths:
        st.warning("No photos or videos found. Add a folder under **Data Sources** first.")
        return
    summary, grouping = scan_with_ui(ctx.db, paths, ctx.strictness, ctx.detect_bodies, rescan, regroup,
                                     detect_characters=st.session_state.get("gal_detect_characters", False))
    st.session_state["gal_last_scan"] = summary.as_text() + (f" — {grouping.as_text()}" if grouping else "")
    st.rerun()


def run_grouping(ctx: GalleryContext):
    with st.spinner("Grouping people…"):
        summary = gg.group_library(ctx.db, ctx.strictness)
    ctx.after_change(summary.as_text())
    st.rerun()


# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

def render_header(ctx: GalleryContext, stats: Dict, review: gg.ReviewState):
    left, right = st.columns([3, 2], vertical_alignment="center")
    with left:
        st.markdown("<div class='gal-h1'>Gallery</div>"
                    "<div class='gal-h1-sub'>Everyone the app has found in your photos and videos</div>",
                    unsafe_allow_html=True)
    with right:
        scan_col, more_col = st.columns([2, 1])
        with scan_col:
            if st.button("🔍 Scan library", type="primary", width="stretch",
                         help="Look through your data sources for new photos and videos, "
                              "then group the people found"):
                run_scan(ctx, _source_files(ctx))
        with more_col:
            with st.popover("⋯", width="stretch"):
                st.markdown("##### Grouping")
                ctx.strictness_control("gal_strictness_menu")
                st.toggle("Detect bodies", value=ctx.detect_bodies, key="gal_detect_bodies",
                          help="Also find people's bodies, so photos where the face is turned away "
                               "still get linked to them (downloads ~145 MB of models once).")
                st.toggle("Cartoon / anime sources", key="gal_detect_characters",
                          help="Scan illustrated sources by bodies, hair, clothing and visual details instead of human faces. "
                               "Choose illustrated sources before scanning. Uses installed HumanArt models.")
                if st.button("♻️ Group again now", width="stretch"):
                    run_grouping(ctx)
                st.divider()
                st.markdown("##### Library")
                if st.button("🔁 Re-analyse everything", width="stretch",
                             help="Run detection over every file again, including ones already scanned. "
                                  "Your people and corrections are kept."):
                    run_scan(ctx, _source_files(ctx), rescan=True)
                st.caption(f"{stats['total_media']} files scanned · "
                           f"{stats['total_faces']} faces · {stats['total_bodies']} bodies")

    last_scan = st.session_state.pop("gal_last_scan", None)
    if last_scan:
        st.success(last_scan, icon="✅")

    cards = [("People", stats["total_persons"], "gal-stat-violet"),
             ("Faces", stats["total_faces"], "gal-stat-indigo"),
             ("Bodies", stats["total_bodies"], "gal-stat-cyan"),
             ("Photos", stats["total_photos"], "gal-stat-emerald"),
             ("Videos", stats["total_videos"], "gal-stat-emerald"),
             ("To review", review.total, "gal-stat-amber")]
    html = "".join(f"<div class='gal-stat {cls}'><div class='gal-stat-value'>{value}</div>"
                   f"<div class='gal-stat-label'>{label}</div></div>" for label, value, cls in cards)
    st.markdown(f"<div class='gal-stats'>{html}</div>", unsafe_allow_html=True)


# ---------------------------------------------------------------------------
# People
# ---------------------------------------------------------------------------

def render_people(ctx: GalleryContext):
    people = ctx.people()
    review = ctx.review()
    if not people:
        _people_empty_state(ctx)
        return

    bar = st.columns([3, 2, 2, 2], vertical_alignment="bottom")
    with bar[0]:
        query = st.text_input("Search", placeholder="Search people…", key="gal_people_search",
                              label_visibility="collapsed")
    with bar[1]:
        order = st.selectbox("Sort", ["Most faces", "Name", "Recently updated", "Unnamed first"],
                             key="gal_people_sort", label_visibility="collapsed")
    with bar[2]:
        select_mode = st.toggle("Select", key="gal_people_select",
                                help="Pick several people to merge or delete")
    with bar[3]:
        with st.popover("＋ New person", width="stretch"):
            name = st.text_input("Name", key="gal_new_person_name", placeholder="e.g. Sara")
            if st.button("Create", type="primary", width="stretch", key="gal_new_person_go"):
                if name.strip():
                    pid = ctx.db.create_person(name.strip())
                    ctx.after_change(f"Created {name.strip()}")
                    open_person(ctx, pid)

    if review.total:
        pending = []
        if review.suggested_face_count:
            pending.append(f"**{review.suggested_face_count} faces** may belong to people you know")
        if review.groups:
            pending.append(f"**{len(review.groups)} new groups**")
        if review.duplicates:
            pending.append(f"**{len(review.duplicates)} possible duplicates**")
        if review.body_links:
            pending.append(f"**{len(review.body_links)} bodies** to confirm")
        note, action = st.columns([4, 1], vertical_alignment="center")
        note.info(" · ".join(pending), icon="🔎")
        if action.button("Review", width="stretch", key="gal_goto_review"):
            switch_view(ctx, "Review")

    rows = [p for p in people if query.lower().strip() in p["name"].lower()] if query else list(people)
    if order == "Name":
        rows.sort(key=lambda r: r["name"].lower())
    elif order == "Recently updated":
        rows.sort(key=lambda r: r["updated_at"], reverse=True)
    elif order == "Unnamed first":
        rows.sort(key=lambda r: (not r["auto_created"], -r["faces"]))
    else:
        rows.sort(key=lambda r: -r["faces"])

    if not rows:
        empty_state("No one matches that search", "Try a different name.", "🔍")
        return

    selected = st.session_state.setdefault("gal_selected_people", set())
    if select_mode and selected:
        _people_batch_bar(ctx, sorted(selected), people)

    page_rows = paginate(rows, PEOPLE_PER_PAGE, "gal_people_page")
    columns = st.columns(6)
    for i, person in enumerate(page_rows):
        with columns[i % 6]:
            chips = chip(f"👤 {person['faces']}")
            if person["bodies"]:
                chips += chip(f"🧍 {person['bodies']}")
            if person["lora"]:
                chips += chip("LoRA", "gal-chip-lora")
            subtitle = f"{person['photos']} photos · {person['videos']} videos"
            tile(thumb_for(person["avatar_path"], 256), person["name"], subtitle, chips,
                 selected=person["id"] in selected)
            if select_mode:
                checked = st.checkbox("Select", value=person["id"] in selected,
                                      key=f"gal_pchk_{person['id']}", label_visibility="collapsed")
                if checked:
                    selected.add(person["id"])
                else:
                    selected.discard(person["id"])
            if st.button("Open", key=f"gal_open_{person['id']}", width="stretch"):
                open_person(ctx, person["id"])


def _people_empty_state(ctx: GalleryContext):
    if not ctx.data_sources:
        empty_state("Nothing here yet", "Add a folder of photos or videos under Data Sources, "
                                        "then come back and press Scan library.", "📂")
        if st.button("Go to Data Sources", type="primary"):
            ctx.navigate_to("sources")
        return
    files = _source_files(ctx)
    empty_state("No people yet", f"{len(files)} files are waiting in your data sources. "
                                 "Scanning finds the faces and groups them into people.", "✨")
    if st.button("🔍 Scan library now", type="primary"):
        run_scan(ctx, files)


def _people_batch_bar(ctx: GalleryContext, selected: List[int], people: List[Dict]):
    names = {p["id"]: p["name"] for p in people}
    with st.container(border=True):
        st.markdown(f"**{len(selected)} selected** — " + ", ".join(names.get(p, "?") for p in selected[:4])
                    + ("…" if len(selected) > 4 else ""))
        merge_col, delete_col, clear_col = st.columns(3)
        with merge_col:
            with st.popover("🔗 Merge", disabled=len(selected) < 2):
                target = st.selectbox("Keep which person?", selected,
                                      format_func=lambda p: names.get(p, str(p)), key="gal_merge_target")
                if st.button("Merge them", type="primary", width="stretch", key="gal_merge_go"):
                    with ctx.db.batch():
                        for pid in selected:
                            if pid != target:
                                ctx.db.merge_persons(pid, target)
                    st.session_state["gal_selected_people"] = set()
                    ctx.after_change(f"Merged into {names.get(target, target)}")
                    st.rerun()
        with delete_col:
            with st.popover("🗑️ Delete", width="stretch"):
                st.caption("Their faces go back to Review — the photos are never deleted.")
                if st.button(f"Delete {len(selected)} people", type="primary",
                             width="stretch", key="gal_delete_people_go"):
                    with ctx.db.batch():
                        for pid in selected:
                            ctx.db.delete_person(pid)
                    st.session_state["gal_selected_people"] = set()
                    ctx.after_change("Deleted")
                    st.rerun()
        with clear_col:
            if st.button("Clear selection", width="stretch", key="gal_clear_people_sel"):
                st.session_state["gal_selected_people"] = set()
                st.rerun()


def open_person(ctx: GalleryContext, person_id: Optional[int]):
    st.session_state.selected_person_id = person_id
    ctx.set_query("person_id", str(person_id) if person_id else None)
    st.rerun()


def switch_view(ctx: GalleryContext, view: str):
    st.session_state["gal_view"] = view
    ctx.set_query("view", VIEW_SLUGS.get(view, "people"))
    st.rerun()


# ---------------------------------------------------------------------------
# One person
# ---------------------------------------------------------------------------

def render_person(ctx: GalleryContext, person_id: int):
    db = ctx.db
    person = db.get_person(person_id)
    if person is None:
        open_person(ctx, None)
        return
    faces = sorted(db.get_faces_by_person(person_id), key=lambda f: -(f.get("quality_score") or 0))
    bodies = db.get_bodies_by_person(person_id)
    name = person.get("name") or f"Person {person_id}"
    review = ctx.review()
    suggestions = review.suggestions.get(person_id, [])
    duplicates = [d for d in review.duplicates if person_id in (d[0], d[1])]
    body_suggestions = [l for l in review.body_links if l.person_id == person_id]

    if st.button("← All people", key="gal_back", type="tertiary"):
        open_person(ctx, None)

    avatar = db.get_person_avatar_face(person_id)
    head_left, head_right = st.columns([3, 2], vertical_alignment="center")
    with head_left:
        uri = data_uri(thumb_for((avatar or {}).get("image_path"), 220))
        picture = (f'<img class="gal-avatar-lg" src="{uri}">' if uri
                   else '<div class="gal-avatar-lg gal-thumb-empty">👤</div>')
        media_count = len(db.person_media_ids(person_id))
        chips = (chip(f"👤 {len(faces)} faces") + chip(f"🧍 {len(bodies)} bodies")
                 + chip(f"🖼️ {media_count} files")
                 + quality_chip(float(np.mean([f.get('quality_score') or 0 for f in faces])) if faces else 0))
        if person.get("trigger_word"):
            chips += chip(f"LoRA: {person['trigger_word']}", "gal-chip-lora")
        st.markdown(f"""
        <div class="gal-hero">
            {picture}
            <div class="gal-hero-body">
                <div class="gal-hero-name">{_esc(name)}</div>
                <div class="gal-chips">{chips}</div>
            </div>
        </div>""", unsafe_allow_html=True)
    with head_right:
        actions = st.columns(3)
        with actions[0]:
            if st.button("🧬 Train LoRA", width="stretch", key="gal_person_lora"):
                st.session_state["lora_dataset_person"] = person_id
                st.session_state["lora_dataset_source_mode"] = "👥 Use Gallery Person"
                ctx.navigate_to("lora")
        with actions[1]:
            if st.button("🎭 Use in Reface", width="stretch", key="gal_person_reface"):
                st.session_state["v2_source_mode"] = "👥 Gallery Person"
                st.session_state["reface_gallery_person"] = person_id
                st.session_state["v2_data_source_mode"] = "gallery"
                ctx.navigate_to("reface")
        with actions[2]:
            with st.popover("⋯", width="stretch"):
                new_name = st.text_input("Name", value=name, key=f"gal_rename_{person_id}")
                if st.button("Save name", type="primary", width="stretch",
                             key=f"gal_rename_go_{person_id}"):
                    if new_name.strip():
                        db.update_person(person_id, {"name": new_name.strip(), "auto_created": False})
                        ctx.after_change("Renamed")
                        st.rerun()
                st.divider()
                others = [p for p in ctx.people() if p["id"] != person_id]
                if others:
                    target = st.selectbox("Merge into", [p["id"] for p in others],
                                          format_func=lambda p: next(o["name"] for o in others if o["id"] == p),
                                          key=f"gal_merge_into_{person_id}")
                    if st.button("Merge", width="stretch", key=f"gal_merge_into_go_{person_id}"):
                        db.merge_persons(person_id, target)
                        ctx.after_change("Merged")
                        open_person(ctx, target)
                st.divider()
                if st.button("🗑️ Delete person", width="stretch", key=f"gal_del_{person_id}",
                             help="Faces go back to Review. Photos are never deleted."):
                    db.delete_person(person_id)
                    ctx.after_change("Deleted")
                    open_person(ctx, None)

    labels = [f"Faces ({len(faces)})", f"Photos & videos ({media_count})", f"Body shots ({len(bodies)})"]
    pending = len(suggestions) + len(duplicates) + len(body_suggestions)
    labels.append(f"Suggestions ({pending})" if pending else "Suggestions")
    tabs = st.tabs(labels)
    with tabs[0]:
        _person_faces(ctx, person_id, faces, avatar)
    with tabs[1]:
        _person_media(ctx, person_id)
    with tabs[2]:
        _person_bodies(ctx, person_id, bodies)
    with tabs[3]:
        _person_suggestions(ctx, person_id, suggestions, duplicates, body_suggestions)


def _person_faces(ctx: GalleryContext, person_id: int, faces: List[Dict], avatar: Optional[Dict]):
    if not faces:
        empty_state("No faces yet", "Add faces from the Review tab, or scan more media.", "👤")
        return
    controls = st.columns([2, 2, 2], vertical_alignment="bottom")
    with controls[0]:
        tiers = st.pills("Quality", ["Great", "Good", "Fair", "Poor"], selection_mode="multi",
                         key=f"gal_face_tiers_{person_id}", label_visibility="collapsed")
    with controls[1]:
        order = st.selectbox("Sort", ["Best first", "Newest first", "Oldest first"],
                             key=f"gal_face_sort_{person_id}", label_visibility="collapsed")
    with controls[2]:
        select_mode = st.toggle("Select faces", key=f"gal_face_select_{person_id}")

    shown = faces
    if tiers:
        wanted = {t.lower() for t in tiers}
        shown = [f for f in shown if face_quality.tier(f.get("quality_score"))[0] in wanted]
    if order == "Newest first":
        shown = sorted(shown, key=lambda f: f.get("created_at") or "", reverse=True)
    elif order == "Oldest first":
        shown = sorted(shown, key=lambda f: f.get("created_at") or "")

    selected = st.session_state.setdefault(f"gal_sel_faces_{person_id}", set())
    if select_mode:
        _face_batch_bar(ctx, person_id, shown, sorted(selected))
    if not shown:
        empty_state("No faces at that quality", "Try turning off the quality filter.", "🔍")
        return

    avatar_id = (avatar or {}).get("id")
    page = paginate(shown, FACES_PER_PAGE, f"gal_faces_page_{person_id}")
    columns = st.columns(8)
    for i, face in enumerate(page):
        fid = face["id"]
        with columns[i % 8]:
            overlay = ('<span class="gal-corner">★</span>' if fid == avatar_id else "")
            source = os.path.basename(face.get("source_path") or "")
            tile(thumb_for(face.get("image_path"), 200), "", "", quality_chip(face.get("quality_score")),
                 overlay=overlay, selected=fid in selected)
            if select_mode:
                checked = st.checkbox("Pick", value=fid in selected, key=f"gal_fchk_{person_id}_{fid}",
                                      label_visibility="collapsed")
                if checked:
                    selected.add(fid)
                else:
                    selected.discard(fid)
            else:
                with st.popover("⋯", width="stretch"):
                    st.caption(_esc(source) or "unknown source")
                    if face.get("frame_number") is not None:
                        st.caption(f"frame {face['frame_number']} · {duration_text(face.get('timestamp'))}")
                    if st.button("★ Make cover", key=f"gal_cover_{fid}", width="stretch"):
                        ctx.db.set_person_avatar(person_id, fid)
                        ctx.after_change("Cover updated")
                        st.rerun()
                    if st.button("🚫 Not this person", key=f"gal_notp_{fid}", width="stretch"):
                        ctx.db.reject_face_from_person(fid, person_id)
                        ctx.after_change("Moved back to Review")
                        st.rerun()
                    if st.button("🗑️ Delete face", key=f"gal_delf_{fid}", width="stretch"):
                        ctx.db.delete_face(fid, delete_file=True)
                        ctx.after_change("Face deleted")
                        st.rerun()


def _face_batch_bar(ctx: GalleryContext, person_id: int, shown: List[Dict], selected: List[int]):
    with st.container(border=True):
        top = st.columns([2, 2, 4], vertical_alignment="center")
        with top[0]:
            if st.button("Select all shown", key=f"gal_selall_{person_id}", width="stretch"):
                st.session_state[f"gal_sel_faces_{person_id}"] = {f["id"] for f in shown}
                st.rerun()
        with top[1]:
            if st.button("Clear", key=f"gal_selnone_{person_id}", width="stretch",
                         disabled=not selected):
                st.session_state[f"gal_sel_faces_{person_id}"] = set()
                st.rerun()
        with top[2]:
            st.markdown(f"**{len(selected)} selected**" if selected else "Nothing selected")
        if not selected:
            return
        actions = st.columns(3)
        with actions[0]:
            others = [p for p in ctx.people() if p["id"] != person_id]
            with st.popover("➡️ Move to…", disabled=not others):
                target = st.selectbox("Person", [p["id"] for p in others],
                                      format_func=lambda p: next(o["name"] for o in others if o["id"] == p),
                                      key=f"gal_move_target_{person_id}")
                if st.button("Move", type="primary", width="stretch",
                             key=f"gal_move_go_{person_id}"):
                    ctx.db.batch_assign_faces(selected, target)
                    st.session_state[f"gal_sel_faces_{person_id}"] = set()
                    ctx.after_change(f"Moved {len(selected)} faces")
                    st.rerun()
        with actions[1]:
            if st.button("🚫 Not this person", width="stretch", key=f"gal_batch_not_{person_id}"):
                gg.reject_faces(ctx.db, selected, person_id)
                st.session_state[f"gal_sel_faces_{person_id}"] = set()
                ctx.after_change("Moved back to Review")
                st.rerun()
        with actions[2]:
            if st.button("🗑️ Delete", width="stretch", key=f"gal_batch_del_{person_id}"):
                with ctx.db.batch():
                    for fid in selected:
                        ctx.db.delete_face(fid, delete_file=True)
                st.session_state[f"gal_sel_faces_{person_id}"] = set()
                ctx.after_change(f"Deleted {len(selected)} faces")
                st.rerun()


def _person_media(ctx: GalleryContext, person_id: int):
    db = ctx.db
    media_ids = db.person_media_ids(person_id)
    rows = [r for r in _media_overview(db.version) if r["media_id"] in media_ids]
    legacy = [p for p in db.person_source_paths(person_id)
              if not any(r["path"] and norm_path(r["path"]) == norm_path(p) for r in rows)]
    if not rows and not legacy:
        empty_state("No files linked yet", "Scan your library so the gallery knows which "
                                           "photos and videos this person appears in.", "🎬")
        return
    st.caption("Files this person appears in. **Body only** means their face wasn't visible — "
               "they were matched by their outfit in the same video.")
    page = paginate(rows + [{"media_id": None, "path": p, "name": os.path.basename(p),
                             "type": "video" if p.lower().endswith((".mp4", ".mov", ".avi", ".mkv")) else "image",
                             "faces": 0, "bodies": 0, "people": [], "body_only": [], "duration": None,
                             "scanned": False} for p in legacy],
                    MEDIA_PER_PAGE, f"gal_pmedia_page_{person_id}")
    columns = st.columns(4)
    for i, row in enumerate(page):
        with columns[i % 4]:
            _media_card(ctx, row, index=f"p{person_id}_{i}", highlight_person=person_id)


def _person_bodies(ctx: GalleryContext, person_id: int, bodies: List[Dict]):
    if not bodies:
        empty_state("No body shots", "Body detection links photos where the face is small or turned "
                                     "away. Turn it on in the ⋯ menu and scan again.", "🧍")
        return
    st.caption("Whole-person crops linked to this person.")
    page = paginate(sorted(bodies, key=lambda b: -(b.get("score") or 0)), 24,
                    f"gal_bodies_page_{person_id}")
    columns = st.columns(6)
    for i, body in enumerate(page):
        with columns[i % 6]:
            extent = pl.EXTENT_LABELS.get(body.get("extent") or "", "")
            method = body.get("link_method")
            chips = chip(extent) if extent else ""
            if body.get("face_id") is not None:
                chips += chip("via face", "gal-chip-ok")
            elif method:
                chips += chip(LINK_LABELS.get(method, method), "gal-chip-soft")
            tile(body_thumb_for(body, 200, ratio=0.75, highlight=True), "", "", chips, ratio="3 / 4",
                 placeholder="🧍")
            b_acts = st.columns([1, 2])
            with b_acts[0]:
                with st.popover("🔍", help="Inspect in full photo"):
                    _render_body_context(ctx, body)
            with b_acts[1]:
                if st.button("🚫 Unlink", key=f"gal_bodyno_{body['id']}", width="stretch"):
                    ctx.db.reject_body_from_person(body["id"], person_id)
                    ctx.after_change("Unlinked")
                    st.rerun()


def _person_suggestions(ctx: GalleryContext, person_id: int, suggestions, duplicates, body_links):
    if not suggestions and not duplicates and not body_links:
        empty_state("Nothing to confirm", "This person looks fully sorted.", "✅")
        return
    if suggestions:
        section("Faces that might be this person", count=len(suggestions))
        _suggestion_grid(ctx, person_id, suggestions, key=f"person{person_id}")
    if duplicates:
        section("Possibly the same person", count=len(duplicates))
        for a, b, score in duplicates:
            _duplicate_row(ctx, a, b, score)
    if body_links:
        section("Bodies that might be this person", count=len(body_links))
        _body_link_grid(ctx, body_links, key=f"person{person_id}")


# ---------------------------------------------------------------------------
# Review
# ---------------------------------------------------------------------------

def render_review(ctx: GalleryContext):
    db = ctx.db
    review = ctx.review()
    top = st.columns([3, 2, 2], vertical_alignment="center")
    with top[0]:
        st.markdown("<div class='gal-h2'>Review</div>"
                    "<div class='gal-h1-sub'>Confirm what the app isn't sure about</div>",
                    unsafe_allow_html=True)
    with top[1]:
        ctx.strictness_control("gal_strictness_review", "Grouping", label_visibility="collapsed")
    with top[2]:
        if st.button("♻️ Group automatically", width="stretch", key="gal_review_group"):
            run_grouping(ctx)

    if not review.total:
        empty_state("Nothing to review", "Every face is either assigned or too unclear to guess. "
                                         "Scan more media to find new people.", "🎉")
        _unsorted_faces(ctx, review.unsorted_face_ids)
        return

    if review.suggestions:
        section("Faces that look like people you know", "Accept to add them to that person.",
                review.suggested_face_count)
        for pid, items in sorted(review.suggestions.items(), key=lambda kv: -len(kv[1])):
            person = db.get_person(pid) or {}
            avatar = db.get_person_avatar_face(pid)
            head = st.columns([1, 4, 2], vertical_alignment="center")
            with head[0]:
                uri = data_uri(thumb_for((avatar or {}).get("image_path"), 96))
                st.markdown(f'<img class="gal-avatar-sm" src="{uri}">' if uri else "👤",
                            unsafe_allow_html=True)
            with head[1]:
                st.markdown(f"**{_esc(person.get('name') or f'Person {pid}')}** — "
                            f"{len(items)} faces to confirm")
            with head[2]:
                if st.button(f"✓ Accept all {len(items)}", key=f"gal_accept_all_{pid}",
                             width="stretch", type="primary"):
                    gg.accept_faces(db, [s.face_id for s in items], pid)
                    ctx.after_change(f"Added {len(items)} faces")
                    st.rerun()
            _suggestion_grid(ctx, pid, items, key=f"review{pid}")
            st.divider()

    if review.groups:
        section("New groups", "Faces that belong together but aren't anyone you've named yet.",
                len(review.groups))
        for i, group in enumerate(review.groups):
            _group_card(ctx, group, i)

    if review.duplicates:
        section("Possibly the same person", "Two people that look like one.", len(review.duplicates))
        for a, b, score in review.duplicates:
            _duplicate_row(ctx, a, b, score)

    if review.body_links:
        section("Bodies to confirm", "Matched by outfit within the same photo or video.",
                len(review.body_links))
        _body_link_grid(ctx, review.body_links, key="review")

    _unsorted_faces(ctx, review.unsorted_face_ids)


def _suggestion_grid(ctx: GalleryContext, person_id: int, items, key: str):
    columns = st.columns(8)
    for i, suggestion in enumerate(items[:32]):
        face = ctx.db.get_face(suggestion.face_id)
        if not face:
            continue
        with columns[i % 8]:
            tile(thumb_for(face.get("image_path"), 200), "", "",
                 chip(f"{suggestion.score * 100:.0f}% match", "gal-chip-soft"))
            yes, no = st.columns(2)
            if yes.button("✓", key=f"gal_sy_{key}_{suggestion.face_id}", width="stretch",
                          help="Yes, this is them"):
                ctx.db.assign_face_to_person(suggestion.face_id, person_id)
                ctx.after_change("Added")
                st.rerun()
            if no.button("✕", key=f"gal_sn_{key}_{suggestion.face_id}", width="stretch",
                         help="No, someone else"):
                ctx.db.reject_face_from_person(suggestion.face_id, person_id)
                ctx.after_change("Dismissed")
                st.rerun()


def _group_card(ctx: GalleryContext, group: gg.GroupSuggestion, index: int):
    with st.container(border=True):
        left, right = st.columns([4, 2], vertical_alignment="center")
        with left:
            columns = st.columns(8)
            for i, fid in enumerate(group.face_ids[:8]):
                face = ctx.db.get_face(fid)
                with columns[i]:
                    tile(thumb_for((face or {}).get("image_path"), 160))
            st.caption(f"{len(group.face_ids)} faces · they look alike "
                       f"({group.cohesion * 100:.0f}% similar on average)")
        with right:
            name = st.text_input("Name", key=f"gal_group_name_{index}", placeholder="Name this person",
                                 label_visibility="collapsed")
            if st.button("＋ Create person", key=f"gal_group_create_{index}", type="primary",
                         width="stretch"):
                pid = gg.create_person_from_faces(ctx.db, group.face_ids, name.strip() or None)
                ctx.after_change(f"Created {ctx.db.get_person(pid)['name']}")
                st.rerun()
            people = ctx.people()
            if people:
                with st.popover("Add to existing", width="stretch"):
                    target = st.selectbox("Person", [p["id"] for p in people],
                                          format_func=lambda p: next(o["name"] for o in people if o["id"] == p),
                                          key=f"gal_group_target_{index}")
                    if st.button("Add", type="primary", width="stretch",
                                 key=f"gal_group_add_{index}"):
                        gg.accept_faces(ctx.db, group.face_ids, target)
                        ctx.after_change("Added")
                        st.rerun()
            if st.button("Not a group", key=f"gal_group_dismiss_{index}", width="stretch"):
                ctx.db.dismiss_face_group(group.face_ids)
                ctx.after_change("Hidden from suggestions")
                st.rerun()


def _duplicate_row(ctx: GalleryContext, a: int, b: int, score: float):
    db = ctx.db
    with st.container(border=True):
        columns = st.columns([1, 2, 1, 2, 2], vertical_alignment="center")
        for slot, pid in ((0, a), (2, b)):
            face = db.get_person_avatar_face(pid)
            uri = data_uri(thumb_for((face or {}).get("image_path"), 120))
            with columns[slot]:
                st.markdown(f'<img class="gal-avatar-sm" src="{uri}">' if uri else "👤",
                            unsafe_allow_html=True)
        for slot, pid in ((1, a), (3, b)):
            person = db.get_person(pid) or {}
            with columns[slot]:
                st.markdown(f"**{_esc(person.get('name') or f'Person {pid}')}**")
                st.caption(f"{person.get('face_count', 0)} faces")
        with columns[4]:
            st.caption(f"{score * 100:.0f}% alike")
            merge, differ = st.columns(2)
            if merge.button("Merge", key=f"gal_dupm_{a}_{b}", type="primary", width="stretch"):
                db.merge_persons(b, a)
                ctx.after_change("Merged")
                st.rerun()
            if differ.button("Different", key=f"gal_dupd_{a}_{b}", width="stretch"):
                db.mark_persons_distinct(a, b)
                ctx.after_change("Kept separate")
                st.rerun()


def _read_source_frame(path: str, frame_number: Optional[int]):
    """The pixels a detection was made on: the photo itself, or that frame of
    the video (cv2.imread can't open a video, which is how an .mp4 path used to
    reach st.image and blow up in PIL)."""
    import cv2
    from library_scanner import imread, is_video
    if not is_video(path):
        return imread(path)
    cap = cv2.VideoCapture(str(path))
    try:
        if frame_number:
            cap.set(cv2.CAP_PROP_POS_FRAMES, int(frame_number))
        ok, frame = cap.read()
        return frame if ok else None
    finally:
        cap.release()


@st.cache_data(show_spinner=False, max_entries=64)
def _annotated_body_context_bytes(path: str, stamp: float, boxes: tuple, target_body_id: int,
                                  frame_number: Optional[int] = None) -> Optional[bytes]:
    import cv2
    img = _read_source_frame(path, frame_number)
    if img is None:
        return None
    scale = min(1.0, 1400 / max(img.shape[:2]))
    if scale < 1.0:
        img = cv2.resize(img, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)

    target_box = None
    for x, y, w, h, kind, label, ref_id in boxes:
        if kind == "b" and ref_id == target_body_id:
            target_box = (x, y, w, h, kind, label, ref_id)
            continue
        sx, sy, sw, sh = [int(v * scale) for v in (x, y, w, h)]
        color = (226, 43, 138) if kind == "f" else (212, 185, 6)
        cv2.rectangle(img, (sx, sy), (sx + sw, sy + sh), color, 2 if kind == "f" else 1)
        if label:
            (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.45, 1)
            cv2.rectangle(img, (sx, max(0, sy - th - 6)), (sx + tw + 6, sy), color, -1)
            cv2.putText(img, label, (sx + 3, max(10, sy - 4)), cv2.FONT_HERSHEY_SIMPLEX, 0.45,
                        (255, 255, 255), 1, cv2.LINE_AA)

    if target_box:
        x, y, w, h, kind, label, ref_id = target_box
        sx, sy, sw, sh = [int(v * scale) for v in (x, y, w, h)]
        neon_color = (252, 132, 192)  # Bright neon violet
        cv2.rectangle(img, (sx - 1, sy - 1), (sx + sw + 1, sy + sh + 1), (0, 0, 0), 4)
        cv2.rectangle(img, (sx, sy), (sx + sw, sy + sh), neon_color, 3)

        arm = max(12, min(30, sw // 4, sh // 6))
        for cx, cy, dx, dy in [(sx, sy, 1, 1), (sx + sw, sy, -1, 1), (sx, sy + sh, 1, -1), (sx + sw, sy + sh, -1, -1)]:
            cv2.line(img, (cx, cy), (cx + dx * arm, cy), (255, 255, 255), 3, cv2.LINE_AA)
            cv2.line(img, (cx, cy), (cx, cy + dy * arm), (255, 255, 255), 3, cv2.LINE_AA)

        target_lbl = f"★ TARGET: {label}" if label else "★ TARGET BODY"
        (tw, th), _ = cv2.getTextSize(target_lbl, cv2.FONT_HERSHEY_SIMPLEX, 0.55, 2)
        banner_y0 = max(0, sy - th - 10)
        cv2.rectangle(img, (sx, banner_y0), (sx + tw + 12, sy), neon_color, -1)
        cv2.putText(img, target_lbl, (sx + 6, max(12, sy - 5)), cv2.FONT_HERSHEY_SIMPLEX, 0.55,
                    (0, 0, 0), 2, cv2.LINE_AA)

    ok, buf = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 88])
    return buf.tobytes() if ok else None


def _annotated_body_context(db: JsonDatabase, path: str, media_id: Optional[int], target_body_id: int,
                            frame_number: Optional[int] = None) -> Optional[bytes]:
    """The frame this body was seen in, with its neighbours boxed and the body
    itself highlighted. None if the frame can't be read."""
    record = db.get_media(media_id) if media_id else None
    boxes = []
    has_target = False
    for det in (record or {}).get("detections", []) or []:
        det_frame, _, kind, ref, x, y, w, h = det
        if det_frame != frame_number:
            continue  # a video's detections span every sampled frame - keep this one's
        if kind == "f":
            face = db.get_face(ref)
            person = db.get_person(face.get("person_id")) if face and face.get("person_id") else None
            label = (person or {}).get("name") or "Face"
        elif kind == "c":
            character = db.character_samples.get(ref, {})
            identity = db.character_identities.get(character.get("identity_id"), {})
            label = identity.get("name") or f"Character {character.get('identity_id', ref)}"
        else:
            body = db.get_body(ref)
            pid = db.body_person_id(body) if body else None
            pname = (db.get_person(pid) or {}).get("name", "") if pid else ""
            label = f"{pname}" if pname else f"Body {ref}"
            if ref == target_body_id:
                has_target = True
        boxes.append((x, y, w, h, kind, label, ref))

    if not has_target:
        tbody = db.get_body(target_body_id)
        if tbody and tbody.get("bbox"):
            tb = tbody["bbox"]
            bx = tb.get("x", 0) if isinstance(tb, dict) else tb[0]
            by = tb.get("y", 0) if isinstance(tb, dict) else tb[1]
            bw = tb.get("w", 0) if isinstance(tb, dict) else tb[2]
            bh = tb.get("h", 0) if isinstance(tb, dict) else tb[3]
            pid = db.body_person_id(tbody)
            pname = (db.get_person(pid) or {}).get("name", "") if pid else ""
            boxes.append((bx, by, bw, bh, "b", pname or f"Body {target_body_id}", target_body_id))

    return _annotated_body_context_bytes(path, _file_stamp(path), tuple(boxes), target_body_id,
                                         frame_number)


def _render_body_context(ctx: GalleryContext, body: Dict, link=None):
    """Shows full photo with all bodies boxed and the target body highlighted in neon."""
    db = ctx.db
    media_id = body.get("media_id")
    media = db.get_media(media_id) if media_id else None
    path = (media or {}).get("path") or body.get("source_path")
    target_person_id = link.person_id if link else db.body_person_id(body)
    target_person = db.get_person(target_person_id) if target_person_id else None
    target_name = (target_person or {}).get("name") or (f"Person {target_person_id}" if target_person_id else "Unassigned")

    st.markdown(f"**Target Body {body.get('id')} → {target_name}**")
    if link:
        st.caption(f"Suggested Match: **{link.confidence * 100:.0f}%** confidence via {LINK_LABELS.get(link.method, link.method)}")

    frame_number = body.get("frame_number")
    annotated_img = None
    if path and os.path.exists(path):
        annotated_img = _annotated_body_context(db, path, media_id, target_body_id=body.get("id"),
                                                frame_number=frame_number)
    if annotated_img is not None:
        st.image(annotated_img, width="stretch")
        if frame_number is not None:
            st.caption(f"Frame {frame_number}"
                       + (f" · {duration_text(body.get('timestamp'))}" if body.get("timestamp") else ""))
    else:
        crop = body.get("crop_path")
        if crop and os.path.exists(crop):
            st.image(crop, width="stretch")
            st.caption("Showing the saved crop — the original frame couldn't be read.")
        else:
            st.warning("Neither the original file nor the saved crop is on disk any more.")

    if link:
        btn_c1, btn_c2 = st.columns(2)
        if btn_c1.button("✓ Confirm Match", key=f"pop_yes_{link.body_id}_{link.person_id}", type="primary", width="stretch"):
            ctx.db.link_body_to_person(link.body_id, link.person_id, "manual", link.confidence)
            ctx.after_change("Linked")
            st.rerun()
        if btn_c2.button("✕ Dismiss", key=f"pop_no_{link.body_id}_{link.person_id}", width="stretch"):
            ctx.db.reject_body_from_person(link.body_id, link.person_id)
            ctx.after_change("Dismissed")
            st.rerun()


def _body_link_grid(ctx: GalleryContext, links, key: str):
    columns = st.columns(6)
    for i, link in enumerate(links[:24]):
        body = ctx.db.get_body(link.body_id)
        person = ctx.db.get_person(link.person_id) or {}
        if not body:
            continue
        with columns[i % 6]:
            tile(body_thumb_for(body, 200, ratio=0.75, highlight=True), "",
                 person.get("name") or f"Person {link.person_id}",
                 chip(f"{link.confidence * 100:.0f}% · {LINK_LABELS.get(link.method, link.method)}",
                      "gal-chip-soft"), ratio="3 / 4", placeholder="🧍")
            col_yes, col_no, col_inspect = st.columns([1, 1, 1])
            if col_yes.button("✓", key=f"gal_by_{key}_{link.body_id}", width="stretch", help="Confirm match"):
                ctx.db.link_body_to_person(link.body_id, link.person_id, "manual", link.confidence)
                ctx.after_change("Linked")
                st.rerun()
            if col_no.button("✕", key=f"gal_bn_{key}_{link.body_id}", width="stretch", help="Dismiss suggestion"):
                ctx.db.reject_body_from_person(link.body_id, link.person_id)
                ctx.after_change("Dismissed")
                st.rerun()
            with col_inspect:
                with st.popover("🔍", help="Inspect in full photo"):
                    _render_body_context(ctx, body, link)


def _unsorted_faces(ctx: GalleryContext, face_ids: List[int]):
    if not face_ids:
        return
    faces = [ctx.db.get_face(fid) for fid in face_ids]
    faces = [f for f in faces if f]
    low = [f for f in faces if (f.get("quality_score") or 0) < 0.35]
    with st.expander(f"Unsorted faces ({len(faces)})"):
        st.caption("Faces that match nobody yet — usually people who only appear once, "
                   "or blurry detections.")
        tools = st.columns([2, 2, 3])
        with tools[0]:
            with st.popover("Assign all to…", width="stretch"):
                people = ctx.people()
                if people:
                    target = st.selectbox("Person", [p["id"] for p in people],
                                          format_func=lambda p: next(o["name"] for o in people if o["id"] == p),
                                          key="gal_unsorted_target")
                    if st.button("Assign", type="primary", width="stretch",
                                 key="gal_unsorted_assign"):
                        gg.accept_faces(ctx.db, [f["id"] for f in faces], target)
                        ctx.after_change("Assigned")
                        st.rerun()
                else:
                    st.caption("No people yet.")
        with tools[1]:
            if st.button(f"🧹 Discard {len(low)} poor ones", width="stretch",
                         disabled=not low, key="gal_unsorted_discard"):
                with ctx.db.batch():
                    for face in low:
                        ctx.db.delete_face(face["id"], delete_file=True)
                ctx.after_change(f"Discarded {len(low)} faces")
                st.rerun()
        page = paginate(faces, FACES_PER_PAGE, "gal_unsorted_page")
        columns = st.columns(8)
        for i, face in enumerate(page):
            with columns[i % 8]:
                tile(thumb_for(face.get("image_path"), 160), "", "",
                     quality_chip(face.get("quality_score")))
                if st.button("＋ New person", key=f"gal_unsorted_new_{face['id']}",
                             width="stretch"):
                    pid = gg.create_person_from_faces(ctx.db, [face["id"]])
                    ctx.after_change("Created")
                    open_person(ctx, pid)


# ---------------------------------------------------------------------------
# Media
# ---------------------------------------------------------------------------

def render_media(ctx: GalleryContext):
    db = ctx.db
    disk = tuple(_source_files(ctx))
    rows = _media_overview(db.version, disk)
    if not rows:
        empty_state("No media yet", "Add a folder under Data Sources, then scan.", "🎬")
        return
    people = ctx.people()
    names = {p["id"]: p["name"] for p in people}

    filters = st.columns([2, 3, 2, 2], vertical_alignment="bottom")
    with filters[0]:
        kind = st.segmented_control("Type", ["All", "Photos", "Videos"], default="All",
                                    key="gal_media_kind", label_visibility="collapsed")
    with filters[1]:
        who = st.multiselect("People", [p["id"] for p in people], format_func=lambda p: names.get(p, "?"),
                             placeholder="Anyone", key="gal_media_people", label_visibility="collapsed")
    with filters[2]:
        state = st.selectbox("Status", ["All files", "Scanned", "Not scanned yet", "Nobody found"],
                             key="gal_media_state", label_visibility="collapsed")
    with filters[3]:
        query = st.text_input("Search", placeholder="Search file name…", key="gal_media_search",
                              label_visibility="collapsed")

    shown = rows
    if kind == "Photos":
        shown = [r for r in shown if r["type"] == "image"]
    elif kind == "Videos":
        shown = [r for r in shown if r["type"] == "video"]
    if who:
        shown = [r for r in shown if set(who) & set(r["people"])]
    if state == "Scanned":
        shown = [r for r in shown if r["scanned"]]
    elif state == "Not scanned yet":
        shown = [r for r in shown if not r["scanned"]]
    elif state == "Nobody found":
        shown = [r for r in shown if r["scanned"] and not r["people"]]
    if query:
        shown = [r for r in shown if query.lower() in (r["name"] or "").lower()]

    unscanned = [r["path"] for r in rows if not r["scanned"] and r["path"]]
    if unscanned:
        note, action = st.columns([4, 1], vertical_alignment="center")
        note.info(f"{len(unscanned)} files haven't been scanned yet.", icon="📥")
        if action.button("Scan them", width="stretch", key="gal_scan_unscanned"):
            run_scan(ctx, unscanned)

    if not shown:
        empty_state("Nothing matches", "Try clearing the filters.", "🔍")
        return
    page = paginate(shown, MEDIA_PER_PAGE, "gal_media_page")
    columns = st.columns(4)
    for i, row in enumerate(page):
        with columns[i % 4]:
            _media_card(ctx, row, index=f"m{i}")


def _media_card(ctx: GalleryContext, row: Dict, index: str, highlight_person: Optional[int] = None):
    db = ctx.db
    path = row.get("path")
    is_vid = row.get("type") == "video"
    frame = 0
    if is_vid and row.get("media_id"):
        record = db.get_media(row["media_id"]) or {}
        first = next((d for d in (record.get("detections") or []) if d[0]), None)
        frame = int(first[0]) if first else 0
    overlay = ""
    if is_vid:
        overlay = (f'<span class="gal-overlay">▶ {duration_text(row.get("duration")) or "video"}</span>')
    chips = ""
    if row["scanned"]:
        chips += chip(f"👤 {row['faces']}") if row["faces"] else ""
        chips += chip(f"🧍 {row['bodies']}") if row["bodies"] else ""
        if not row["faces"] and not row["bodies"]:
            chips += chip("nobody found", "gal-chip-soft")
        if highlight_person is not None and highlight_person in (row.get("body_only") or []):
            chips += chip("body only", "gal-chip-soft")
    else:
        chips += chip("not scanned", "gal-chip-warn")
    strip = avatar_strip(row.get("people") or [], db)
    tile(thumb_for(path, 320, ratio=4 / 3, video_frame=frame), row.get("name") or "",
         ", ".join(row.get("people_names") or []) or " ", chips, overlay=overlay + strip, ratio="4 / 3",
         placeholder="🎬" if is_vid else "🖼️")
    if st.button("Inspect", key=f"gal_inspect_{index}", width="stretch"):
        st.session_state["gal_inspect"] = row
        st.rerun()


def _close_inspector():
    st.session_state.pop("gal_inspect", None)


@st.dialog("Media", width="large", on_dismiss=_close_inspector)
def _inspector(ctx: GalleryContext, row: Dict):
    db = ctx.db
    path = row.get("path")
    st.markdown(f"**{_esc(row.get('name'))}**")
    st.caption(_esc(path))
    media_id = row.get("media_id")
    record = db.get_media(media_id) if media_id else None
    is_vid = row.get("type") == "video"

    if not is_vid and path and os.path.exists(path):
        annotated = _annotated(ctx, path, media_id)
        if annotated is None:
            st.warning("This file couldn't be opened as an image.")
        else:
            st.image(annotated, width="stretch")
    elif is_vid and path and os.path.exists(path):
        start = st.session_state.get("gal_inspect_start", 0)
        st.video(path, start_time=int(start))
    else:
        st.warning("The file is no longer on disk.")

    if record is None:
        st.info("This file hasn't been scanned yet.")
        if st.button("Scan this file", type="primary"):
            st.session_state.pop("gal_inspect", None)
            run_scan(ctx, [path])
        return

    faces = [f for f in db.faces.values() if f.get("media_id") == media_id]
    bodies = db.get_bodies_by_media(media_id)
    st.caption(f"{len(faces)} faces · {len(bodies)} bodies · "
               f"{record.get('frames_scanned', 1)} frames scanned")

    people = ctx.people()
    for face in sorted(faces, key=lambda f: -(f.get("quality_score") or 0))[:12]:
        columns = st.columns([1, 3, 3], vertical_alignment="center")
        with columns[0]:
            thumb = thumb_for(face.get("image_path"), 80)
            if thumb:
                st.image(thumb)
        with columns[1]:
            person = db.get_person(face.get("person_id")) if face.get("person_id") else None
            st.markdown(f"**{_esc(person['name']) if person else 'Unassigned'}**")
            bits = [face_quality.tier(face.get("quality_score"))[1]]
            if face.get("timestamp") is not None:
                bits.append(f"at {duration_text(face['timestamp'])}")
            st.caption(" · ".join(bits))
        with columns[2]:
            options = [None] + [p["id"] for p in people]
            choice = st.selectbox("Assign", options, index=0, key=f"gal_insp_assign_{face['id']}",
                                  format_func=lambda p: "Assign to…" if p is None else
                                  next(o["name"] for o in people if o["id"] == p),
                                  label_visibility="collapsed")
            if choice is not None and choice != face.get("person_id"):
                db.assign_face_to_person(face["id"], choice)
                ctx.after_change("Assigned")
                st.rerun()
        if is_vid and face.get("timestamp") is not None:
            if st.button(f"▶ Play from {duration_text(face['timestamp'])}",
                         key=f"gal_seek_{face['id']}", type="tertiary"):
                st.session_state["gal_inspect_start"] = int(face["timestamp"])
                st.rerun()

    actions = st.columns(3)
    with actions[0]:
        if st.button("🎭 Use as Reface target", width="stretch"):
            st.session_state["reface_target_path"] = path
            st.session_state["reface_target_is_video"] = is_vid
            st.session_state.pop("gal_inspect", None)
            ctx.navigate_to("reface_v2")
    with actions[1]:
        if st.button("🔁 Scan again", width="stretch"):
            st.session_state.pop("gal_inspect", None)
            run_scan(ctx, [path], rescan=True)
    with actions[2]:
        if st.button("Close", width="stretch"):
            st.session_state.pop("gal_inspect", None)
            st.rerun()


@st.cache_data(show_spinner=False, max_entries=64)
def _annotated_bytes(path: str, stamp: float, boxes: tuple) -> Optional[bytes]:
    import cv2
    from library_scanner import imread
    img = imread(path)
    if img is None:
        return None
    scale = min(1.0, 1400 / max(img.shape[:2]))
    if scale < 1.0:
        img = cv2.resize(img, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
    for x, y, w, h, kind, label in boxes:
        x, y, w, h = [int(v * scale) for v in (x, y, w, h)]
        color = (226, 43, 138) if kind == "f" else (212, 185, 6)
        cv2.rectangle(img, (x, y), (x + w, y + h), color, 2 if kind == "f" else 1)
        if label:
            (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1)
            cv2.rectangle(img, (x, max(0, y - th - 6)), (x + tw + 6, y), color, -1)
            cv2.putText(img, label, (x + 3, max(10, y - 4)), cv2.FONT_HERSHEY_SIMPLEX, 0.5,
                        (255, 255, 255), 1, cv2.LINE_AA)
    ok, buf = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 88])
    return buf.tobytes() if ok else None


def _annotated(ctx: GalleryContext, path: str, media_id: Optional[int]):
    db = ctx.db
    boxes = []
    record = db.get_media(media_id) if media_id else None
    for det in (record or {}).get("detections", []) or []:
        _, _, kind, ref, x, y, w, h = det
        if kind == "f":
            face = db.get_face(ref)
            person = db.get_person(face.get("person_id")) if face and face.get("person_id") else None
            label = (person or {}).get("name") or "Unassigned"
        elif kind == "c":
            character = db.character_samples.get(ref, {})
            identity = db.character_identities.get(character.get("identity_id"), {})
            label = identity.get("name") or f"Character {character.get('identity_id', ref)}"
        else:
            body = db.get_body(ref)
            pid = db.body_person_id(body) if body else None
            label = (db.get_person(pid) or {}).get("name", "") if pid else ""
        boxes.append((x, y, w, h, kind, label))
    # Bytes, or None if the file can't be decoded - never the path itself: handing
    # a video (or a broken file) to st.image raises PIL's UnidentifiedImageError.
    return _annotated_bytes(path, _file_stamp(path), tuple(boxes))


# ---------------------------------------------------------------------------
# Insights
# ---------------------------------------------------------------------------

def render_insights(ctx: GalleryContext):
    import pandas as pd
    import plotly.express as px

    db = ctx.db
    faces = db.get_all_faces()
    people = ctx.people()
    if not faces:
        empty_state("No data yet", "Scan your library to see how it's doing.", "📊")
        return

    assigned = sum(1 for f in faces if f.get("person_id") is not None)
    v2 = sum(1 for f in faces if (f.get("quality_version") or 0) >= face_quality.QUALITY_VERSION)
    metrics = st.columns(4)
    metrics[0].metric("Faces sorted", f"{assigned / len(faces) * 100:.0f}%",
                      help=f"{assigned} of {len(faces)} faces belong to a person")
    metrics[1].metric("People", len(people))
    bodies = db.get_all_bodies()
    linked = sum(1 for b in bodies if db.body_person_id(b) is not None)
    metrics[2].metric("Bodies linked", f"{linked}/{len(bodies)}" if bodies else "0")
    metrics[3].metric("Re-analysed", f"{v2 / len(faces) * 100:.0f}%",
                      help="Faces measured with the current detector and quality score")

    if v2 < len(faces):
        st.info(f"{len(faces) - v2} faces were mined by the old detector. "
                "Re-analyse everything (⋯ menu) to give them the new quality score and link "
                "their photos.", icon="ℹ️")

    charts = st.columns(2)
    with charts[0]:
        with st.container(border=True):
            st.markdown("##### Face quality")
            tiers = [face_quality.tier(f.get("quality_score"))[1] for f in faces]
            frame = pd.DataFrame({"tier": tiers}).value_counts().reset_index(name="faces")
            figure = px.bar(frame, x="tier", y="faces",
                            category_orders={"tier": ["Great", "Good", "Fair", "Poor"]},
                            color="tier", color_discrete_map={
                                "Great": QUALITY_COLORS["great"], "Good": QUALITY_COLORS["good"],
                                "Fair": QUALITY_COLORS["fair"], "Poor": QUALITY_COLORS["poor"]})
            figure.update_layout(template="plotly_dark", paper_bgcolor="rgba(0,0,0,0)",
                                 plot_bgcolor="rgba(0,0,0,0)", showlegend=False, height=300,
                                 margin=dict(l=10, r=10, t=10, b=10))
            st.plotly_chart(figure, width="stretch")
    with charts[1]:
        with st.container(border=True):
            st.markdown("##### Biggest people")
            top = sorted(people, key=lambda p: -p["faces"])[:10]
            if top:
                figure = px.bar(pd.DataFrame({"name": [p["name"] for p in top],
                                              "faces": [p["faces"] for p in top]}),
                                x="faces", y="name", orientation="h", color="faces",
                                color_continuous_scale="Purples")
                figure.update_layout(template="plotly_dark", paper_bgcolor="rgba(0,0,0,0)",
                                     plot_bgcolor="rgba(0,0,0,0)", height=300,
                                     yaxis=dict(autorange="reversed"), coloraxis_showscale=False,
                                     margin=dict(l=10, r=10, t=10, b=10))
                st.plotly_chart(figure, width="stretch")

    with st.container(border=True):
        st.markdown("##### Where people were found")
        index = db.media_index()
        with_people = sum(1 for e in index.values() if e["people"])
        body_only = sum(1 for e in index.values() if e["body_only_people"])
        nobody = len(index) - with_people
        st.markdown(f"- **{with_people}** files have someone you know in them "
                    f"({body_only} of them only by body)\n"
                    f"- **{nobody}** scanned files have nobody identified\n"
                    f"- **{db.get_stats()['total_media']}** files scanned in total")

    with st.expander("Duplicate face crops"):
        st.caption("Near-identical crops (cosine distance < 0.05). They're harmless, "
                   "but removing them trims LoRA datasets.")
        if st.button("Scan for duplicates", key="gal_dupscan"):
            matrix, ids = db._get_embedding_matrix()
            if matrix.size:
                normed = matrix / np.maximum(np.linalg.norm(matrix, axis=1, keepdims=True), 1e-10)
                sim = normed @ normed.T
                np.fill_diagonal(sim, -1)
                pairs = np.argwhere(sim > 0.95)
                pairs = {(min(int(a), int(b)), max(int(a), int(b))) for a, b in pairs}
                if pairs:
                    st.warning(f"{len(pairs)} near-identical pairs")
                    for a, b in list(pairs)[:10]:
                        st.caption(f"Face #{ids[a]} ↔ #{ids[b]} ({sim[a, b]:.3f} similar)")
                else:
                    st.success("No duplicate crops found.")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def render(db: JsonDatabase, navigate_to: Callable[[str], None], data_sources: List[Dict],
           set_query: Callable[[str, Optional[str]], None], view_param: Optional[str] = None,
           person_param: Optional[int] = None):
    ctx = GalleryContext(db=db, navigate_to=navigate_to, data_sources=data_sources, set_query=set_query)

    if person_param is not None and db.get_person(person_param):
        st.session_state.selected_person_id = person_param
    if "gal_view" not in st.session_state:
        st.session_state["gal_view"] = SLUG_VIEWS.get((view_param or "").lower(), "People")

    stats = db.get_stats()
    review = ctx.review()
    render_header(ctx, stats, review)

    labels = {"People": f"👥 People ({stats['total_persons']})", "Characters": "✨ Characters",
              "Review": f"🔎 Review ({review.total})" if review.total else "🔎 Review",
              "Media": f"🎬 Media ({stats['total_media']})", "Insights": "📊 Insights"}
    view = st.segmented_control("View", VIEWS, default=st.session_state["gal_view"],
                                format_func=lambda v: labels[v], key="gal_view_control",
                                label_visibility="collapsed")
    if view and view != st.session_state["gal_view"]:
        st.session_state["gal_view"] = view
        set_query("view", VIEW_SLUGS[view])
    view = st.session_state["gal_view"]

    if st.session_state.get("gal_inspect"):
        _inspector(ctx, st.session_state["gal_inspect"])

    if view == "People":
        person_id = st.session_state.get("selected_person_id")
        if person_id and db.get_person(person_id):
            render_person(ctx, person_id)
        else:
            render_people(ctx)
    elif view == "Characters":
        render_characters(ctx)
    elif view == "Review":
        render_review(ctx)
    elif view == "Media":
        render_media(ctx)
    else:
        render_insights(ctx)
