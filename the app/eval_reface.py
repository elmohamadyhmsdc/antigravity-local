"""
Antigravity Local - Reface quality harness (read-only)

Swaps known people onto test videos with each engine configuration and
measures what matters, so model and setting choices are made from numbers:

  identity    cosine of the swapped face to the person's held-out real photos,
              measured with an independent recogniser (antelopev2 glintr100).
              The swappers are conditioned on buffalo_l's w600k embedding, so
              scoring with that same model would flatter them.
  leak        cosine of the swapped face to the original target face (lower =
              more of the target's identity replaced)
  flicker     frame-to-frame change of the aligned output face divided by the
              same for the source video: 1.0 = as steady as the original,
              above 1 = the swap adds shimmer
  id_wobble   standard deviation of the identity score across frames
  sharpness   Laplacian variance of the output face / the original face
  ms/frame    the engine's own time per frame (metrics excluded)

People: every lora_datasets/<person>/ with real photos (*_body.jpg). Even
photos build the identity (identity_builder, the same code the UI uses); odd
photos are held out as the reference it is scored against.
Targets: the DeepFaceLab sample videos (workspace/data_dst.mp4 and
data_src.mp4), a few seconds each.

    venv\\Scripts\\python.exe eval_reface.py                       # swappers, then restorers, then occluders
    venv\\Scripts\\python.exe eval_reface.py --stage swappers
    venv\\Scripts\\python.exe eval_reface.py --people hanoo,pass --seconds 2

Writes reface_output/eval/<timestamp>/ (report.json, report.md, sheet.png).
Nothing in data/, facesets/ or identities/ is touched.
"""

import argparse
import contextlib
import gc
import io
import json
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

import cv2
import numpy as np

APP = Path(__file__).parent
DFL_WORKSPACE = APP.parent / "DeepFaceLab_NVIDIA_RTX3000_series" / "workspace"
RECOGNISER = APP / "models" / "eval" / "glintr100.onnx"
OUT_ROOT = APP / "reface_output" / "eval"

# (label, engine kwargs). Stage 2 and 3 reuse the winner of the stage before.
SWAPPER_STAGE = [
    ("inswapper_128", {"swapper": "inswapper_128"}),
    ("hyperswap_1b_256", {"swapper": "hyperswap_1b_256"}),
    ("hyperswap_1c_256", {"swapper": "hyperswap_1c_256"}),
]
RESTORER_STAGE = ["codeformer", "gpen_bfr_512", "gpen_bfr_1024", "gfpgan_1.4", "restoreformer_plus_plus", "none"]
OCCLUDER_STAGE = [("xseg_1", ["xseg_1"]), ("xseg_1+xseg_2", ["xseg_1", "xseg_2"])]
BOOST_STAGE = [0.0, 0.5, 1.0]


def quiet():
    return contextlib.redirect_stdout(io.StringIO())


# --- data ---------------------------------------------------------------------

def dataset_people(only: Optional[List[str]] = None) -> Dict[str, List[str]]:
    root = APP / "lora_datasets"
    people = {}
    for d in sorted(p for p in root.iterdir() if p.is_dir()) if root.exists() else []:
        if only and d.name not in only:
            continue
        photos = sorted(str(p) for p in d.glob("*person/*_body.jpg"))
        if len(photos) >= 8:
            people[d.name] = photos
    return people


def clip_frames(path: Path, start_s: float, seconds: float, max_side: int = 1920) -> List[np.ndarray]:
    cap = cv2.VideoCapture(str(path))
    fps = float(cap.get(cv2.CAP_PROP_FPS) or 25.0)
    cap.set(cv2.CAP_PROP_POS_FRAMES, int(start_s * fps))
    frames = []
    for _ in range(int(seconds * fps)):
        ok, f = cap.read()
        if not ok:
            break
        frames.append(f)
    cap.release()
    return frames


# --- measuring ----------------------------------------------------------------

class Judge:
    """Detection (buffalo_l det_10g) + the independent recogniser."""

    def __init__(self, providers):
        from insightface.app import FaceAnalysis
        from insightface.model_zoo import get_model

        with quiet():
            self.det = FaceAnalysis(name="buffalo_l", allowed_modules=["detection"], providers=providers)
            self.det.prepare(ctx_id=0, det_size=(640, 640))
            self.rec = get_model(str(RECOGNISER), providers=providers)
            self.rec.prepare(ctx_id=0)

    def faces(self, img):
        return self.det.get(img)

    def embed(self, img, face) -> np.ndarray:
        e = np.asarray(self.rec.get(img, face), np.float32)
        return e / max(float(np.linalg.norm(e)), 1e-8)

    def reference(self, photos: List[str]) -> Optional[np.ndarray]:
        embs = self.embeddings(photos)
        if not embs:
            return None
        m = np.mean(embs, 0)
        return m / np.linalg.norm(m)

    def embeddings(self, photos: List[str]) -> List[np.ndarray]:
        """Independent embedding of the largest face in each photo."""
        embs = []
        for p in photos:
            img = cv2.imread(p)
            if img is None:
                continue
            fs = self.faces(img)
            if fs:
                f = max(fs, key=lambda x: (x.bbox[2] - x.bbox[0]) * (x.bbox[3] - x.bbox[1]))
                embs.append(self.embed(img, f))
        return embs


