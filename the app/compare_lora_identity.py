"""
Antigravity Local - Phase 0 measurement for the LoRA identity source (Reface V2)

Answers the question docs/plans/2026-09-17-lora-in-reface-v2-design.md section 2 poses: does an
identity vector averaged from LoRA-generated portraits match the real person better than one
averaged from their real training photos? Exercises the same code the Reface V2 UI will use
(lora_identity.py, identity.py, RefaceEngineV3), just driven from the command line.

    venv\\Scripts\\python.exe compare_lora_identity.py <person_id> <target_image> [<target_image> ...]

Needs a person with a trained LoRA and at least 8 "plain" generations already on disk (Character
LoRA -> 3) Generate, default prompt, no reference image).

Prints, for two folds (build on half the real photos, score against the held-out half, then the
reverse): each candidate's (Real / LoRA / Mixed) vector score and swapped-output score against the
held-out mean, the spread of generated faces around the real-photo mean, the lowest-scoring real
photos (worth a manual look - gallery clustering can attach the wrong face to a person), and the
10th-percentile real-photo similarity to its held-out mean (the proposed MIN_ANCHOR_SIMILARITY).

Output: reface_output/compare_lora_identity_<timestamp>.png - one row per target image, columns
Real / LoRA / Mixed.
"""
import sys
from datetime import datetime
from pathlib import Path

import cv2
import numpy as np

from database import get_person_by_id
from identity import build_identity_embedding
from job_manager import JobManager
from lora_identity import (MODE_LABELS, MODE_LORA, MODE_MIXED, MODE_REAL, clean_generated_images,
                           detect_largest_face, faceset_from_detections, real_photo_embeddings)
from reface_engine_v3 import RefaceEngineV3


