"""
S0 (roadmap section 9, Track S): how well does NudeNet 640m work on YOUR photos? Read-only, CPU by default.

    # 1. detect on a random sample and write a local label sheet (no image is copied: the sheet points at
    #    the originals with file:// links and draws the boxes on top)
    venv\\Scripts\\python eval_sensitive.py <photo folder> [<photo folder> ...] --sample 150

    # 2. open eval\\sensitive_<time>\\sheet.html, mark each box correct / wrong (and tick labels it missed),
    #    press "Download labels.json", then:
    venv\\Scripts\\python eval_sensitive.py --score <labels.json> [--target 0.95]

Output only goes to eval\\sensitive_<time>\\ (report.json, sheet.html) and eval\\sensitive_thresholds.json.
A label counts toward `isSensitive` only at precision >= 0.95 (the target); its smallest passing score is written
to thresholds.json and copied into mobile/lib/domain/sensitive/sensitive_policy.dart + the shared fixtures.
"""

import argparse
import html
import json
import random
import sys
import time
from collections import defaultdict
from pathlib import Path

import cv2
import numpy as np

HERE = Path(__file__).resolve().parent
EVAL_DIR = HERE / "eval"
EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}


def list_photos(folders):
    out = []
    for folder in folders:
        out += [p for p in Path(folder).rglob("*") if p.suffix.lower() in EXTENSIONS]
    return sorted(out)


def detect_sample(paths, detector):
    import sensitive_detection as sd
    rows = []
    for path in paths:
        img = cv2.imdecode(np.fromfile(str(path), dtype=np.uint8), cv2.IMREAD_COLOR)
        if img is None:
            continue
        h, w = img.shape[:2]
        scale = 2560 / max(h, w)       # the phone sends at most 2560 px
        if scale < 1:
            img = cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
            h, w = img.shape[:2]
        regions = detector.detect(img)
        rows.append({"path": str(path), "width": w, "height": h,
                     "regions": [{"label": r["label"], "exposed": r["exposed"], "score": round(r["score"], 4),
                                  "bbox": [round(v, 1) for v in r["bbox"]]} for r in regions]})
    return rows


def sheet_html(rows):
    """One self-contained page. Verdicts live in the page; 'Download labels.json' saves them."""
    data = json.dumps(rows)
    return f"""<!doctype html><meta charset="utf-8"><title>Sensitive regions - label sheet</title>
<style>body{{font:14px system-ui;margin:16px;background:#111;color:#eee}}
.img{{position:relative;display:inline-block;margin:8px 0}}.img img{{max-width:640px;display:block}}
.box{{position:absolute;border:2px solid #f44}}.box.covered{{border-color:#fc4}}
.row{{margin:2px 0}}.card{{border-bottom:1px solid #333;padding:10px 0}}button{{font-size:15px;padding:6px 14px}}</style>
<h2>Mark every box. Rows: correct / wrong. Tick labels the model MISSED.</h2>
<button onclick="save()">Download labels.json</button><div id="root"></div>
<script>
const ROWS = {data};
const LABELS = {json.dumps(list(__import__('sensitive_detection').LABELS))};
const root = document.getElementById('root');
ROWS.forEach((r, i) => {{
  const c = document.createElement('div'); c.className = 'card';
  const boxes = r.regions.map((g, j) => `<div class="box ${{g.exposed ? '' : 'covered'}}" style="left:${{100*g.bbox[0]/r.width}}%;top:${{100*g.bbox[1]/r.height}}%;width:${{100*(g.bbox[2]-g.bbox[0])/r.width}}%;height:${{100*(g.bbox[3]-g.bbox[1])/r.height}}%" title="${{j}}"></div>`).join('');
  const rows = r.regions.map((g, j) => `<div class="row">#${{j}} ${{g.label}} ${{g.score}} <label><input type="radio" name="v${{i}}_${{j}}" value="correct">correct</label> <label><input type="radio" name="v${{i}}_${{j}}" value="wrong">wrong</label></div>`).join('');
  const miss = LABELS.filter(l => !l.startsWith('FACE')).map(l => `<label style="margin-right:8px"><input type="checkbox" data-miss="${{i}}" value="${{l}}">${{l}}</label>`).join('');
  c.innerHTML = `<div class="img"><img src="file:///${{r.path.replace(/\\\\/g, '/')}}">${{boxes}}</div>${{rows}}<details><summary>Missed labels</summary>${{miss}}</details>`;
  root.appendChild(c);
}});
function save() {{
  const out = ROWS.map((r, i) => ({{path: r.path,
    regions: r.regions.map((g, j) => {{const v = document.querySelector(`input[name=v${{i}}_${{j}}]:checked`); return {{label: g.label, score: g.score, verdict: v ? v.value : null}}; }}),
    missed: [...document.querySelectorAll(`input[data-miss="${{i}}"]:checked`)].map(x => x.value)}}));
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([JSON.stringify({{images: out}}, null, 1)], {{type: 'application/json'}}));
  a.download = 'labels.json'; a.click();
}}
</script>"""


