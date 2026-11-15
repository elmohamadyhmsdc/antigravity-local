"""
Embed a labelled face set (one folder per person, e.g. LFW) into an .npz that eval_grouping_sim.py replays.

    venv\\Scripts\\python eval_grouping_extract.py <root_with_person_folders> <out.npz> [--max-per-person 40]

Same models and quality as a phone scan (buffalo_l through analysis.detect_faces / assess_face). Every face that
passes the face_quality gate is kept. The face nearest the image centre carries the folder's label; any other
face in the photo is a bystander and gets a unique negative label (it is someone else - nobody we can name).
GPU, read-only on the input folder.
"""

import argparse
import sys
from pathlib import Path

import cv2
import numpy as np


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("out")
    ap.add_argument("--max-per-person", type=int, default=40)
    args = ap.parse_args(argv)

    import face_quality
    from analysis import assess_face, detect_faces
    from mobile_api.engines import load_face_analyzer

    app = load_face_analyzer()
    root = Path(args.root)
    people = sorted(p for p in root.iterdir() if p.is_dir())
    names, emb, qual, label, photo, centre, px = [], [], [], [], [], [], []
    photo_id = 0
    bystander = -1
    for pi, person in enumerate(people):
        names.append(person.name)
        files = sorted(person.glob("*.jpg"))[:args.max_per_person]
        for f in files:
            img = cv2.imread(str(f))
            if img is None:
                continue
            h, w = img.shape[:2]
            faces = detect_faces(app, img)
            kept = []
            for face in faces:
                q = assess_face(img, face)
                if not face_quality.passes_gate(face, face_quality.DEFAULT_MIN_QUALITY, q["quality_score"]):
                    continue
                x1, y1, x2, y2 = [float(v) for v in face.bbox[:4]]
                d = np.hypot((x1 + x2) / 2 - w / 2, (y1 + y2) / 2 - h / 2)
                kept.append((d, face, q))
            if kept:
                main_i = int(np.argmin([k[0] for k in kept]))
                for i, (d, face, q) in enumerate(kept):
                    e = np.asarray(face.normed_embedding, dtype=np.float32)
                    emb.append(e)
                    qual.append(q["quality_score"])
                    px.append(q["face_px"])
                    photo.append(photo_id)
                    centre.append(i == main_i)
                    if i == main_i:
                        label.append(pi)
                    else:
                        label.append(bystander)
                        bystander -= 1
            photo_id += 1
        if pi % 200 == 0:
            print(f"{pi}/{len(people)} people, {len(emb)} faces", flush=True)
    np.savez_compressed(args.out, names=np.array(names), embedding=np.stack(emb).astype(np.float32),
                        quality=np.array(qual, np.float32), label=np.array(label), photo=np.array(photo),
                        centre=np.array(centre), face_px=np.array(px, np.float32))
    print(f"saved {len(emb)} faces from {photo_id} photos of {len(people)} people -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
