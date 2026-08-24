"""
Antigravity Local - V3 realism A/B

Renders one target image through the 'clean' preset (pre-rebuild behaviour) and
the 'natural' preset, and writes them side by side for visual comparison.

    venv\\Scripts\\python.exe compare_v3.py <target_image> <faceset_name>
    venv\\Scripts\\python.exe compare_v3.py <target_image> <faceset_name> maximum_detail

Output: reface_output/compare_<timestamp>.png
"""

import sys
from datetime import datetime
from pathlib import Path

import cv2
import numpy as np

from reface_engine_v3 import RefaceEngineV3


def _label(img, text):
    out = img.copy()
    cv2.rectangle(out, (0, 0), (out.shape[1], 48), (0, 0, 0), -1)
    cv2.putText(out, text, (16, 33), cv2.FONT_HERSHEY_SIMPLEX, 1.0,
                (255, 255, 255), 2, cv2.LINE_AA)
    return out


def render(target_path: str, faceset_name: str, preset: str):
    engine = RefaceEngineV3(realism_preset=preset)
    faceset = engine.load_faceset_by_name(faceset_name)
    if not faceset:
        print(f"[FAIL] faceset '{faceset_name}' not found")
        return None
    result = engine.reface_image_v3(target_path, faceset)
    if not result.success:
        print(f"[FAIL] {preset}: {result.message}")
        return None
    print(f"[OK]   {preset}: {result.output_path}")
    return cv2.imread(result.output_path)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1

    target, faceset_name = argv[0], argv[1]
    challenger = argv[2] if len(argv) > 2 else "natural"

    if not Path(target).exists():
        print(f"[FAIL] target not found: {target}")
        return 1

    before = render(target, faceset_name, "clean")
    after = render(target, faceset_name, challenger)
    if before is None or after is None:
        return 1

    if before.shape != after.shape:
        after = cv2.resize(after, (before.shape[1], before.shape[0]))

    pair = np.hstack([_label(before, "clean (legacy V3)"),
                      _label(after, challenger)])

    out_dir = Path(__file__).parent / "reface_output"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"compare_{datetime.now():%Y%m%d_%H%M%S}.png"
    cv2.imwrite(str(out_path), pair)
    print(f"\nWrote {out_path}")
    print("Zoom in on: the jaw and hairline edge, skin texture, and any hand or open mouth.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
