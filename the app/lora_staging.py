"""
Antigravity Local - LoRA upload staging

The Character LoRA page's "Upload New" source collects photos and videos in
lora_uploads/<character slug>/ before a dataset is built from them. That folder
is the staged list, not Streamlit session state, so a page refresh, a dropped
browser connection or a dashboard restart keeps everything staged so far.

Files arrive two ways:
- import_folder(): straight from a folder on this PC. Nothing goes through the
  browser, so big batches and long videos can't fail half-way. Hard-links when
  the folder is on the same drive (instant, no extra disk space), copies otherwise.
- stage_bytes(): one file from Streamlit's uploader.

Both skip a file that's already staged (same size and same first/last MiB), so
re-running an interrupted import or re-selecting a half-uploaded batch only adds
what's missing. A different file whose name is taken is saved as `name_2.ext`.
"""

import hashlib
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional

from lora_dataset import IMAGE_EXTENSIONS, VIDEO_EXTENSIONS, VIDEO_FRAMES_DIRNAME, _slugify

APP_DIR = Path(__file__).parent
STAGING_ROOT = APP_DIR / "lora_uploads"
MEDIA_EXTENSIONS = IMAGE_EXTENSIONS | VIDEO_EXTENSIONS
# Photo/video formats people have on phones that OpenCV can't read; counted so the import can say so.
UNSUPPORTED_MEDIA_EXTENSIONS = {".heic", ".heif", ".avif", ".gif", ".tif", ".tiff", ".dng", ".raw"}
FINGERPRINT_BYTES = 1 << 20

FOLDER_PICKER_SCRIPT = """
import sys, tkinter as tk
from tkinter import filedialog
root = tk.Tk()
root.withdraw()
root.attributes("-topmost", True)
print(filedialog.askdirectory(title="Choose a folder of photos and videos", initialdir=sys.argv[1] or None) or "")
"""


def staging_dir(character_name: str) -> Path:
    return STAGING_ROOT / _slugify((character_name or "").strip() or "unnamed")


def is_media(path) -> bool:
    return Path(path).suffix.lower() in MEDIA_EXTENSIONS


def list_staged(folder: Path) -> Dict[str, List[Path]]:
    """{"images": [...], "videos": [...]} directly inside folder. Subfolders are skipped: `_frames/`
    holds the frames sampled from staged videos. Half-written `.part` files never match."""
    staged = {"images": [], "videos": []}
    if Path(folder).is_dir():
        for path in sorted(Path(folder).iterdir()):
            suffix = path.suffix.lower()
            if suffix in IMAGE_EXTENSIONS and path.is_file():
                staged["images"].append(path)
            elif suffix in VIDEO_EXTENSIONS and path.is_file():
                staged["videos"].append(path)
    return staged


def _fingerprint(size: int, head: bytes, tail: bytes) -> str:
    return hashlib.sha1(str(size).encode() + b":" + head + tail).hexdigest()


def fingerprint_data(data: bytes) -> str:
    """Cheap identity for a file: its size plus its first and last MiB (whole content when smaller)."""
    size = len(data)
    tail = data[max(size - FINGERPRINT_BYTES, FINGERPRINT_BYTES):] if size > FINGERPRINT_BYTES else b""
    return _fingerprint(size, data[:FINGERPRINT_BYTES], tail)


def fingerprint_file(path) -> str:
    """fingerprint_data() for a file on disk, without reading the middle of a multi-GB video."""
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        head = f.read(FINGERPRINT_BYTES)
        tail = b""
        if size > FINGERPRINT_BYTES:
            f.seek(max(size - FINGERPRINT_BYTES, FINGERPRINT_BYTES))
            tail = f.read()
    return _fingerprint(size, head, tail)


def staged_fingerprints(folder: Path) -> set:
    staged = list_staged(folder)
    return {fingerprint_file(path) for path in staged["images"] + staged["videos"]}


def _free_name(folder: Path, filename: str, fingerprint: str) -> Path:
    """Where a new file goes: its own name when that's free. Names with non-ASCII characters are
    replaced, because OpenCV's imread/VideoCapture can't open such paths on Windows."""
    name = Path(filename).name
    stem, suffix = Path(name).stem, Path(name).suffix.lower()
    if not name.isascii() or not stem.strip(". "):
        stem = f"media_{fingerprint[:12]}"
    target, n = folder / f"{stem}{suffix}", 2
    while target.exists():
        target, n = folder / f"{stem}_{n}{suffix}", n + 1
    return target


def stage_bytes(folder: Path, filename: str, data: bytes, known: Optional[set] = None) -> str:
    """Saves one uploaded file into folder. Returns "added", "duplicate" or "unsupported".
    When staging a batch, pass `known` from staged_fingerprints() so the folder is read once."""
    if not is_media(filename):
        return "unsupported"
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    known = staged_fingerprints(folder) if known is None else known
    fingerprint = fingerprint_data(data)
    if fingerprint in known:
        return "duplicate"
    target = _free_name(folder, filename, fingerprint)
    part = target.with_name(target.name + ".part")
    part.write_bytes(data)
    os.replace(part, target)
    known.add(fingerprint)
    return "added"


