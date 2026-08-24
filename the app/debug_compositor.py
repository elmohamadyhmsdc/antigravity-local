"""
Antigravity Local - compositor stage diagnostic

Walks one image through the V3 pipeline and prints coverage statistics at every
stage, so a mask that collapses to zero can be traced to the exact step that
zeroed it. Also dumps the intermediate crops as PNGs.

    venv\\Scripts\\python.exe debug_compositor.py <target_image> <faceset_name>

Output: reface_output/debug_*.png
"""

import sys
from pathlib import Path

import cv2
import numpy as np

from reface_engine_v3 import RefaceEngineV3, _face_height
from identity import build_source_from_faceset
from face_compositor import alignment_matrix
from face_masking import (DEFAULT_REGIONS, feather_mask, harden_occlusion,
                          region_from_seg)


def stat(name, arr):
    a = np.asarray(arr, np.float32)
    nonzero = float((a > 0.01).mean())
    print(f"  {name:<28} min={a.min():.4f} max={a.max():.4f} "
          f"mean={a.mean():.4f} coverage={nonzero*100:.1f}%")


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1

    target_path, faceset_name = argv[0], argv[1]
    if not Path(target_path).exists():
        print(f"[FAIL] target not found: {target_path}")
        return 1

    out_dir = Path(__file__).parent / "reface_output"
    out_dir.mkdir(parents=True, exist_ok=True)

    eng = RefaceEngineV3()
    faceset = eng.load_faceset_by_name(faceset_name)
    if not faceset:
        print(f"[FAIL] faceset '{faceset_name}' not found")
        return 1

    source = build_source_from_faceset(faceset)
    if source is None:
        print("[FAIL] faceset has no usable source faces")
        return 1

    frame = cv2.imread(target_path)
    faces = eng.app.get(frame)
    if not faces:
        print("[FAIL] no face detected in target")
        return 1
    face = faces[0]
    print(f"\n[1] detection: {len(faces)} face(s), bbox height = {_face_height(face):.0f}px")

    # ---- swap -------------------------------------------------------------
    try:
        aligned_swap, m_swap = eng.swapper.get(frame, face, source, paste_back=False)
        print(f"[2] swap OK: crop {aligned_swap.shape}, mean {aligned_swap.mean():.1f}")
        cv2.imwrite(str(out_dir / "debug_1_swap_raw.png"), aligned_swap)
    except Exception as e:
        print(f"[2] SWAP FAILED: {e}")
        return 1

    comp = eng.compositor
    size = comp.config.restore_size

    # ---- alignment --------------------------------------------------------
    m_ffhq = alignment_matrix(face.kps, size)
    if m_ffhq is None:
        print("[3] ALIGNMENT FAILED: bad landmarks")
        return 1
    orig_aligned = cv2.warpAffine(frame, m_ffhq, (size, size),
                                  borderMode=cv2.BORDER_REPLICATE)
    base = comp._place_swap(aligned_swap, m_swap, m_ffhq, orig_aligned, size)
    diff = float(np.abs(base.astype(np.float32) - orig_aligned.astype(np.float32)).mean())
    print(f"[3] placement OK: base differs from original by {diff:.1f} grey levels")
    print("    (a value near 0 would mean the swap never landed in the crop)")
    cv2.imwrite(str(out_dir / "debug_2_orig_aligned.png"), orig_aligned)
    cv2.imwrite(str(out_dir / "debug_3_base_placed.png"), base)

    # ---- restore ----------------------------------------------------------
    restored = base
    if comp.restorer.available:
        restored = comp.restorer.enhance(base)
        if restored.shape[:2] != (size, size):
            restored = cv2.resize(restored, (size, size))
        print(f"[4] restore OK: mean {restored.mean():.1f}")
    else:
        print("[4] restore SKIPPED (restorer unavailable)")
    cv2.imwrite(str(out_dir / "debug_4_restored.png"), restored)

    # ---- mask, stage by stage --------------------------------------------
    print("\n[5] mask stages:")
    regions = comp._regions()
    print(f"    regions in use: {regions}")

    seg_orig = comp.masker.segment(orig_aligned)
    seg_res = comp.masker.segment(restored)
    if seg_orig is None or seg_res is None:
        print("    PARSER RETURNED None -> falling back to box mask")
        return 1

    print(f"    classes found in original crop: {sorted(np.unique(seg_orig).tolist())}")
    print(f"    classes found in restored crop: {sorted(np.unique(seg_res).tolist())}")

    region_orig = region_from_seg(seg_orig, regions)
    region_res = region_from_seg(seg_res, regions)
    region = region_res * region_orig
    stat("region (original crop)", region_orig)
    stat("region (restored crop)", region_res)
    stat("region (intersection)", region)

    feathered = feather_mask(region, comp.config.mask_erode, comp.config.mask_feather)
    stat("after erode + feather", feathered)

    mask = feathered
    if comp.config.use_occluder and comp.masker.occluder is not None:
        occ = comp.masker.occlusion_mask(orig_aligned)
        if occ is not None:
            stat("occluder (raw)", occ)
            hardened = harden_occlusion(occ)
            stat("occluder (hardened)", hardened)
            mask = feathered * hardened
            stat("FINAL mask", mask)
        else:
            print("    occluder returned None")
    else:
        print("    occluder disabled or unavailable")

    cv2.imwrite(str(out_dir / "debug_5_mask.png"), (mask * 255).astype(np.uint8))

    coverage = float((mask > 0.01).mean())
    print("\n[6] verdict:")
    if coverage < 0.01:
        print("    MASK IS EMPTY -> output will be the original face.")
        print("    Compare the stages above to see which one zeroed it.")
    else:
        print(f"    mask covers {coverage*100:.1f}% of the crop - swap should be visible")

    print(f"\nWrote debug PNGs to {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
