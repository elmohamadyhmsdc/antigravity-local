"""OPT-IN real-model reference Reface acceptance; never run by ordinary CPU tests.

No API/server is started. Uses the EXACT production adapter and existing local
venv/venv_ai/model paths. Fixtures must be synthetic neutral fully clothed
fictional people/characters. The source is an explicitly chosen face crop.
Default mode checks asset files only. --run-gpu is a deliberate operator opt-in.
This measures selection/locality and retains outputs; identity fidelity and
video aesthetics still require human inspection.
"""
import argparse
import base64
import json
import math
from pathlib import Path
import shutil
import time

import cv2
import numpy as np
from PIL import Image

from mobile_api import reference_reface as rr


def parse_box(text):
    try:
        x, y, w, h = map(float, text.split(","))
        return rr.normalized_box(dict(x=x, y=y, w=w, h=h))
    except (ValueError, TypeError) as exc:
        raise argparse.ArgumentTypeError("Use normalized x,y,w,h inside the target") from exc


def iou(a, b):
    area = max(0, min(a["x"]+a["w"], b["x"]+b["w"])-max(a["x"], b["x"])) * \
           max(0, min(a["y"]+a["h"], b["y"]+b["h"])-max(a["y"], b["y"]))
    return area / max(1e-9, a["w"]*a["h"]+b["w"]*b["h"]-area)


def derive_identity(target, box, kind):
    model = "ccip-caformer24@1" if kind == "character" else "buffalo_l@1"
    probe = np.zeros(rr.IDENTITY_DIMS[model], dtype="<f4")
    probe[0] = 1
    seed_identity = dict(model_id=model, embedding=base64.b64encode(probe.tobytes()).decode("ascii"))
    detector = rr._target_detector(seed_identity)  # SAME local CPU model path as production
    image = cv2.imread(str(target))
    if image is None:
        raise ValueError("The synthetic target photo cannot be decoded")
    candidates = detector(image)
    ranked = sorted(((iou(box, c["box"]), c) for c in candidates), key=lambda row: row[0], reverse=True)
    if not ranked or ranked[0][0] < .35 or (len(ranked) > 1 and ranked[0][0]-ranked[1][0] < .10):
        raise ValueError("The explicit target box does not uniquely select a detected synthetic face")
    vector = np.asarray(ranked[0][1]["embedding"], dtype="<f4")
    return dict(model_id=model, embedding=base64.b64encode(vector.tobytes()).decode("ascii")), len(candidates)


def mask_union(size, boxes):
    mask = np.zeros((size[1], size[0]), dtype=bool)
    for box in boxes:
        _, hard, _ = rr._face_mask(size, box)
        mask |= np.asarray(hard) > 0
    return mask


def locality(original, output, boxes):
    before, after = np.asarray(original), np.asarray(output)
    if before.shape != after.shape:
        raise AssertionError("Output dimensions changed")
    mask = mask_union(original.size, boxes)
    outside = np.abs(after.astype(np.int16)-before.astype(np.int16))[~mask]
    inside = np.abs(after.astype(np.int16)-before.astype(np.int16))[mask]
    maximum = int(outside.max()) if outside.size else 0
    return dict(outside_max_error=maximum, outside_exact=maximum == 0,
                inside_mean_change=float(inside.mean()) if inside.size else 0.0)


def create_clip(target, destination, count=3):
    rgb = rr._open_rgb(target)
    bgr = cv2.cvtColor(np.asarray(rgb), cv2.COLOR_RGB2BGR)
    height, width = bgr.shape[:2]
    temporary = destination.with_suffix(".avi")
    writer = cv2.VideoWriter(str(temporary), cv2.VideoWriter_fourcc(*"MJPG"), 5.0, (width, height))
    if not writer.isOpened():
        raise RuntimeError("The installed OpenCV cannot encode the synthetic clip")
    try:
        for index in range(count):
            # Small real pixel motion exercises current-frame target selection.
            shifted = cv2.warpAffine(bgr, np.float32([[1, 0, index*2], [0, 1, 0]]),
                                     (width, height), borderMode=cv2.BORDER_REFLECT)
            writer.write(shifted)
    finally:
        writer.release()
    temporary.replace(destination)