def find_media(source: Path, recursive: bool = True, skip: Optional[Path] = None):
    """(media files, count of unsupported photo/video files) under source, leaving out `skip`
    (the staging folder itself, in case it sits inside source). Unreadable subfolders are ignored."""
    skip = Path(skip).resolve() if skip else None
    found, unsupported = [], 0
    for root, dirs, names in os.walk(source):
        root_path = Path(root).resolve()
        if skip and (root_path == skip or skip in root_path.parents):
            dirs.clear()
            continue
        if not recursive:
            dirs.clear()
        for name in sorted(names):
            suffix = Path(name).suffix.lower()
            if suffix in MEDIA_EXTENSIONS:
                found.append(Path(root) / name)
            elif suffix in UNSUPPORTED_MEDIA_EXTENSIONS:
                unsupported += 1
        dirs.sort()
    return found, unsupported


def import_folder(source, folder: Path, recursive: bool = True, progress=None) -> Dict:
    """Stages every photo and video under source into folder.

    Returns {"found", "added", "duplicate", "unsupported", "failed", "errors"}. A file that can't be
    read or written is counted in "failed" and the import carries on with the rest.
    `progress(fraction, text)` is called before each file.
    """
    source, folder = Path(source), Path(folder)
    if not source.is_dir():
        raise NotADirectoryError(f"Not a folder: {source}")
    folder.mkdir(parents=True, exist_ok=True)

    if progress:
        progress(0.0, f"Scanning {source}...")
    files, unsupported = find_media(source, recursive, skip=folder)
    known = staged_fingerprints(folder)
    result = {"found": len(files), "added": 0, "duplicate": 0, "unsupported": unsupported, "failed": 0, "errors": []}

    for i, src in enumerate(files):
        if progress:
            progress(i / len(files), f"Importing {i + 1}/{len(files)}: {src.name}")
        part = None
        try:
            fingerprint = fingerprint_file(src)
            if fingerprint in known:
                result["duplicate"] += 1
                continue
            target = _free_name(folder, src.name, fingerprint)
            part = target.with_name(target.name + ".part")
            part.unlink(missing_ok=True)
            try:
                os.link(src, part)  # same drive: instant and takes no extra space
            except OSError:
                shutil.copyfile(src, part)
            os.replace(part, target)
            known.add(fingerprint)
            result["added"] += 1
        except OSError as e:
            result["failed"] += 1
            result["errors"].append(f"{src}: {e}")
            if part is not None:
                part.unlink(missing_ok=True)

    if progress:
        progress(1.0, "Import finished")
    return result


def move_staged(source_folder: Path, folder: Path) -> Dict[str, int]:
    """Moves everything staged in source_folder into folder (a file folder already has is just
    removed from source_folder). Used to hand files staged before a name was typed to that character."""
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    known = staged_fingerprints(folder)
    staged = list_staged(source_folder)
    result = {"added": 0, "duplicate": 0}
    for path in staged["images"] + staged["videos"]:
        fingerprint = fingerprint_file(path)
        if fingerprint in known:
            path.unlink()
            result["duplicate"] += 1
            continue
        os.replace(path, _free_name(folder, path.name, fingerprint))
        known.add(fingerprint)
        result["added"] += 1
    shutil.rmtree(Path(source_folder) / VIDEO_FRAMES_DIRNAME, ignore_errors=True)
    return result


def clear_staged(folder: Path) -> int:
    """Deletes the staged copies in folder (hard links: an imported original stays where it was)."""
    staged = list_staged(folder)
    for path in staged["images"] + staged["videos"]:
        path.unlink()
    shutil.rmtree(Path(folder) / VIDEO_FRAMES_DIRNAME, ignore_errors=True)
    for part in Path(folder).glob("*.part"):
        part.unlink(missing_ok=True)
    return len(staged["images"]) + len(staged["videos"])


def summarize_staging(result: Dict) -> str:
    """One line for the dashboard about an import or upload batch."""
    parts = [f"Staged {result.get('added', 0)} new file(s)"]
    if result.get("duplicate"):
        parts.append(f"{result['duplicate']} already staged, skipped")
    if result.get("unsupported"):
        parts.append(f"{result['unsupported']} in formats that can't be read (HEIC, GIF, ...), skipped")
    if result.get("failed"):
        parts.append(f"{result['failed']} failed")
    return " · ".join(parts)


def pick_folder(initial: str = "") -> Optional[str]:
    """Native folder picker on the PC running the dashboard; None if cancelled or unavailable.
    Runs as its own process because Tk needs its thread's event loop, and Streamlit runs the
    page script on a worker thread."""
    try:
        picked = subprocess.run(
            [sys.executable, "-c", FOLDER_PICKER_SCRIPT, initial if initial and Path(initial).is_dir() else ""],
            capture_output=True, text=True, encoding="utf-8", timeout=600,
            env=dict(os.environ, PYTHONIOENCODING="utf-8"),
        ).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return None
    return str(Path(picked)) if picked else None
