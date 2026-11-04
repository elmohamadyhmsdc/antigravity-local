"""
Pose rules + descriptor in Python (pose_filters.py) against hand-written expectations, and the shared golden
cases the phone's Dart implementation is checked against (mobile_api/contract/fixtures/pose/cases.json).

    venv\\Scripts\\python.exe test_pose_filters.py            # run
    venv\\Scripts\\python.exe test_pose_filters.py --write    # also (re)write the golden cases
"""

import json
import sys
import traceback
from pathlib import Path

import numpy as np

import pose_filters as pf

CASES = Path(__file__).parent / "mobile_api" / "contract" / "fixtures" / "pose" / "cases.json"
_TESTS = []


def test(fn):
    _TESTS.append(fn)
    return fn


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


def standing():
    """Frontal, standing, a 1000 x 1500 picture: shoulders 300 wide, torso 400."""
    return {0: (500, 300), 1: (530, 280), 2: (470, 280), 3: (560, 290), 4: (440, 290),
            5: (650, 400), 6: (350, 400), 7: (670, 550), 8: (330, 550), 9: (680, 700), 10: (320, 700),
            11: (560, 800), 12: (440, 800), 13: (560, 1050), 14: (440, 1050), 15: (560, 1300), 16: (440, 1300)}


def moved(base, changes):
    return {**base, **changes}


def mirrored(pts):
    return {pf.MIRROR[i]: (1000 - x, y) for i, (x, y) in pts.items()}


def rotated(pts):
    return {i: (1500 - y, x) for i, (x, y) in pts.items()}


def pose(pts, extent="full", yaw=None, hidden=(), faint=()):
    rows = []
    for i in range(17):
        if i in pts:
            score = 0.0 if i in hidden else (0.1 if i in faint else 0.9)
            rows.append([pts[i][0], pts[i][1], score])
        else:
            rows.append([0, 0, 0])
    return pf.Pose(rows, extent, yaw)


def cases():
    s = standing()
    side = moved(s, {13: (800, 820), 14: (700, 820), 15: (800, 1080), 16: (700, 1080)})
    frontal_seat = moved(s, {13: (560, 890), 14: (440, 890), 15: (560, 1250), 16: (440, 1250)})
    relaxed = rotated(moved(s, {13: (600, 1000), 14: (400, 1000), 15: (900, 1100), 16: (100, 1100)}))
    no_hips = {i: v for i, v in s.items() if i < 11}
    return {
        "standing": (pose(s), {"standing", "frontal"}),
        "bent": (pose({i: (x + 250 if i <= 10 else x, y) for i, (x, y) in s.items()}),
                 {"bent", "frontal"}),
        "standing_upper_extent": (pose(s, extent="upper"), {"frontal"}),
        "lying": (pose(rotated(s)), {"lying"}),
        "lying_relaxed": (pose(relaxed), {"lying"}),
        "sitting_side": (pose(side), {"sitting", "frontal"}),
        "sitting_frontal": (pose(frontal_seat), {"sitting", "frontal"}),
        "arms_up": (pose(moved(s, {9: (680, 250), 10: (320, 250)})), {"standing", "frontal", "arms_up"}),
        "one_arm_up": (pose(moved(s, {9: (680, 250)})), {"standing", "frontal", "one_arm_up"}),
        "arms_spread": (pose(moved(s, {7: (800, 400), 8: (200, 400), 9: (950, 400), 10: (50, 400)})),
                        {"standing", "frontal", "arms_spread"}),
        "hands_on_hips": (pose(moved(s, {7: (780, 600), 8: (220, 600), 9: (565, 800), 10: (435, 800)})),
                          {"standing", "frontal", "hands_on_hips"}),
        "profile_face": (pose(s, yaw=80), {"standing", "profile"}),
        "back_view": (pose(s, faint=(0, 1, 2)), {"standing", "back"}),
        "no_hips": (pose(no_hips, extent="upper"), set()),    # frontal needs the torso length (no hips: unknown)
    }


@test
def test_hand_written_expectations():
    for name, (p, expected) in cases().items():
        got = pf.tier_a_tags(p)
        check(got == expected, f"{name}: {sorted(got)} != {sorted(expected)}")
    p = pose(rotated(standing()))
    check("lying" in pf.tier_a_tags(p) and "lying" not in pf.tier_a_tags(p, guard_rotated_standing=True),
          "the guard recognises a sideways standing photo")