def prepare_fixture(args):
    if not args.target or not args.output_dir:
        raise ValueError("Fixture preparation requires --target and a fresh --output-dir")
    if args.run_gpu:
        raise ValueError("Prepare fixtures separately from --run-gpu")
    target = args.target.resolve()
    output = args.output_dir.resolve()
    model = "ccip-caformer24@1" if args.target_kind == "character" else "buffalo_l@1"
    vector = np.zeros(rr.IDENTITY_DIMS[model], dtype="<f4")
    vector[0] = 1
    detector = rr._target_detector(dict(model_id=model, embedding=base64.b64encode(vector.tobytes()).decode("ascii")))
    image = cv2.imread(str(target))
    if image is None:
        raise ValueError("The synthetic fixture could not be read")
    candidates = detector(image)
    left = [c for c in candidates if c["box"]["x"]+c["box"]["w"]*.5 < .45]
    right = [c for c in candidates if c["box"]["x"]+c["box"]["w"]*.5 > .55]
    if len(left) != 1 or len(right) != 1:
        boxes = [c["box"] for c in candidates]
        raise ValueError(f"Expected one explicit left and one explicit right face, found: {boxes}")
    output.mkdir(parents=True, exist_ok=False)
    rgb = rr._open_rgb(target)
    rgb.save(output/"target.png")
    box = left[0]["box"]
    width, height = rgb.size
    # Tight reference crop with modest face context; never select by detector order.
    crop = (max(0, int((box["x"]-.15*box["w"])*width)),
            max(0, int((box["y"]-.20*box["h"])*height)),
            min(width, math.ceil((box["x"]+1.15*box["w"])*width)),
            min(height, math.ceil((box["y"]+1.15*box["h"])*height)))
    rgb.crop(crop).save(output/"source-reference.png")
    selected = right[0]["box"]
    result = dict(cpu_fixture_detection=True, gpu_run=False, kind=args.target_kind, model_id=model,
                  detected_count=len(candidates), source_selection="explicit left half", target_selection="explicit right half",
                  source_box=box, target_box=selected,
                  target_box_argument=",".join(format(selected[k], ".10g") for k in ("x", "y", "w", "h")),
                  source_reference=str(output/"source-reference.png"), target=str(output/"target.png"))
    (output/"fixture.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0


def verify_selection(args):
    if args.run_gpu or not args.target or args.target_box is None or not args.output_dir:
        raise ValueError("CPU selection verification needs target, target-box and fresh output-dir; no --run-gpu")
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=False)
    selected, count = derive_identity(args.target, args.target_box, args.target_kind)
    create_clip(args.target, output/"input.target")
    data = rr.locate_video(output/"input.target", output,
                          dict(target_identity=selected, target_kind=args.target_kind, start_time=0, end_time=.6))
    frames = data["frames"]
    summary = dict(gpu_run=False, target_kind=args.target_kind, model_id=selected["model_id"],
                   target_candidates_in_photo=count, frames=frames,
                   all_three_matched=len(frames) == 3 and all(e["status"] == "matched" for e in frames.values()))
    (output/"selection-report.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0 if summary["all_three_matched"] else 1


def ensure_compute_idle():
    from mobile_api.gpu_guard import GpuGuard
    from mobile_dashboard_controller import MobileDashboardController
    guard = GpuGuard(rr.APP_DIR/"jobs", rr.APP_DIR/"mobile_workspace/jobs")
    guard.require_free()
    status = MobileDashboardController(rr.APP_DIR).status()  # read-only local status request
    active = sum(int(device.get("active_jobs", 0)) for device in status.get("devices", []))
    if active or status["state"] in ("starting", "stopping", "external"):
        raise RuntimeError("The existing mobile compute service is busy or cannot be verified idle; nothing was stopped")
    return dict(gpu_guard="free", mobile_server_state=status["state"], active_mobile_jobs=active)


def measure_identity(args):
    if not args.source_reference or not args.target or not args.result or args.target_box is None or not args.output_dir:
        raise ValueError("Identity measurement requires source-reference, target, result, target-box and output-dir")
    if args.source_kind != args.target_kind:
        raise ValueError("Independent identity metrics cannot compare different model spaces")
    def cosine(a, b):
        a, b = np.asarray(a, np.float32).reshape(-1), np.asarray(b, np.float32).reshape(-1)
        return float(np.dot(a/np.linalg.norm(a), b/np.linalg.norm(b)))
    if args.target_kind == "person":
        from insightface.app import FaceAnalysis
        from insightface.model_zoo import get_model
        detector = FaceAnalysis(name="buffalo_l", allowed_modules=["detection"], providers=["CPUExecutionProvider"])
        detector.prepare(ctx_id=-1, det_size=(640, 640))
        recognizer = get_model(str(rr.APP_DIR/"models/eval/glintr100.onnx"), providers=["CPUExecutionProvider"])
        recognizer.prepare(ctx_id=-1)
        def embedding(path, selected_box=None):
            image = cv2.imread(str(path))
            h, w = image.shape[:2]
            faces = detector.get(image)
            if selected_box is None:
                if len(faces) != 1:
                    raise ValueError("The source crop does not contain exactly one measurable face")
                face = faces[0]
            else:
                ranked = sorted(((iou(selected_box, rr._clamped_detection_box(f.bbox, w, h)), f)
                                  for f in faces if rr._clamped_detection_box(f.bbox, w, h) is not None),
                                 key=lambda value: value[0], reverse=True)
                if not ranked or ranked[0][0] < .35:
                    return None
                face = ranked[0][1]
            return recognizer.get(image, face)
        model_name = "independent glintr100 ArcFace (CPU; not the generator/target identity model)"
    else:
        model = "ccip-caformer24@1"
        vector = np.zeros(rr.IDENTITY_DIMS[model], dtype="<f4")
        vector[0] = 1
        detector = rr._target_detector(dict(model_id=model, embedding=base64.b64encode(vector.tobytes()).decode("ascii")))
        def embedding(path, selected_box=None):
            image = cv2.imread(str(path))
            candidates = detector(image)
            if selected_box is None:
                if len(candidates) != 1:
                    raise ValueError("The source crop does not contain exactly one measurable character face")
                return candidates[0]["embedding"]
            ranked = sorted(((iou(selected_box, c["box"]), c) for c in candidates),
                            key=lambda value: value[0], reverse=True)
            return ranked[0][1]["embedding"] if ranked and ranked[0][0] >= .35 else None
        model_name = "CCIP caformer24 (CPU; independent of IP-Adapter's CLIP conditioning)"
    source = embedding(args.source_reference)
    before = embedding(args.target, args.target_box)
    after = embedding(args.result, args.target_box)
    if before is None:
        raise ValueError("The explicitly selected original target could not be measured")
    source_before = cosine(source, before)
    source_after = None if after is None else cosine(source, after)
    summary = dict(gpu_run=False, recognizer=model_name, selected_target="explicit right-face box",
                   source_to_before=source_before, source_to_after=source_after,
                   after_to_before=None if after is None else cosine(after, before),
                   improvement=None if after is None else source_after-source_before,
                   output_face_detected=after is not None,
                   note="Relative measurements only; no threshold was changed to pass; visual identity/artifact review is required.")
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    (output/args.metrics_name).write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


def run(args):
    missing = rr.reference_reface_missing()
    if missing:
        raise FileNotFoundError("Missing local assets: " + ", ".join(missing))
    if args.measure_identity:
        return measure_identity(args)
    if args.prepare_fixture:
        return prepare_fixture(args)
    if args.verify_selection:
        return verify_selection(args)
    if not args.run_gpu:
        print(json.dumps(dict(asset_files_present=True, inference_run=False)))
        return 0
    if not args.source_reference or not args.target or args.target_box is None or not args.output_dir:
        raise ValueError("--run-gpu requires source-reference, target, target-box and output-dir")
    idle = ensure_compute_idle()
    source, target = args.source_reference.resolve(), args.target.resolve()
    output = args.output_dir.resolve()
    # Only write fresh review outputs; never replace a previous smoke or real job.
    output.mkdir(parents=True, exist_ok=False)
    image_dir, video_dir = output/"image", output/"video"
    image_dir.mkdir()
    video_dir.mkdir()
    report = dict(asset_files_present=True, inference_run=True, idle_check=idle, started=time.time(),
                  source_kind=args.source_kind, target_kind=args.target_kind,
                  production_module=str(Path(rr.__file__).resolve()),
                  main_python=str(rr.APP_DIR/"venv/Scripts/python.exe"),
                  generation_python=str(rr.APP_DIR/"venv_ai/Scripts/python.exe"),
                  base=str(rr.APP_DIR/rr.BASE_REL), adapter=str(rr.APP_DIR/rr.ADAPTER_REL),
                  identity_fidelity="requires visual review", temporal_quality="requires visual review")
    (output/"report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    events = []
    def progress(value, message, **details):
        event = dict(progress=value, message=message, **details)
        events.append(event)
        print(json.dumps(event), flush=True)
    try:
        chosen, count = derive_identity(target, args.target_box, args.target_kind)
        report["target_candidates_in_photo"] = count
        report["target_model_id"] = chosen["model_id"]
        if count < 2:
            raise ValueError("Use a target with at least two detected fictional faces to test unselected locality")
        common = dict(experimental_acknowledged=True, source_kind=args.source_kind, target_kind=args.target_kind, seed=args.seed,
                      steps=args.steps, strength=args.strength, reference_scale=.8, initialization=args.initialization)
        report["generation_settings"] = common
        for directory in (image_dir, video_dir):
            shutil.copyfile(source, directory/"input.source_reference")
        shutil.copyfile(target, image_dir/"input.target")
        image_params = dict(common, target_regions=[dict(frame=0, boxes=[args.target_box])])
        ensure_compute_idle()
        print("PHASE: real-model image rendering", flush=True)
        start = time.monotonic()
        report["image_meta"] = rr.run_reference_reface(
            dict(type="reface_image_reference", params=image_params), image_dir, progress, lambda: False)
        report["image_seconds"] = time.monotonic()-start
        before, after = rr._open_rgb(image_dir/"input.target"), rr._open_rgb(image_dir/"result.png")
        report["image_locality"] = locality(before, after, [args.target_box])
        if not report["image_locality"]["outside_exact"]:
            raise AssertionError("Image output changed outside the selected face ellipse")
        if report["image_locality"]["inside_mean_change"] < .25:
            raise AssertionError("The selected face did not change enough to demonstrate rendering")
        if args.image_only:
            report["pixel_tests_passed"] = True
            report["acceptance"] = "image inference completed; identity quality requires review"
            return 0
        create_clip(target, video_dir/"input.target")
        video_params = dict(common, target_identity=chosen, start_time=0, end_time=.6)
        ensure_compute_idle()
        print("PHASE: real-model three-frame video rendering", flush=True)
        start = time.monotonic()
        report["video_meta"] = rr.run_reference_reface(
            dict(type="reface_video_reference", params=video_params), video_dir, progress, lambda: False)
        report["video_seconds"] = time.monotonic()-start
        regions = json.loads((video_dir/"reference.regions.json").read_text(encoding="utf-8"))
        cap = cv2.VideoCapture(str(video_dir/"input.target"))
        checks = []
        try:
            for index in range(3):
                ok, frame = cap.read()
                if not ok:
                    raise AssertionError("Synthetic clip decode failed")
                original = Image.fromarray(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
                rendered = rr._open_rgb(video_dir/"reference.frames"/f"frame_{index:09d}.png")
                entry = regions["frames"][str(index)]
                checks.append(dict(frame=index, selection=entry["status"], boxes=entry["boxes"],
                                   **locality(original, rendered, entry["boxes"])))
        finally:
            cap.release()
        report["video_preencode_locality"] = checks
        if not all(check["outside_exact"] for check in checks):
            raise AssertionError("A decoded output frame changed outside selected face ellipses")
        report["selection_matched_frames"] = sum(check["selection"] == "matched" for check in checks)
        if report["selection_matched_frames"] != 3:
            raise AssertionError("The synthetic right-hand target was not uniquely matched in all three frames")
        if any(check["inside_mean_change"] < .25 for check in checks):
            raise AssertionError("A selected video face did not visibly change")
        report["pixel_tests_passed"] = True
        report["acceptance"] = "real inference completed; inspect identity and flicker before release"
        return 0
    except Exception as exc:
        report["error"] = repr(exc)
        report["acceptance"] = "failed; do not advertise validated quality"
        raise
    finally:
        report["finished"] = time.time()
        report["events"] = events
        report["video_encoding_note"] = "Exact locality is checked on PNG frames before H.264; codec recompression is expected."
        (output/"report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-gpu", action="store_true", help="Explicit opt-in: launches actual production GPU workers")
    parser.add_argument("--prepare-fixture", action="store_true", help="CPU-only model detection and explicit left/right crop preparation")
    parser.add_argument("--verify-selection", action="store_true", help="CPU-only real-model right-target matching on a three-frame clip")
    parser.add_argument("--measure-identity", action="store_true", help="CPU-only independent source-vs-target/output identity measurement")
    parser.add_argument("--metrics-name", default="identity-metrics.json")
    parser.add_argument("--result", type=Path)
    parser.add_argument("--source-reference", type=Path)
    parser.add_argument("--target", type=Path)
    parser.add_argument("--target-box", type=parse_box)
    parser.add_argument("--source-kind", choices=("person", "character"), default="character")
    parser.add_argument("--target-kind", choices=("person", "character"), default="character")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--steps", type=int, choices=range(5, 51), default=20)
    parser.add_argument("--seed", type=int, default=18472)
    parser.add_argument("--strength", type=float, default=.75)
    parser.add_argument("--initialization", choices=("target", "source_pixels"), default="target")
    parser.add_argument("--image-only", action="store_true", help="Bounded image-only quality experiment")
    return run(parser.parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