def nearest(faces, bbox):
    """The detected face whose centre is closest to bbox's centre."""
    if not faces:
        return None
    cx, cy = (bbox[0] + bbox[2]) / 2, (bbox[1] + bbox[3]) / 2
    return min(faces, key=lambda f: ((f.bbox[0] + f.bbox[2]) / 2 - cx) ** 2 + ((f.bbox[1] + f.bbox[3]) / 2 - cy) ** 2)


def aligned(img, kps, size=256):
    from face_compositor import alignment_matrix
    m = alignment_matrix(kps, size)
    return cv2.warpAffine(img, m, (size, size), borderMode=cv2.BORDER_REPLICATE)


def lap_var(img):
    return float(cv2.Laplacian(cv2.cvtColor(img, cv2.COLOR_BGR2GRAY), cv2.CV_64F).var())


def run_clip(engine, source, frames, judge: Judge, reference: np.ndarray) -> Dict:
    """Swap every frame of a clip and score it."""
    engine.begin_video()
    ids, leaks, sharp, d_out, d_src, times = [], [], [], [], [], []
    prev_out = prev_src = None
    keep = None
    for i, frame in enumerate(frames):
        t0 = time.perf_counter()
        with quiet():
            out, _, faces = engine.render_frame(frame.copy(), source, i)
        times.append((time.perf_counter() - t0) * 1000)
        if not faces:
            prev_out = prev_src = None
            continue
        target = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))
        swapped = nearest(judge.faces(out), target.bbox)
        if swapped is None:
            continue
        e_out = judge.embed(out, swapped)
        e_src = judge.embed(frame, target)
        ids.append(float(e_out @ reference))
        leaks.append(float(e_out @ e_src))
        a_out, a_src = aligned(out, target.kps), aligned(frame, target.kps)
        sharp.append(lap_var(a_out) / max(lap_var(a_src), 1e-6))
        if prev_out is not None:
            d_out.append(float(np.mean(np.abs(a_out.astype(np.float32) - prev_out))))
            d_src.append(float(np.mean(np.abs(a_src.astype(np.float32) - prev_src))))
        prev_out, prev_src = a_out.astype(np.float32), a_src.astype(np.float32)
        if i == len(frames) // 2:
            keep = (frame, out, target.bbox)
    return {
        "frames": len(frames), "scored": len(ids),
        "identity": float(np.mean(ids)) if ids else None,
        "id_wobble": float(np.std(ids)) if ids else None,
        "leak": float(np.mean(leaks)) if leaks else None,
        "sharpness": float(np.median(sharp)) if sharp else None,
        "flicker": float(np.mean(d_out) / max(np.mean(d_src), 1e-6)) if d_out else None,
        "ms_per_frame": float(np.median(times[2:] if len(times) > 4 else times)),
        "_sample": keep,
    }


# --- the run ------------------------------------------------------------------

def model_missing(kwargs) -> Optional[str]:
    """The file a config needs but doesn't have (it would silently fall back)."""
    from face_masking import MODELS_DIR, OCCLUDER_FILES
    from face_restore import RESTORER_FILES
    from face_swappers import SWAPPERS
    need = []
    if kwargs.get("swapper") in SWAPPERS:
        need.append(SWAPPERS[kwargs["swapper"]][0])
    if kwargs.get("restorer") in RESTORER_FILES:
        need.append(RESTORER_FILES[kwargs["restorer"]])
    need += [OCCLUDER_FILES.get(o, f"{o}.onnx") for o in kwargs.get("occluders") or []]
    return next((n for n in need if not (MODELS_DIR / n).exists()), None)


