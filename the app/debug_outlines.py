"""
Visual debug script for face and body outlines.

Usage:
    python debug_outlines.py <photo> <out.png>

Runs analysis with outlines=True, draws detector boxes (thin grey), face outlines (amber),
and body outlines (cyan), prints point counts and timing, and saves <out.png>.
"""

import sys
import os
from pathlib import Path

import cv2
import numpy as np

from analysis import AnalyzeOptions
from mobile_api.engines import InsightEngines


def main():
    if len(sys.argv) < 3:
        print("Usage: python debug_outlines.py <photo> <out.png>")
        sys.exit(1)

    photo_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2])

    if not photo_path.exists():
        print(f"File not found: {photo_path}")
        sys.exit(1)

    img = cv2.imread(str(photo_path))
    if img is None:
        print(f"Failed to read image: {photo_path}")
        sys.exit(1)

    h, w = img.shape[:2]
    print(f"Analyzing {photo_path.name} ({w}x{h})...")

    engines = InsightEngines(isolate_scans=False)
    options = AnalyzeOptions(detect_bodies=True, outlines=True)
    result = engines.analyze(img, options)

    canvas = img.copy()

    # Colors (BGR)
    COLOR_BOX = (128, 128, 128)      # Thin grey
    COLOR_FACE = (0, 165, 255)       # Amber (BGR)
    COLOR_BODY = (255, 255, 0)       # Cyan (BGR)

    print(f"\nResults for {photo_path.name}:")
    print(f"Timing outline: {result.timings_ms.get('outline', 0)} ms")
    print(f"Total timings: {result.timings_ms}")

    # Draw bodies
    print(f"\nBodies ({len(result.bodies)}):")
    for i, b in enumerate(result.bodies):
        bx1, by1, bx2, by2 = [int(round(v)) for v in b.bbox[:4]]
        cv2.rectangle(canvas, (bx1, by1), (bx2, by2), COLOR_BOX, 1, lineType=cv2.LINE_AA)

        outline = result.body_outlines[i] if i < len(result.body_outlines) else None
        if outline is not None:
            pts = np.round(outline).astype(np.int32).reshape((-1, 1, 2))
            cv2.polylines(canvas, [pts], isClosed=True, color=COLOR_BODY, thickness=2, lineType=cv2.LINE_AA)
            print(f"  Body {i}: score={b.score:.2f}, {len(outline)} outline points")
        else:
            print(f"  Body {i}: score={b.score:.2f}, no outline")

    # Draw faces
    print(f"\nFaces ({len(result.faces)}):")
    for i, f in enumerate(result.faces):
        fx1, fy1, fx2, fy2 = [int(round(v)) for v in f.bbox[:4]]
        cv2.rectangle(canvas, (fx1, fy1), (fx2, fy2), COLOR_BOX, 1, lineType=cv2.LINE_AA)

        passes = result.passes_gate[i] if i < len(result.passes_gate) else False
        outline = result.face_outlines[i] if i < len(result.face_outlines) else None
        if outline is not None:
            pts = np.round(outline).astype(np.int32).reshape((-1, 1, 2))
            cv2.polylines(canvas, [pts], isClosed=True, color=COLOR_FACE, thickness=2, lineType=cv2.LINE_AA)
            print(f"  Face {i}: det_score={f.det_score:.2f}, passes_gate={passes}, {len(outline)} outline points")
        else:
            print(f"  Face {i}: det_score={f.det_score:.2f}, passes_gate={passes}, no outline")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(out_path), canvas)
    print(f"\nSaved visualization to {out_path} ({out_path.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