@test
def test_denormalisation_by_width_and_height():
    truth = standing()
    for w, h in ((1500, 1500), (900, 1600), (4000, 3000)):
        raw = json.dumps([[truth[i][0] / w, truth[i][1] / h, 0.9] for i in range(17)])
        p = pf.Pose.from_normalised(raw, w, h, "full")
        check(abs(p.xy(5)[0] - 650) < 1e-6 and abs(p.torso - 400) < 1e-6 and abs(p.spine_tilt) < 1e-6, (w, h))
    check(pf.Pose.from_normalised("[[0.1,0.1,0.9]]", 10, 10) is None, "broken")
    check(pf.Pose.from_normalised(None, 10, 10) is None and pf.Pose.from_normalised("[]", None, 10) is None, "missing")


@test
def test_descriptor_is_mirror_invariant_scale_free_and_not_rotation_free():
    a = pf.build_feature(pose(standing()))
    check(abs(pf.compare(a, a)[0] - 1) < 1e-9, "same")
    check(abs(pf.compare(a, pf.build_feature(pose(mirrored(standing()))))[0] - 1) < 1e-6, "mirror")
    small = {i: (x * 0.5 + 40, y * 0.5 + 90) for i, (x, y) in standing().items()}
    check(abs(pf.compare(a, pf.build_feature(pose(small)))[0] - 1) < 1e-6, "scale + translation")
    check(pf.compare(a, pf.build_feature(pose(rotated(standing()))))[0] < 0.05, "rotation matters")


@test
def test_scale_source_and_comparability():
    s = standing()
    no_hips = {i: v for i, v in s.items() if i < 11}
    shoulder = pf.build_feature(pose(no_hips, extent="upper"))
    torso = pf.build_feature(pose(s))
    check(shoulder.scale_source == "shoulder" and torso.scale_source == "torso", "sources")
    check(pf.compare(shoulder, torso) is None, "different scale sources are not comparable")
    no_ears = {i: v for i, v in no_hips.items() if i not in (3, 4)}
    check(pf.build_feature(pose(no_ears, extent="upper")) is None, "not frontal -> no shoulder scale")
    check(pf.build_feature(pose(no_hips, extent="upper", yaw=70)) is None, "profile")
    upper = pf.build_feature(pose({i: v for i, v in s.items() if i <= 12}, extent="upper"))
    sim, coverage, shared = pf.compare(torso, upper)
    check(abs(sim - 1) < 1e-6 and abs(coverage - 13 / 17) < 1e-9 and shared == 13, (sim, coverage, shared))
    few = {i: s[i] for i in (5, 6, 11, 12)}
    check(pf.build_feature(pose(few)) is None, "fewer than 8 visible points")


@test
def test_limb_differences_and_invalid_values_are_not_hidden():
    base = pf.build_feature(pose(standing()))
    for change in ({9: (680, 250)}, {15: (900, 950)}):
        other = pf.build_feature(pose(moved(standing(), change)))
        check(pf.compare(base, other)[0] < 0.65, "one different limb must reduce similarity")
    broken = pf.Feature(np.full(34, np.nan, dtype=np.float32), base.mask, "torso")
    check(pf.compare(base, broken) is None, "invalid feature")


def golden():
    cs = cases()
    feats = {n: pf.build_feature(p) for n, (p, _) in cs.items()}
    out = {"version": 1, "note": "points are image pixels [x, y, score]; written by test_pose_filters.py --write",
           "cases": {}, "similarities": []}
    for name, (p, expected) in cs.items():
        f = feats[name]
        out["cases"][name] = {
            "extent": p.extent, "face_yaw": p.face_yaw,
            "points": [[round(float(v), 3) for v in row] for row in p.p],
            "tags": sorted(expected),
            "feature": None if f is None else {"scale_source": f.scale_source, "mask": f.mask,
                                               "data": [round(float(v), 5) for v in f.data]},
        }
    names = [n for n, f in feats.items() if f is not None]
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            r = pf.compare(feats[a], feats[b])
            out["similarities"].append({"a": a, "b": b, "result": None if r is None else
                                        {"similarity": round(r[0], 5), "coverage": round(r[1], 5), "shared": r[2]}})
    return out


@test
def test_golden_cases_are_current():
    fresh = golden()
    check(CASES.exists(), "run with --write once to create the golden cases")
    stored = json.loads(CASES.read_text(encoding="utf-8"))
    check(stored == fresh, "the golden cases are stale: run test_pose_filters.py --write and rerun the Dart tests")


def main(argv):
    if "--write" in argv:
        CASES.parent.mkdir(parents=True, exist_ok=True)
        CASES.write_text(json.dumps(golden(), indent=1) + "\n", encoding="utf-8")
        print("wrote", CASES)
    failed = 0
    for fn in _TESTS:
        try:
            fn()
            print(f"PASS  {fn.__name__}")
        except Exception:  # noqa: BLE001
            failed += 1
            print(f"FAIL  {fn.__name__}")
            traceback.print_exc()
    print(f"\n{len(_TESTS) - failed}/{len(_TESTS)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