def evaluate(label, kwargs, people, clips, judge, out_dir) -> Dict:
    from identity import build_source_from_faceset
    from reface_engine_v3 import RefaceEngineV3

    with quiet():
        engine = RefaceEngineV3(output_dir=str(out_dir), **kwargs)
    rows = []
    for person, info in people.items():
        source = build_source_from_faceset(info["faceset"])
        for clip_name, frames in clips.items():
            r = run_clip(engine, source, frames, judge, info["reference"])
            r.update(person=person, clip=clip_name, config=label)
            rows.append(r)
            print(f"   {label:28s} {person:12s} {clip_name:9s} id={_f(r['identity'])} leak={_f(r['leak'])} "
                  f"flicker={_f(r['flicker'])} sharp={_f(r['sharpness'])} {r['ms_per_frame']:.0f} ms/f", flush=True)
    del engine
    gc.collect()
    return {"label": label, "kwargs": kwargs, "rows": rows, "summary": summarise(rows)}


def _f(v):
    return "  -  " if v is None else f"{v:.3f}"


def summarise(rows) -> Dict:
    def mean(k):
        v = [r[k] for r in rows if r.get(k) is not None]
        return float(np.mean(v)) if v else None
    return {k: mean(k) for k in ("identity", "id_wobble", "leak", "flicker", "sharpness", "ms_per_frame")}


def rank(results) -> List[Dict]:
    """Identity first; within 0.015 of the best (run-to-run noise), the
    sharper result wins, then the steadier identity.

    Flicker only counts against a config when it is above the source's own
    (> 1.03): a blurrier face changes less between frames, so rewarding low
    flicker would reward blur - the first version of this ranking picked "no
    restorer" that way.
    """
    ok = [r for r in results if r["summary"]["identity"] is not None]
    if not ok:
        return results
    best = max(r["summary"]["identity"] for r in ok)
    close = [r for r in ok if r["summary"]["identity"] >= best - 0.015]
    # Sharpness and leak rounded to 2 places: third-decimal differences are
    # run-to-run noise and must not decide (they once picked identity boost 0
    # over 0.5 on a 0.0002 sharpness gap while 0.5 cut leak by 0.06).
    close.sort(key=lambda r: ((r["summary"]["flicker"] or 9) > 1.03,
                              -round(r["summary"]["sharpness"] or 0, 2),
                              round(r["summary"]["leak"] or 9, 2),
                              r["summary"]["id_wobble"] or 9))
    rest = sorted([r for r in ok if r not in close], key=lambda r: -r["summary"]["identity"])
    return close + rest


