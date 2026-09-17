"""
ffmpeg_utils.py - Shared FFmpeg discovery and command construction
"""

import os
import subprocess
from pathlib import Path
from typing import Optional, List

_DEFAULT_BUNDLED = Path("d:/AndroidScan/gallary/DeepFaceLab_NVIDIA_RTX3000_series/_internal/ffmpeg/ffmpeg.exe")
_ENV_PATH = os.environ.get("ANTIGRAVITY_FFMPEG", "").strip()
_BUNDLED_FFMPEG = Path(_ENV_PATH) if _ENV_PATH else _DEFAULT_BUNDLED


def _ffmpeg_exe() -> str:
    """Return path to ffmpeg binary (env-configured, bundled, or PATH fallback)."""
    env_str = os.environ.get("ANTIGRAVITY_FFMPEG", "").strip()
    if env_str:
        p = Path(env_str)
        if p.exists():
            return str(p)
    return str(_DEFAULT_BUNDLED) if _DEFAULT_BUNDLED.exists() else "ffmpeg"


def build_mux_command(video_path, source_path, out_path,
                      start_time: float = 0.0, end_time: Optional[float] = None) -> list:
    """ffmpeg args to copy the source's audio onto the rendered video.

    -ss/-to sit before the source input so they trim that input, matching the
    clip range the video was rendered from.
    """
    cmd = [_ffmpeg_exe(), "-y", "-loglevel", "error", "-i", str(video_path)]
    if start_time and start_time > 0:
        cmd += ["-ss", str(start_time)]
    if end_time and end_time > 0:
        cmd += ["-to", str(end_time)]
    cmd += ["-i", str(source_path),
            "-c", "copy", "-map", "0:v:0", "-map", "1:a:0",
            "-shortest", str(out_path)]
    return cmd


def mux_audio(video_path: Path, source_path: str,
              start_time: float = 0.0, end_time: Optional[float] = None) -> bool:
    """Copy the source's audio onto the rendered video, in place.

    Silently does nothing when the source has no audio stream - ffmpeg
    fails the mapping and we keep the silent render.
    """
    video_path = Path(video_path)
    tmp = video_path.with_suffix(".muxed.mp4")
    try:
        proc = subprocess.run(
            build_mux_command(video_path, source_path, tmp, start_time, end_time),
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if proc.returncode == 0 and tmp.exists() and tmp.stat().st_size > 0:
            tmp.replace(video_path)
            return True
    except Exception as e:
        print(f"[ffmpeg_utils] audio mux failed: {e}")
    try:
        tmp.unlink(missing_ok=True)
    except Exception:
        pass
    return False


def concat_list_text(part_paths: List[Path]) -> str:
    """Body of an ffmpeg concat demuxer list file, in the given order."""
    lines = []
    for p in part_paths:
        # Escape single quotes for ffmpeg concat demuxer: file 'path'
        clean_path = str(Path(p).resolve()).replace("'", "'\\''")
        lines.append(f"file '{clean_path}'")
    return "\n".join(lines) + "\n"


def write_concat_list(part_paths: List[Path], list_file: Path) -> Path:
    """Write the concat list file ffmpeg reads, and return its path."""
    Path(list_file).write_text(concat_list_text(part_paths), encoding="utf-8")
    return Path(list_file)


def build_concat_command(part_paths: List[Path], list_file: Path, out_path: Path) -> list:
    """Concat demuxer args. Every part must share codec and resolution,
    which they do because one engine instance rendered them all.

    This also writes the list file, because the returned command is useless
    without it. Use concat_list_text() when only the contents are wanted.
    """
    write_concat_list(part_paths, list_file)

    return [
        _ffmpeg_exe(), "-y", "-loglevel", "error",
        "-f", "concat", "-safe", "0",
        "-i", str(list_file),
        "-c", "copy",
        str(out_path)
    ]