def score_labels(labels, target):
    """Per label: precision/recall at every score cut, and the smallest score that reaches `target` precision."""
    per = defaultdict(list)            # label -> [(score, correct)]
    missed = defaultdict(int)
    for image in labels["images"]:
        for region in image["regions"]:
            if region.get("verdict") in ("correct", "wrong"):
                per[region["label"]].append((region["score"], region["verdict"] == "correct"))
        for label in image.get("missed", []):
            missed[label] += 1
    report = {}
    for label in sorted(set(per) | set(missed)):
        pairs = sorted(per.get(label, []), reverse=True)
        true_total = sum(ok for _, ok in pairs) + missed.get(label, 0)
        best = None
        for cut in sorted({s for s, _ in pairs}):
            kept = [ok for s, ok in pairs if s >= cut]
            precision = sum(kept) / len(kept)
            if precision >= target and len(kept) >= 5 and (best is None or cut < best["threshold"]):
                best = {"threshold": cut, "precision": round(precision, 3), "kept": len(kept),
                        "recall": round(sum(kept) / true_total, 3) if true_total else None}
        report[label] = {"labelled": len(pairs), "correct": sum(ok for _, ok in pairs), "missed": missed.get(label, 0),
                         "passes_target": best is not None, **(best or {})}
    return report


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folders", nargs="*")
    ap.add_argument("--sample", type=int, default=150)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--gpu", action="store_true", help="use CUDA (default: CPU, so a running scan is not disturbed)")
    ap.add_argument("--score", metavar="LABELS_JSON")
    ap.add_argument("--target", type=float, default=0.95)
    args = ap.parse_args(argv)

    EVAL_DIR.mkdir(exist_ok=True)
    if args.score:
        labels = json.loads(Path(args.score).read_text(encoding="utf-8"))
        report = score_labels(labels, args.target)
        for label, r in report.items():
            print(f"{label:28s} labelled {r['labelled']:4d}  correct {r['correct']:4d}  missed {r['missed']:3d}  "
                  + (f"threshold {r['threshold']:.3f} -> precision {r['precision']} recall {r['recall']}"
                     if r["passes_target"] else "does NOT reach the target - not used for isSensitive"))
        (EVAL_DIR / "sensitive_thresholds.json").write_text(json.dumps(
            {"target_precision": args.target, "labels": report}, indent=1), encoding="utf-8")
        print(f"wrote {EVAL_DIR / 'sensitive_thresholds.json'}")
        return 0

    if not args.folders:
        ap.error("give at least one photo folder (or --score labels.json)")
    photos = list_photos(args.folders)
    if not photos:
        print("no photos found")
        return 1
    random.Random(args.seed).shuffle(photos)
    sample = photos[:args.sample]
    import cuda_dll_dirs
    cuda_dll_dirs.add_nvidia_dll_dirs()
    import sensitive_detection as sd
    detector = sd.SensitiveDetector(providers=None if args.gpu else ["CPUExecutionProvider"])
    started = time.time()
    rows = detect_sample(sample, detector)
    out = EVAL_DIR / time.strftime("sensitive_%Y%m%d_%H%M%S")
    out.mkdir()
    counts = defaultdict(list)
    for row in rows:
        for r in row["regions"]:
            counts[r["label"]].append(r["score"])
    report = {"photos": len(rows), "seconds": round(time.time() - started, 1), "model_version": sd.MODEL_VERSION,
              "labels": {k: {"n": len(v), "score_p10_p50_p90": [round(float(np.percentile(v, q)), 3) for q in (10, 50, 90)]}
                         for k, v in sorted(counts.items())}}
    (out / "report.json").write_text(json.dumps(report, indent=1), encoding="utf-8")
    (out / "sheet.html").write_text(sheet_html(rows), encoding="utf-8")
    print(json.dumps(report, indent=1))
    print(f"\nlabel sheet: {out / 'sheet.html'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
