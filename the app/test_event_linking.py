"""
Roadmap section 7.2 / Phase 5 - event-context body linking in person_linking, CPU only:
the same outfit on an identified body and on a faceless body of ANOTHER photo taken within the window.

    venv\\Scripts\\python.exe test_event_linking.py
"""

import sys
import traceback

import numpy as np

import person_linking as pl

_TESTS = []
HOUR = 3600 * 1000
T0 = 1_762_000_000_000


def test(fn):
    _TESTS.append(fn)
    return fn


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


def outfit_image(torso_bgr, legs_bgr, size=(400, 200)):
    w, h = size[1], size[0]
    img = np.zeros((h, w, 3), np.uint8)
    img[: h // 2] = torso_bgr
    img[h // 2:] = legs_bgr
    return img


def descriptor(torso, legs):
    d = pl.appearance_descriptor(outfit_image(torso, legs), (20, 40, 180, 390))
    assert d is not None
    return [float(x) for x in d]


BLUE, WHITE = descriptor((200, 80, 30), (240, 240, 240)), descriptor((205, 85, 35), (238, 238, 238))
GREEN = descriptor((60, 180, 60), (30, 30, 30))
SKIN = descriptor((120, 160, 215), (200, 100, 40))     # BGR skin tone on the torso, blue legs


def body(i, media, taken, appearance, anchor=None, frame=None, rejected=(), taken_at="unset"):
    return {"id": i, "media_id": media, "frame_number": frame, "appearance": appearance,
            "weak_face_embedding": None, "rejected_person_ids": set(rejected), "anchor_person_id": anchor,
            "taken_at": taken if taken_at == "unset" else taken_at}


def link(bodies, strictness="balanced"):
    return pl.link_faceless_bodies(bodies, lambda b: b["anchor_person_id"], {}, pl.params_for(strictness))


@test
def test_vectorised_similarity_equals_the_scalar_one():
    rows = np.asarray([BLUE, GREEN, SKIN, [0.0] * 80], dtype=np.float32)
    many = pl.appearance_similarity_many(BLUE, rows)
    for r, m in zip(rows, many):
        check(abs(pl.appearance_similarity(BLUE, r) - m) < 1e-6, (pl.appearance_similarity(BLUE, r), m))
    legs_only = np.asarray([[0.0] * 40 + list(GREEN[40:])], dtype=np.float32)
    check(abs(pl.appearance_similarity(GREEN, legs_only[0]) - pl.appearance_similarity_many(GREEN, legs_only)[0]) < 1e-6,
          "regions that only one side shows")


@test
def test_same_outfit_within_the_window_links_in_another_photo():
    links = link([body(1, 10, T0, BLUE, anchor=7), body(2, 11, T0 + HOUR, WHITE)])
    check(len(links) == 1, links)
    l = links[0]
    check((l.body_id, l.person_id, l.method, l.decision) == (2, 7, "event_outfit", "auto"), l)
    check(l.confidence >= pl.params_for("balanced").event_auto, l.confidence)


@test
def test_outside_the_window_or_a_different_outfit_never_links():
    anchor = body(1, 10, T0, BLUE, anchor=7)
    check(link([anchor, body(2, 11, T0 + 2 * 24 * HOUR, WHITE)]) == [], "two days later")
    check(link([anchor, body(2, 11, T0 + 7 * HOUR, WHITE)]) == [], "just outside 6 h")
    check(len(link([anchor, body(2, 11, T0 + 5 * HOUR, WHITE)])) == 1, "inside 6 h, either side")
    check(len(link([anchor, body(2, 11, T0 - 5 * HOUR, WHITE)])) == 1, "before the anchor too")
    check(link([anchor, body(2, 11, T0 + HOUR, GREEN)]) == [], "another outfit")


@test
def test_missing_taken_at_is_ignored_on_either_side():
    check(link([body(1, 10, T0, BLUE, anchor=7), body(2, 11, None, WHITE)]) == [], "faceless without a time")
    check(link([body(1, 10, None, BLUE, anchor=7), body(2, 11, T0, WHITE)]) == [], "anchor without a time")
    plain = [body(1, 10, None, BLUE, anchor=7), body(2, 11, None, WHITE)]
    check(link(plain) == [], "old callers that send no taken_at get exactly the old behaviour")
    for b in plain:
        b.pop("taken_at")
    check(link(plain) == [], "key absent")


@test
def test_two_people_in_one_uniform_are_only_a_suggestion():
    bodies = [body(1, 10, T0, BLUE, anchor=7), body(2, 12, T0 + HOUR, WHITE, anchor=8),
              body(3, 11, T0 + 2 * HOUR, BLUE)]
    links = link(bodies)
    check(len(links) == 1 and links[0].decision == "suggest" and links[0].method == "event_outfit", links)


@test
def test_rejections_and_people_already_in_the_frame_are_respected():
    anchor = body(1, 10, T0, BLUE, anchor=7)
    check(link([anchor, body(2, 11, T0 + HOUR, WHITE, rejected=[7])]) == [], "the user said not them")
    in_frame = [anchor, body(3, 11, T0 + HOUR, GREEN, anchor=7, frame=5),
                body(2, 11, T0 + HOUR, WHITE, frame=5)]
    check(link(in_frame) == [], "person 7 is already elsewhere in this frame")


@test
def test_the_same_photo_is_left_to_the_same_media_rule():
    same_media = [body(1, 10, T0, BLUE, anchor=7, frame=1), body(2, 10, T0, WHITE, frame=2)]
    links = link(same_media)
    check(len(links) == 1 and links[0].method == "appearance", links)


@test
def test_bare_skin_is_not_an_outfit():
    check(pl.skin_dominated(SKIN) and not pl.skin_dominated(BLUE) and not pl.skin_dominated(GREEN), "classification")
    check(not pl.skin_dominated(None) and not pl.skin_dominated([0.0] * 80), "no torso, nothing to say")
    legs_only = [0.0] * 40 + list(BLUE[40:])
    check(not pl.skin_dominated(legs_only), "legs only is not skin-dominated")
    bodies = [body(1, 10, T0, SKIN, anchor=7), body(2, 11, T0 + HOUR, SKIN)]
    check(link(bodies) == [], "two bare torsos of the same tone are not 'the same outfit'")


@test
def test_thresholds_follow_the_strictness():
    strict, loose = pl.params_for("strict"), pl.params_for("loose")
    check(strict.event_auto > pl.params_for("balanced").event_auto > loose.event_auto, "ordering")
    check(all(p.event_suggest < p.event_auto for p in (strict, loose, pl.params_for("balanced"))), "suggest below auto")


@test
def test_bone_ratio_veto_is_soft_and_off_by_default():
    def pose(shoulder_half, torso, tilt=0.0, vis=0.9):
        k = np.zeros((17, 2))
        k[5], k[6] = (100 - shoulder_half, 100), (100 + shoulder_half, 100)
        k[11], k[12] = (100 - 30 + tilt, 100 + torso), (100 + 30 + tilt, 100 + torso)
        k[15], k[16] = (80, 400), (120, 400)
        s = np.full(17, vis)
        return k, s

    wide, narrow = pose(60, 150), pose(46, 150)      # shoulder/torso 0.80 vs 0.61: both frontal, 23 % apart
    check(pl.bone_ratio_veto(*wide, *narrow, spread=0.0) is False, "disabled")
    check(pl.bone_ratio_veto(*wide, *narrow, spread=0.2) is True, "frontal, upright, far beyond the spread")
    check(pl.bone_ratio_veto(*wide, *pose(55, 150), spread=0.2) is False, "within the spread")
    check(pl.bone_ratio_veto(*wide, *pose(35, 150, tilt=120), spread=0.2) is False, "not upright: no veto")
    check(pl.bone_ratio_veto(*wide, *pose(35, 150, vis=0.1), spread=0.2) is False, "legs not visible: no veto")
    check(pl.bone_ratio_veto(*wide, *pose(20, 150), spread=0.2) is False, "not frontal (narrow shoulders): no veto")


@test
def test_grouping_core_carries_taken_at_end_to_end():
    import grouping_core
    import json
    from pathlib import Path
    fx = Path(__file__).parent / "mobile_api" / "contract" / "fixtures"
    req = json.loads((fx / "GroupingPlanRequest.event_outfit.json").read_text(encoding="utf-8"))
    links = grouping_core.plan_request(req)["body_links"]
    check([(l["body_id"], l["method"], l["decision"]) for l in links] == [(12, "event_outfit", "auto")], links)
    bad = dict(req, bodies=[dict(req["bodies"][0], taken_at="yesterday")])
    try:
        grouping_core.plan_request(bad)
    except grouping_core.GroupingRequestError:
        pass
    else:
        raise AssertionError("a non-integer taken_at must be refused")
    nulls = dict(req, bodies=[dict(b, taken_at=None) for b in req["bodies"]])
    check(grouping_core.plan_request(nulls)["body_links"] == [], "without times nothing is linked by time")


@test
def test_eval_body_links_reads_a_backup_and_reports_a_window():
    import base64
    import json
    import tempfile
    import zipfile
    from pathlib import Path

    import eval_body_links as ev

    def enc(vec):
        return {"$b64": base64.b64encode(np.asarray(vec, dtype="<f4").tobytes()).decode()}

    rng = np.random.default_rng(0)
    outfits = {1: BLUE, 2: GREEN, 3: descriptor((30, 30, 200), (60, 60, 60))}
    media, bodies = [], []
    for person, outfit in outfits.items():
        for k in range(8):
            mid = person * 100 + k
            media.append({"id": mid, "taken_at": T0 + k * HOUR // 2, "width": 1000, "height": 800})
            noisy = np.clip(np.asarray(outfit) + rng.normal(0, 0.003, 80), 0, None)
            bodies.append({"id": mid, "kind": "person", "person_id": person, "face_id": mid, "media_id": mid,
                           "link_method": None, "appearance": enc(noisy), "kpts": None, "extent": "upper"})
    bodies.append({"id": 999, "kind": "person", "person_id": 1, "face_id": None, "media_id": 1, "link_method": "appearance",
                   "appearance": enc(BLUE), "kpts": None, "extent": "upper"})        # derived link: not ground truth
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "lib.agbackup"
        with zipfile.ZipFile(path, "w") as z:
            z.writestr("db/media.0000.jsonl", "\n".join(json.dumps(m) for m in media))
            z.writestr("db/bodies.0000.jsonl", "\n".join(json.dumps(b) for b in bodies))
        report = ev.evaluate(ev.load_tables(path), [1.0, 6.0])
    check(report["bodies"] == 24 and report["people"] == 3, report)
    window = report["windows"]["6.0"]
    check(window["pairs"] > 0 and window["event_auto"] is not None, window)
    check(window["precision"]["0.9"]["precision"] == 1.0, "distinct outfits separate perfectly in this synthetic library")
    check(report["llr_within_6h"] and report["bone_ratio"]["verdict"].startswith("not enough"), report["bone_ratio"])


def main(argv):
    wanted = argv[1] if len(argv) > 1 else ""
    failed = 0
    ran = 0
    for fn in _TESTS:
        if wanted and wanted not in fn.__name__:
            continue
        ran += 1
        try:
            fn()
            print(f"PASS  {fn.__name__}")
        except Exception:  # noqa: BLE001
            failed += 1
            print(f"FAIL  {fn.__name__}")
            traceback.print_exc()
    print(f"\n{ran - failed}/{ran} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