def contact_sheet(stage_results, path: Path):
    """Middle frame of the first person's first clip, every config side by side."""
    tiles = []
    for res in stage_results:
        sample = next((r["_sample"] for r in res["rows"] if r.get("_sample")), None)
        if sample is None:
            continue
        frame, out, bbox = sample
        x1, y1, x2, y2 = [int(v) for v in bbox]
        pad = int((x2 - x1) * 0.6)
        crop = lambda im: im[max(0, y1 - pad):y2 + pad, max(0, x1 - pad):x2 + pad]
        if not tiles:
            tiles.append(("original", cv2.resize(crop(frame), (320, 320))))
        tiles.append((res["label"], cv2.resize(crop(out), (320, 320))))
    if not tiles:
        return
    sheet = np.full((350, 330 * len(tiles), 3), 255, np.uint8)
    for i, (name, im) in enumerate(tiles):
        sheet[25:345, i * 330 + 5:i * 330 + 325] = im
        cv2.putText(sheet, name[:30], (i * 330 + 8, 18), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 1, cv2.LINE_AA)
    cv2.imwrite(str(path), sheet)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--stage", default="all", choices=["all", "swappers", "restorers", "occluders", "boost"])
    ap.add_argument("--people", default="", help="comma-separated lora_datasets names (default: all)")
    ap.add_argument("--seconds", type=float, default=3.0, help="seconds of each test clip")
    ap.add_argument("--swapper", default="inswapper_128", help="base swapper for a restorers/occluders-only run")
    ap.add_argument("--restorer", default="codeformer", help="base restorer for an occluders/boost run")
    ap.add_argument("--occluders", default="xseg_1", help="base occluders (comma-separated) for a boost run")
    args = ap.parse_args(argv)

    from cuda_dll_dirs import add_nvidia_dll_dirs
    add_nvidia_dll_dirs()
    from identity_builder import build_identity
    from reface_engine import Faceset, FaceData

    if not RECOGNISER.exists():
        print(f"Missing {RECOGNISER} (antelopev2 glintr100) - the independent recogniser.")
        return 1
    providers = ["CUDAExecutionProvider", "CPUExecutionProvider"]
    judge = Judge(providers)

    clips = {}
    for name in ("data_dst", "data_src"):
        p = DFL_WORKSPACE / f"{name}.mp4"
        if p.exists():
            clips[name] = clip_frames(p, 5.0, args.seconds)
    if not clips:
        print(f"No test videos in {DFL_WORKSPACE}")
        return 1

    from insightface.app import FaceAnalysis
    with quiet():
        full = FaceAnalysis(name="buffalo_l", providers=providers)
        full.prepare(ctx_id=0, det_size=(640, 640))

    people = {}
    only = [p for p in args.people.split(",") if p] or None
    for person, photos in dataset_people(only).items():
        build, held = photos[0::2], photos[1::2]
        with quiet():
            identity, report = build_identity(person, build, full)
        reference = judge.reference(held)
        if identity is None or reference is None:
            print(f"skip {person}: {report.get('reason', 'no held-out reference')}")
            continue
        fs = Faceset(name=person)
        for f in identity.faces:
            fs.add_face(FaceData(image_path=f.source, embedding=f.embedding, pose=(f.yaw, f.pitch, 0.0),
                                 bbox=list(f.bbox), quality=f.quality))
        # The ceiling: how a single real photo of the person scores against the
        # held-out set. A swap can't be expected to look more like them than that.
        own = judge.embeddings(sorted({f.source for f in identity.faces}))
        base = float(np.mean([e @ reference for e in own])) if own else 0.0
        people[person] = {"faceset": fs, "reference": reference, "kept": len(identity.faces),
                          "build_photos": len(build), "held_out": len(held), "real_vs_real": base}
        print(f"{person}: identity from {len(identity.faces)}/{len(build)} photos, "
              f"{len(held)} held out; a real photo scores {base:.3f} against the held-out set (ceiling)")
    del full
    gc.collect()
    if not people:
        print("No usable people in lora_datasets/")
        return 1

    out_dir = OUT_ROOT / datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir.mkdir(parents=True, exist_ok=True)
    stages = {}

    def run_stage(name, configs):
        print(f"\n== {name} ==")
        res = []
        for label, kw in configs:
            missing = model_missing(kw)
            if missing:
                print(f"   {label}: skipped, models/{missing} not downloaded")
                continue
            res.append(evaluate(label, kw, people, clips, judge, out_dir))
        ranked = rank(res)
        contact_sheet(res, out_dir / f"sheet_{name}.png")
        stages[name] = ranked
        return ranked[0]["kwargs"]

    best = {"swapper": args.swapper, "restorer": args.restorer, "occluders": args.occluders.split(",")}
    if args.stage in ("all", "swappers"):
        best = {**best, **run_stage("swappers", [(lab, {**kw, "restorer": best["restorer"]})
                                                 for lab, kw in SWAPPER_STAGE])}
    if args.stage in ("all", "restorers"):
        best = dict(run_stage("restorers", [(f"{best['swapper']}+{r}", {**best, "restorer": r})
                                            for r in RESTORER_STAGE]))
    if args.stage in ("all", "occluders"):
        best = dict(run_stage("occluders", [(f"{lab}", {**best, "occluders": occ}) for lab, occ in OCCLUDER_STAGE]))
    if args.stage in ("all", "boost"):
        best = dict(run_stage("boost", [(f"identity_boost {b}", {**best, "identity_boost": b}) for b in BOOST_STAGE]))

    report = {"people": {k: {kk: vv for kk, vv in v.items() if kk not in ("faceset", "reference")}
                         for k, v in people.items()},
              "clips": {k: len(v) for k, v in clips.items()},
              "stages": {n: [{"label": r["label"], "kwargs": r["kwargs"], "summary": r["summary"],
                              "rows": [{k: v for k, v in row.items() if k != "_sample"} for row in r["rows"]]}
                             for r in rs] for n, rs in stages.items()},
              "winner": best}
    (out_dir / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    lines = ["# Reface evaluation", "", f"People: {', '.join(people)}  |  clips: "
             + ", ".join(f"{k} ({v} frames)" for k, v in report["clips"].items()), "",
             "Ceiling (a real photo of the person vs their held-out photos): "
             + ", ".join(f"{k} {v['real_vs_real']:.3f}" for k, v in report["people"].items()), ""]
    for n, rs in stages.items():
        lines += [f"## {n}", "", "| config | identity | leak | flicker | id wobble | sharpness | ms/frame |",
                  "|---|---|---|---|---|---|---|"]
        for r in rs:
            s = r["summary"]
            lines.append(f"| {r['label']} | {_f(s['identity'])} | {_f(s['leak'])} | {_f(s['flicker'])} | "
                         f"{_f(s['id_wobble'])} | {_f(s['sharpness'])} | {s['ms_per_frame']:.0f} |")
        lines.append("")
    lines.append(f"Winner: `{best}`")
    (out_dir / "report.md").write_text("\n".join(lines), encoding="utf-8")
    print("\n" + "\n".join(lines))
    print(f"\nWritten to {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