def _label(img, text):
    out = img.copy()
    cv2.rectangle(out, (0, 0), (out.shape[1], 40), (0, 0, 0), -1)
    cv2.putText(out, text, (12, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2, cv2.LINE_AA)
    return out


def _unit(v):
    v = np.asarray(v, dtype=np.float32).ravel()
    n = np.linalg.norm(v)
    return v / n if np.isfinite(n) and n >= 1e-8 else None


def _cosine(a, b):
    if a is None or b is None:
        return None
    ua, ub = _unit(a), _unit(b)
    return None if ua is None or ub is None else float(np.dot(ua, ub))


def _mean_unit(faces):
    """Unit-norm mean embedding of a list of FaceData - the held-out ground truth for a fold, so
    unweighted (unlike the quality-weighted identity vectors under test)."""
    units = [u for u in (_unit(f.embedding) for f in faces) if u is not None]
    return _unit(np.mean(units, axis=0)) if units else None


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1

    person_id = int(argv[0])
    targets = argv[1:]
    for t in targets:
        if not Path(t).exists():
            print(f"[FAIL] target not found: {t}")
            return 1

    person = get_person_by_id(person_id)
    if not person:
        print(f"[FAIL] person {person_id} not found")
        return 1

    print(f"[INFO] Loading models for {person['name']}...")
    engine = RefaceEngineV3()
    face_app = engine.app

    real_faces, source = real_photo_embeddings(person_id, person["name"], face_app)
    if len(real_faces) < 4:
        print(f"[FAIL] only {len(real_faces)} real photo(s) found ({source or 'none'}) - need at least "
              f"a handful per fold to measure anything")
        return 1
    print(f"[INFO] {len(real_faces)} real photo(s) from {source}")

    jobs = JobManager(str(Path(__file__).parent / "jobs"))
    clean_paths, excluded = clean_generated_images(person["name"], jobs)
    for path, reason in excluded:
        print(f"[SKIP] {path.name}: {reason}")
    if len(clean_paths) < 4:
        print(f"[FAIL] only {len(clean_paths)} clean generated portrait(s) - need at least 8 plain "
              f"generations (Character LoRA -> Generate, no reference image)")
        return 1

    generated_faces = []
    for path in clean_paths:
        face = detect_largest_face(path, face_app)
        if face is None:
            print(f"[SKIP] {Path(path).name}: no face detected")
        else:
            generated_faces.append(face)
    print(f"[INFO] {len(generated_faces)}/{len(clean_paths)} generated portrait(s) have a detectable face")
    if len(generated_faces) < 4:
        print("[FAIL] too few generated faces survived detection to measure anything")
        return 1

    half = len(real_faces) // 2
    folds = [(real_faces[:half], real_faces[half:]), (real_faces[half:], real_faces[:half])]

    fold_results = []
    per_photo_scores = []  # (image_path, similarity to its own held-out fold mean)
    for fold_index, (build_half, holdout_half) in enumerate(folds, start=1):
        holdout_mean = _mean_unit(holdout_half)
        for f in build_half:
            per_photo_scores.append((f.image_path, _cosine(f.embedding, holdout_mean)))

        candidates = {MODE_REAL: build_half, MODE_LORA: generated_faces, MODE_MIXED: build_half + generated_faces}
        print(f"\n=== Fold {fold_index}: build on {len(build_half)}, score against {len(holdout_half)} held out ===")
        fold_result = {}
        for mode, faces in candidates.items():
            faceset = faceset_from_detections(f"_phase0_{mode}", faces)
            vector = build_identity_embedding(faceset)
            vector_score = _cosine(vector, holdout_mean)

            output_scores, rendered = [], []
            for target in targets:
                result = engine.reface_image_v3(target, faceset)
                if not result.success:
                    print(f"[FAIL] {mode} swap on {target}: {result.message}")
                    output_scores.append(None)
                    rendered.append(None)
                    continue
                output_face = detect_largest_face(result.output_path, face_app)
                output_scores.append(_cosine(output_face.embedding, holdout_mean) if output_face else None)
                rendered.append(cv2.imread(result.output_path))

            valid_output = [s for s in output_scores if s is not None]
            avg_output = sum(valid_output) / len(valid_output) if valid_output else None
            vector_str = f"{vector_score:.3f}" if vector_score is not None else "n/a"
            output_str = f"{avg_output:.3f}" if avg_output is not None else "n/a"
            print(f"  {MODE_LABELS[mode]:<14} vector={vector_str}  output avg={output_str}")
            fold_result[mode] = {"vector_score": vector_score, "output_scores": output_scores, "rendered": rendered}
        fold_results.append(fold_result)

    real_mean = _mean_unit(real_faces)
    generated_similarities = sorted((s for s in (_cosine(f.embedding, real_mean) for f in generated_faces)
                                     if s is not None), reverse=True)
    if generated_similarities:
        print(f"\nGenerated-portrait similarity to real-photo mean: "
              f"min={generated_similarities[-1]:.3f} max={generated_similarities[0]:.3f} "
              f"mean={sum(generated_similarities) / len(generated_similarities):.3f}")

    per_photo_scores = [(p, s) for p, s in per_photo_scores if s is not None]
    per_photo_scores.sort(key=lambda t: t[1])
    print("\nLowest-scoring real photos (check these for wrong-person contamination):")
    for path, score in per_photo_scores[:5]:
        print(f"  {score:.3f}  {path}")

    scores_only = sorted(s for _, s in per_photo_scores)
    if scores_only:
        pct10 = scores_only[max(0, int(len(scores_only) * 0.10) - 1)]
        print(f"\n10th-percentile real-photo similarity to held-out mean "
              f"(proposed MIN_ANCHOR_SIMILARITY): {pct10:.3f}")

    rows = []
    for row_index in range(len(targets)):
        cells = []
        for mode in (MODE_REAL, MODE_LORA, MODE_MIXED):
            img = fold_results[0][mode]["rendered"][row_index]
            cells.append(_label(img, MODE_LABELS[mode]) if img is not None else np.zeros((512, 512, 3), np.uint8))
        height = max(c.shape[0] for c in cells)
        cells = [cv2.resize(c, (int(c.shape[1] * height / c.shape[0]), height)) for c in cells]
        rows.append(np.hstack(cells))
    width = max(r.shape[1] for r in rows)
    rows = [cv2.copyMakeBorder(r, 0, 0, 0, width - r.shape[1], cv2.BORDER_CONSTANT) for r in rows]
    grid = np.vstack(rows)

    out_dir = Path(__file__).parent / "reface_output"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"compare_lora_identity_{datetime.now():%Y%m%d_%H%M%S}.png"
    cv2.imwrite(str(out_path), grid)
    print(f"\nWrote {out_path}")
    print("\nGo/no-go: Real, LoRA or Mixed wins if it beats Real on vector score in BOTH folds by "
          ">= 0.02, and the side-by-side looks no worse. Otherwise: no-go, ship Real only.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
