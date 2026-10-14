"""Embedding-only adapter over the existing Reface engines; no saved facesets."""

import shutil
import subprocess
import gc
from pathlib import Path

import cv2
import numpy as np

from .schemas import decode_embedding


def match_boxes(boxes, faces, minimum=0.35):
    """Match each selected preview box to one detection, refusing ambiguous/missing picks."""
    selected = []
    for box in boxes:
        x, y, w, h = (box[k] for k in ("x", "y", "w", "h"))
        scores = []
        for face in faces:
            x1, y1, x2, y2 = face.bbox[:4]
            intersection = max(0, min(x + w, x2) - max(x, x1)) * max(0, min(y + h, y2) - max(y, y1))
            union = w * h + (x2 - x1) * (y2 - y1) - intersection
            scores.append(float(intersection / union) if union > 0 else 0)
        if not scores or max(scores) < minimum:
            raise ValueError("A selected face was not found. Detect the target again.")
        index = int(np.argmax(scores))
        if index in selected:
            raise ValueError("Two selected boxes matched the same face. Detect the target again.")
        selected.append(index)
    return selected


def run_reface(job, directory, report, stopped):
    try:
        return _run_reface(job, directory, report, stopped)
    finally:
        # A paused video must release its ONNX sessions before the next queued job.
        engine = job.pop("_engine", None)
        compositor = getattr(engine, "compositor", None)
        pool = getattr(compositor, "_pool", None)
        if pool is not None:
            pool.shutdown(wait=True)
        del pool, compositor, engine
        gc.collect()


def _run_reface(job, directory, report, stopped):
    # Lazy imports: importing the API never loads a model or changes the GPU environment.
    from reface_engine import Faceset, FaceData
    from reface_engine_v3 import RefaceEngineV3
    from ffmpeg_utils import build_concat_command, mux_audio, _ffmpeg_exe

    params = job["params"]
    faceset = Faceset("mobile")
    for face in params["source_faces"]:
        pose = face.get("pose") or {}
        faceset.add_face(FaceData("", decode_embedding(face["embedding"]),
                                 tuple(pose.get(k, 0) or 0 for k in ("yaw", "pitch", "roll")),
                                 [], face["quality"]))
    legacy = job["type"].endswith("_v2")
    if legacy:
        from reface_engine_v2 import RefaceEngineV2
        engine = RefaceEngineV2(output_dir=str(directory / "render"))
    else:
        dfm_path = None
        if job["type"].endswith("_dfm"):
            from .engines import available_dfm_models
            dfm_path = next((m.path for m in available_dfm_models()
                             if m.name == params["dfm_model"]), None)
            if dfm_path is None:
                raise ValueError("The selected DFM model is no longer available.")
        engine = RefaceEngineV3(
            output_dir=str(directory / "render"), dfm_path=dfm_path,
            restorer=None if params.get("restorer", "auto") == "auto" else params["restorer"],
            restorer_weight=params.get("restorer_weight", 0.5),
            use_parser=params.get("use_parser", True), use_occluder=params.get("use_occluder", True),
            realism_preset=params.get("realism_preset", "natural"))
        if dfm_path and engine.dfm is None:
            raise ValueError("The DFM model could not be loaded.")
    job["_engine"] = engine
    if stopped():
        return None
    target = directory / "input.target"
    is_video = job["type"].startswith("reface_video")
    selected = references = None
    if params.get("target_faces"):
        img = cv2.imread(str(target))
        if img is None:
            raise ValueError("The target photo could not be opened.")
        detected = engine.app.get(img) if legacy else engine._detect(img, embeddings=True)
        selected = match_boxes(params["target_faces"], detected)
        references = [f.normed_embedding for f in detected]
    if not is_video:
        report(0.1, "Swapping selected faces")
        result = (engine.reface_with_faceset_v2(str(target), faceset, selected)
                  if legacy else engine.reface_image_v3(str(target), faceset, selected, references))
        if not result.success or not result.output_path:
            raise ValueError(result.message)
        # V2 writes JPEG: encode the decoded output so the public filename and MIME are true.
        output = cv2.imread(result.output_path)
        if output is None or not cv2.imwrite(str(directory / "result.png"), output):
            raise ValueError("The result photo could not be saved.")
        return {"faces_swapped": result.faces_swapped}

    cap = cv2.VideoCapture(str(target))
    try:
        fps = cap.get(cv2.CAP_PROP_FPS)
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        if not np.isfinite(fps) or fps <= 0 or total <= 0:
            raise ValueError("The target video has no readable duration.")
        rounding = int if legacy else round
        first = rounding(params.get("start_time", 0) * fps)
        end = min(total, rounding(params["end_time"] * fps)) if params.get("end_time") else total
        if first >= end:
            raise ValueError("The trim range is outside this video.")
        length = end - first
    finally:
        cap.release()
    base = job.get("_frames_done", 0)
    done = 0

    def progress(count, _total):
        nonlocal done
        done = count
        report(min(0.98, (base + count) / length), "Rendering video",
               frames_done=base + count, last_frame=first + base + count - 1)
        return not stopped()

    kwargs = dict(progress_callback=progress, start_time=params.get("start_time", 0),
                  end_time=params.get("end_time"), resume_from_frame=base, finalize=False)
    if legacy:
        result = engine.reface_video_with_faceset_v2(str(target), faceset, **kwargs)
    else:
        result = engine.reface_video_v3(str(target), faceset, **kwargs)
    if not result.success or not result.output_path:
        raise ValueError(result.message)
    if legacy:
        # V2 returns its AVI part before its final progress callback. Read the
        # actual frame count, including clips shorter than its five-frame tick.
        part = cv2.VideoCapture(result.output_path)
        try:
            done = int(part.get(cv2.CAP_PROP_FRAME_COUNT))
        finally:
            part.release()
        if done <= 0:
            raise ValueError('The video part has no readable frames.')
        report(min(.98,(base+done)/length),'Rendering video',frames_done=base+done,last_frame=first+base+done-1)
    job.setdefault("_parts", []).append(result.output_path)
    job["_frames_done"] = base + done
    if stopped() and job["_frames_done"] < length:
        return None
    # A truncated decode must not be reported as a complete video.
    if job["_frames_done"] != length:
        raise ValueError("The video ended before all requested frames were rendered.")
    parts = [Path(p) for p in job["_parts"]]
    output = directory / "result.mp4"
    joined = directory/'joined.avi' if legacy else output
    if len(parts) == 1:
        if legacy:
            joined=parts[0]
        else:
            shutil.copyfile(parts[0], output)
    else:
        command = build_concat_command(parts, directory / "parts.txt", joined)
        subprocess.run(command, capture_output=True, check=True, timeout=600)
    if legacy:
        subprocess.run([_ffmpeg_exe(),'-y','-loglevel','error','-i',str(joined),'-c:v','libx264',
                        '-preset','medium','-crf','16','-pix_fmt','yuv420p','-an',str(output)],
                       capture_output=True,check=True,timeout=600)
    mux_audio(output, str(target), params.get("start_time", 0), params.get("end_time"))
    return {"frames_done": job["_frames_done"], "fps": fps}
