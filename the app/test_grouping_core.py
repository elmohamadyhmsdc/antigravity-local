"""
grouping_core tests - the DB-free grouping step the Streamlit gallery and the mobile API now share.

Standalone script (repo convention): prints PASS/FAIL per test and exits 1 on failure. CPU only,
no models, no GPU, never touches the real data/ folder (temporary JsonDatabase instances).

What it proves
  1. gallery_grouping (now a thin wrapper over grouping_core) behaves EXACTLY like the code it
     replaced. The pre-refactor group_library / relink_bodies / review_state are embedded below
     verbatim as the reference and both are run on identical copies of the libraries test_gallery.py
     builds (plus harder ones: frame conflicts, rejections, dismissed faces, bodies, all strictness
     presets, every flag combination). The final database state, the GroupingSummary and the whole
     ReviewState must be equal.
  2. The JSON path (what POST /v1/grouping/plan runs) gives the same result as the in-memory path,
     including the phone's three-round orchestration.
  3. The committed golden GroupingPlan fixtures are reproduced byte for byte, both from the
     committed requests and by regenerating them with make_fixtures.py in a temp folder.
  4. Malformed requests are refused with a clear message.

    venv\\Scripts\\python.exe test_grouping_core.py
    venv\\Scripts\\python.exe test_grouping_core.py fixtures     # only names containing "fixtures"
"""

import base64
import copy
import importlib.util
import json
import shutil
import sys
import tempfile
import traceback
from pathlib import Path
from typing import Dict, List

import numpy as np

HERE = Path(__file__).resolve().parent
CONTRACT = HERE / "mobile_api" / "contract"

_TESTS = []


def test(fn):
    _TESTS.append(fn)
    return fn


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


# ---------------------------------------------------------------------------
# The reference: gallery_grouping as it was before grouping_core existed (verbatim)
# ---------------------------------------------------------------------------

import person_linking as pl  # noqa: E402
import gallery_grouping as gg  # noqa: E402
import grouping_core as gc  # noqa: E402
from database import JsonDatabase  # noqa: E402
from test_gallery import identity, outfit_image, seed_library  # noqa: E402


def legacy_arrays(db, faces):
    e = pl.normalize_rows(db.get_embeddings_for([f["id"] for f in faces]))
    q = np.array([gg.face_quality_of(f) for f in faces], dtype=np.float32)
    keys = [gg.frame_key(f) for f in faces]
    rejected = [set(f.get("rejected_person_ids") or ()) for f in faces]
    return e, q, keys, rejected


def legacy_group_library(db, strictness="balanced", match_existing=True, create_new=True, link_bodies=True,
                         log=print):
    params = pl.params_for(strictness)
    summary = gg.GroupingSummary()

    with db.batch():
        unassigned = [f for f in db.faces.values() if f.get("person_id") is None]

        if match_existing and unassigned:
            models = gg.person_models(db)
            if models:
                e, q, keys, rejected = legacy_arrays(db, unassigned)
                for m in pl.match_faces(e, models, params, keys, rejected):
                    if m.decision == "auto":
                        db.assign_face_to_person(unassigned[m.index]["id"], m.person_id)
                        summary.assigned_to_existing += 1
                unassigned = [f for f in unassigned if f.get("person_id") is None]
                log(f"[grouping] {summary.assigned_to_existing} faces matched to existing people")

        if create_new and unassigned:
            e, q, keys, _ = legacy_arrays(db, unassigned)
            for cluster in pl.cluster_faces(e, q, params, keys):
                if not pl.should_auto_create(cluster, params):
                    continue
                face_ids = [unassigned[i]["id"] for i in cluster.indices]
                pid = db.create_person()
                db.update_person(pid, {"name": f"Person {pid}", "auto_created": True})
                db.batch_assign_faces(face_ids, pid)
                best = max((db.get_face(fid) for fid in face_ids), key=gg.face_quality_of)
                db.set_person_avatar(pid, best["id"])
                summary.new_people += 1
                summary.faces_in_new_people += len(face_ids)
            log(f"[grouping] {summary.new_people} new people created")

        if link_bodies and db.bodies:
            summary.bodies_linked = legacy_relink_bodies(db, params)

        summary.pending_faces = sum(1 for f in db.faces.values() if f.get("person_id") is None)
    return summary


def legacy_relink_bodies(db, params):
    linked = 0
    with db.batch():
        for body in db.bodies.values():
            if body.get("link_method") in gg.DERIVED_BODY_LINKS:
                body["person_id"] = None
                body["link_method"] = None
                body["link_confidence"] = None
        db.save_db()
        models = gg.person_models(db)
        if not models:
            return 0
        for link in pl.link_faceless_bodies(list(db.bodies.values()), db.body_person_id, models, params):
            if link.decision == "auto":
                db.link_body_to_person(link.body_id, link.person_id, link.method, link.confidence)
                linked += 1
    return linked


def legacy_review_state(db, strictness="balanced", max_suggestions_per_person=60):
    params = pl.params_for(strictness)
    state = gg.ReviewState()
    unassigned = [f for f in db.faces.values() if f.get("person_id") is None]
    models = gg.person_models(db)

    claimed = set()
    if unassigned and models:
        e, q, keys, rejected = legacy_arrays(db, unassigned)
        for m in pl.match_faces(e, models, params, keys, rejected):
            if m.decision in ("auto", "suggest"):
                face = unassigned[m.index]
                state.suggestions.setdefault(m.person_id, []).append(
                    gg.FaceSuggestion(face["id"], m.person_id, round(m.score, 3)))
                claimed.add(face["id"])
    for pid, items in state.suggestions.items():
        items.sort(key=lambda s: -s.score)
        del items[max_suggestions_per_person:]

    rest = [f for f in unassigned if f["id"] not in claimed and not f.get("review_dismissed")]
    if rest:
        e, q, keys, _ = legacy_arrays(db, rest)
        for cluster in pl.cluster_faces(e, q, params, keys):
            face_ids = [rest[i]["id"] for i in cluster.indices]
            state.groups.append(gg.GroupSuggestion(face_ids, round(cluster.cohesion, 3), round(cluster.quality, 3)))
            claimed.update(face_ids)

    if len(models) > 1:
        state.duplicates = pl.suggest_merges(models, params, db.distinct_pairs())

    if db.bodies and models:
        state.body_links = [l for l in pl.link_faceless_bodies(list(db.bodies.values()), db.body_person_id,
                                                              models, params)
                            if l.decision == "suggest"]

    state.unsorted_face_ids = [f["id"] for f in unassigned if f["id"] not in claimed]
    return state


# ---------------------------------------------------------------------------
# Libraries
# ---------------------------------------------------------------------------

def temp_db():
    tmp = Path(tempfile.mkdtemp(prefix="grouping_core_test_"))
    return JsonDatabase(data_dir=tmp), tmp


def db_state(db):
    """Everything group_library may change, in a comparable form."""
    return {
        "persons": {pid: (p.get("name"), p.get("auto_created"), p.get("avatar_face_id"), p.get("face_count"),
                          tuple(p.get("distinct_from") or ()))
                    for pid, p in sorted(db.persons.items())},
        "faces": {fid: (f.get("person_id"), tuple(f.get("rejected_person_ids") or ()), f.get("review_dismissed"))
                  for fid, f in sorted(db.faces.items())},
        "bodies": {bid: (b.get("person_id"), b.get("link_method"), b.get("link_confidence"), b.get("face_id"))
                   for bid, b in sorted(db.bodies.items())},
    }


def lib_basic(db):
    seed_library(db)


def lib_stranger(db):
    with db.batch():
        pid = db.create_person("Known")
        for v in identity(70, 4):
            db.add_face(v, "known.jpg", person_id=pid, quality_score=0.8)
        db.add_face(identity(71, 1)[0], "stranger.jpg", quality_score=0.8)


def lib_review(db):
    with db.batch():
        vecs = identity(80, 10)
        pid = db.create_person("Known")
        for v in vecs[:5]:
            db.add_face(v, "known.jpg", person_id=pid, quality_score=0.8)
        for i, v in enumerate(vecs[5:]):
            db.add_face(v, f"loose{i}.jpg", quality_score=0.8)
        other = identity(81, 10)
        p2, p3 = db.create_person("Split A"), db.create_person("Split B")
        for v in other[:5]:
            db.add_face(v, "a.jpg", person_id=p2, quality_score=0.8)
        for v in other[5:]:
            db.add_face(v, "b.jpg", person_id=p3, quality_score=0.8)


def lib_bodies(db):
    red = pl.appearance_descriptor(outfit_image((40, 40, 200), (150, 60, 40)), (20, 40, 180, 390))
    green = pl.appearance_descriptor(outfit_image((60, 180, 60), (240, 240, 240)), (20, 40, 180, 390))
    with db.batch():
        pid = db.create_person("Known")
        fid = db.add_face(identity(90, 1)[0], "clip.mp4", person_id=pid, quality_score=0.8,
                          extra={"media_id": 7, "frame_number": 0})
        db.add_body({"media_id": 7, "frame_number": 0, "face_id": fid, "appearance": [float(v) for v in red],
                     "bbox": {}})
        db.add_body({"media_id": 7, "frame_number": 90, "appearance": [float(v) for v in red], "bbox": {}})
        db.add_body({"media_id": 7, "frame_number": 90, "bbox": {}, "appearance": [float(v) for v in green]})
        manual = db.add_body({"media_id": 7, "frame_number": 120, "bbox": {}, "appearance": [float(v) for v in red]})
        # a body with a weak face of the known person and a rejected derived link
        weak = db.add_body({"media_id": 7, "frame_number": 150, "bbox": {},
                            "weak_face_embedding": [float(v) for v in identity(90, 1)[0]]})
        db.add_body({"media_id": 8, "frame_number": 1, "bbox": {}, "appearance": [float(v) for v in red],
                     "rejected_person_ids": [pid]})
    db.link_body_to_person(manual, pid, "manual")
    db.reject_body_from_person(weak, pid)


def lib_hard(db):
    """Same-frame conflicts, video faces without frame numbers, rejections, dismissed faces,
    low-quality leftovers, two known people, a split person and a distinct pair."""
    rng = np.random.default_rng(5)
    with db.batch():
        a, b = db.create_person("Ann"), db.create_person("Bob")
        c1, c2 = db.create_person("Cy A"), db.create_person("Cy B")
        db.mark_persons_distinct(a, b)
        va, vb, vc = identity(100, 14), identity(101, 12), identity(102, 12)
        for i, v in enumerate(va[:6]):
            db.add_face(v, f"a{i}.jpg", person_id=a, quality_score=float(rng.uniform(0.5, 0.95)),
                        extra={"media_id": 1000 + i})
        for i, v in enumerate(vb[:5]):
            db.add_face(v, f"b{i}.jpg", person_id=b, quality_score=float(rng.uniform(0.5, 0.95)),
                        extra={"media_id": 2000 + i})
        for i, v in enumerate(vc[:6]):
            db.add_face(v, f"c{i}.jpg", person_id=c1 if i < 3 else c2, quality_score=0.8,
                        extra={"media_id": 3000 + i})
        # loose faces of Ann/Bob, two of them in one photo (never the same person)
        db.add_face(va[6], "p.jpg", quality_score=0.8, extra={"media_id": 4000, "frame_number": None})
        db.add_face(vb[6], "p.jpg", quality_score=0.8, extra={"media_id": 4000, "frame_number": None})
        for i, v in enumerate(va[7:]):
            db.add_face(v, f"la{i}.jpg", quality_score=float(rng.uniform(0.3, 0.9)), extra={"media_id": 5000 + i})
        # an unknown person seen in 5 different photos and one low-quality extra
        for i, v in enumerate(identity(110, 5)):
            db.add_face(v, f"n{i}.jpg", quality_score=0.75, extra={"media_id": 6000 + i})
        db.add_face(identity(110, 1, spread=0.7)[0], "nlow.jpg", quality_score=0.3, extra={"media_id": 6100})
        # legacy video faces: no frame number, so no same-frame constraint
        for i, v in enumerate(identity(111, 4)):
            db.add_face(v, "clip.mp4", quality_score=0.7, extra={"media_id": 7000})
        # strangers
        for k in range(3):
            db.add_face(identity(120 + k, 1)[0], f"s{k}.jpg", quality_score=0.6, extra={"media_id": 8000 + k})
    ids = sorted(db.faces)
    # user feedback: a loose face of Ann was rejected from Ann; two faces were dismissed from review
    loose = [fid for fid in ids if db.faces[fid]["person_id"] is None]
    db.reject_face_from_person(loose[0], a)
    db.dismiss_face_group([loose[-1], loose[-2]])


LIBRARIES = {"basic": lib_basic, "stranger": lib_stranger, "review": lib_review, "bodies": lib_bodies,
             "hard": lib_hard}


def build(name):
    db, tmp = temp_db()
    LIBRARIES[name](db)
    return db, tmp


def both(name):
    """Two identical databases from the same builder."""
    a, ta = build(name)
    b, tb = build(name)
    check(db_state(a) == db_state(b), f"library {name!r} must be deterministic")
    return a, b, [ta, tb]


# ---------------------------------------------------------------------------
# 1. gallery_grouping == the code it replaced
# ---------------------------------------------------------------------------

@test
def test_group_library_matches_the_pre_refactor_behaviour_on_every_library_and_option():
    combos = [dict(), dict(match_existing=False), dict(create_new=False), dict(link_bodies=False),
              dict(match_existing=False, create_new=False)]
    ran = 0
    for name in LIBRARIES:
        for strictness in ("balanced", "strict", "loose"):
            for opts in combos:
                new_db, old_db, tmps = both(name)
                try:
                    logs_new, logs_old = [], []
                    s_new = gg.group_library(new_db, strictness, log=logs_new.append, **opts)
                    s_old = legacy_group_library(old_db, strictness, log=logs_old.append, **opts)
                    label = f"{name}/{strictness}/{opts}"
                    check(s_new == s_old, f"{label}: summary {s_new} != {s_old}")
                    check(logs_new == logs_old, f"{label}: log lines {logs_new} != {logs_old}")
                    check(db_state(new_db) == db_state(old_db), f"{label}: database state differs")
                    ran += 1
                finally:
                    for t in tmps:
                        shutil.rmtree(t, ignore_errors=True)
    check(ran == len(LIBRARIES) * 3 * len(combos), f"ran {ran} comparisons")


@test
def test_group_library_actually_does_something_on_the_hard_library():
    """Guard against a vacuous comparison: the hard library must exercise every branch."""
    db, tmp = build("hard")
    try:
        summary = gg.group_library(db, "balanced", log=lambda *_: None)
        check(summary.assigned_to_existing >= 5, f"known people should absorb their loose faces: {summary}")
        check(summary.new_people >= 1, f"the unknown person should be created: {summary}")
        check(summary.pending_faces >= 1, f"strangers stay pending: {summary}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    db, tmp = build("bodies")
    try:
        summary = gg.group_library(db, "balanced", log=lambda *_: None)
        check(summary.bodies_linked >= 1, f"an outfit link must be made: {summary}")
        manual = [b for b in db.bodies.values() if b.get("link_method") == "manual"]
        check(len(manual) == 1, "the manual link survives")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@test
def test_review_state_matches_the_pre_refactor_behaviour_before_and_after_grouping():
    for name in LIBRARIES:
        for strictness in ("balanced", "strict", "loose"):
            new_db, old_db, tmps = both(name)
            try:
                check(gg.review_state(new_db, strictness) == legacy_review_state(old_db, strictness),
                      f"{name}/{strictness}: review state differs before grouping")
                capped = gg.review_state(new_db, strictness, max_suggestions_per_person=2)
                check(capped == legacy_review_state(old_db, strictness, max_suggestions_per_person=2),
                      f"{name}/{strictness}: capped review state differs")
                check(all(len(v) <= 2 for v in capped.suggestions.values()), "the cap is honoured")
                gg.group_library(new_db, strictness, log=lambda *_: None)
                legacy_group_library(old_db, strictness, log=lambda *_: None)
                check(gg.review_state(new_db, strictness) == legacy_review_state(old_db, strictness),
                      f"{name}/{strictness}: review state differs after grouping")
            finally:
                for t in tmps:
                    shutil.rmtree(t, ignore_errors=True)


@test
def test_review_state_on_the_hard_library_has_something_in_every_section():
    db, tmp = build("hard")
    try:
        state = gg.review_state(db, "balanced")
        check(state.suggestions, "suggestions for known people")
        check(state.groups, "a new group")
        check(state.unsorted_face_ids, "unsorted faces")
        check(any(f.get("rejected_person_ids") for f in db.faces.values()), "a rejection is in the library")
        dismissed = {fid for fid, f in db.faces.items() if f.get("review_dismissed")}
        in_groups = {fid for g in state.groups for fid in g.face_ids}
        check(dismissed and not (dismissed & in_groups), "dismissed faces never come back as a group")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    db, tmp = build("review")
    try:
        check(gg.review_state(db, "balanced").duplicates, "the split person is a duplicate suggestion")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    db, tmp = build("bodies")
    try:
        gg.group_library(db, "balanced", log=lambda *_: None)
        # after grouping, whatever is only a suggestion is reported
        check(isinstance(gg.review_state(db, "balanced").body_links, list), "body links are a list")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------------------
# 2. the JSON path (POST /v1/grouping/plan) == the in-memory path
# ---------------------------------------------------------------------------

def b64(vec) -> str:
    return base64.b64encode(np.asarray(vec, dtype="<f4").tobytes()).decode("ascii")


def models_json(db, cap=300) -> List[Dict]:
    """What the phone sends as `models`: one prototype + the best `cap` members per person."""
    faces = [f for f in db.faces.values() if f.get("person_id") is not None]
    if not faces:
        return []
    models = pl.build_person_models(db.get_embeddings_for([f["id"] for f in faces]),
                                    [f["person_id"] for f in faces], [gg.face_quality_of(f) for f in faces], cap=cap)
    return [{"pid": pid, "proto": b64(m.proto), "members": [b64(x) for x in m.members], "count": int(m.count)}
            for pid, m in sorted(models.items())]


def key_text(key):
    return None if key is None else f"{key[0]}:{'' if key[1] is None else key[1]}"


def pending_json(db) -> List[Dict]:
    out = []
    for f in db.faces.values():
        if f.get("person_id") is None:
            # raw stored vector: the server normalises once, exactly like the in-memory path does
            out.append({"id": f["id"], "embedding": b64(np.asarray(f["embedding"], dtype=np.float32)),
                        "quality": gg.face_quality_of(f), "frame_key": key_text(gg.frame_key(f)),
                        "rejected_person_ids": sorted(f.get("rejected_person_ids") or ())})
    return out


def bodies_json(db, drop_derived=False) -> List[Dict]:
    out = []
    for b in db.bodies.values():
        anchor = db.body_person_id(b)
        if drop_derived and b.get("face_id") is None and b.get("link_method") in gg.DERIVED_BODY_LINKS:
            anchor = None
        wf = b.get("weak_face_embedding")
        out.append({"id": b["id"], "media_id": b.get("media_id"), "frame_number": b.get("frame_number"),
                    "anchor_person_id": anchor, "appearance": b.get("appearance"),
                    "weak_face_embedding": None if wf is None else b64(wf),
                    "rejected_person_ids": sorted(b.get("rejected_person_ids") or ())})
    return out


def request_from_db(db, mode, stages, strictness="balanced", cap=300, drop_derived=False):
    return {"mode": mode, "stages": stages, "strictness": strictness, "models": models_json(db, cap),
            "pending": pending_json(db),
            "dismissed_face_ids": sorted(fid for fid, f in db.faces.items() if f.get("review_dismissed")),
            "distinct_pairs": [list(p) for p in db.distinct_pairs()],
            "bodies": bodies_json(db, drop_derived), "max_suggestions_per_person": 60}


def phone_rounds(db, strictness="balanced", cap=300):
    """The phone's orchestration, played on a JsonDatabase: round 1 apply [match, cluster] (autos in one
    go, new people get real ids), round 2 apply [bodies] with derived links cleared first, and
    returns the round-3 review plan. Every call goes through the JSON wire format."""
    with db.batch():
        r1 = gc.plan_request(request_from_db(db, "apply", ["match", "cluster"], strictness, cap))
        for a in r1["assignments"]:
            db.assign_face_to_person(a["face_id"], a["person_id"])
        for g in r1["groups"]:
            if g["auto_create"]:
                pid = db.create_person()
                db.update_person(pid, {"name": f"Person {pid}", "auto_created": True})
                db.batch_assign_faces(g["face_ids"], pid)
                best = max((db.get_face(fid) for fid in g["face_ids"]), key=gg.face_quality_of)
                db.set_person_avatar(pid, best["id"])
        for body in db.bodies.values():
            if body.get("link_method") in gg.DERIVED_BODY_LINKS:
                body["person_id"] = None
                body["link_method"] = None
                body["link_confidence"] = None
        r2 = gc.plan_request(request_from_db(db, "apply", ["bodies"], strictness, cap, drop_derived=True))
        for l in r2["body_links"]:
            if l["decision"] == "auto":
                db.link_body_to_person(l["body_id"], l["person_id"], l["method"], l["confidence"])
    return gc.plan_request(request_from_db(db, "review", list(gc.STAGES), strictness, cap))


@test
def test_the_json_path_with_the_phones_three_rounds_equals_group_library_and_review_state():
    for name in LIBRARIES:
        for strictness in ("balanced", "strict", "loose"):
            wire_db, ref_db, tmps = both(name)
            try:
                review = phone_rounds(wire_db, strictness)
                gg.group_library(ref_db, strictness, log=lambda *_: None)
                label = f"{name}/{strictness}"
                check(db_state(wire_db) == db_state(ref_db), f"{label}: the phone's rounds end in a different library")
                state = gg.review_state(ref_db, strictness)
                suggestions = {}
                for a in review["assignments"]:
                    suggestions.setdefault(a["person_id"], []).append((a["face_id"], a["score"]))
                check(suggestions == {p: [(s.face_id, s.score) for s in v] for p, v in state.suggestions.items()},
                      f"{label}: suggestions differ")
                check([(g["face_ids"], g["cohesion"], g["quality"]) for g in review["groups"]]
                      == [(g.face_ids, g.cohesion, g.quality) for g in state.groups], f"{label}: groups differ")
                check([(d["person_a"], d["person_b"], d["score"]) for d in review["duplicates"]]
                      == list(state.duplicates), f"{label}: duplicates differ")
                check([(l["body_id"], l["person_id"], l["method"], l["confidence"]) for l in review["body_links"]]
                      == [(l.body_id, l.person_id, l.method, l.confidence) for l in state.body_links],
                      f"{label}: body links differ")
                check(review["unsorted_face_ids"] == state.unsorted_face_ids, f"{label}: unsorted faces differ")
            finally:
                for t in tmps:
                    shutil.rmtree(t, ignore_errors=True)


@test
def test_member_cap_limits_are_enforced_and_the_documented_range_is_accepted():
    """The accuracy of a smaller cap is eval_member_cap.py's job (it needs a real curated library). Here: the
    server takes 50..1000 members per person - duplicate scoring reads the first 50 - and refuses more."""
    rng = np.random.default_rng(3)
    vecs = rng.standard_normal((1001, 512)).astype(np.float32)
    vecs /= np.linalg.norm(vecs, axis=1, keepdims=True)

    def request(n_members):
        return {"mode": "review", "stages": ["match", "duplicates"], "strictness": "balanced",
                "models": [{"pid": 1, "proto": b64(vecs[0]), "members": [b64(v) for v in vecs[:n_members]],
                            "count": n_members},
                           {"pid": 2, "proto": b64(vecs[1]), "members": [b64(v) for v in vecs[1:1 + n_members]],
                            "count": n_members}],
                "pending": [], "distinct_pairs": [], "bodies": []}

    for n in (50, 100, 300, 1000):
        check(gc.plan_request(request(n))["mode"] == "review", f"{n} members per person should be accepted")
    refused(request(1001), "members")


# ---------------------------------------------------------------------------
# 3. golden fixtures
# ---------------------------------------------------------------------------

GOLDEN = ["apply_basic", "review_all", "review_distinct_pair"]


def read_fixture(name):
    return json.loads((CONTRACT / "fixtures" / f"{name}.json").read_text(encoding="utf-8"))


@test
def test_committed_grouping_requests_produce_the_committed_responses():
    for name in GOLDEN:
        req, expected = read_fixture(f"GroupingPlanRequest.{name}"), read_fixture(f"GroupingPlanResponse.{name}")
        got = gc.plan_request(copy.deepcopy(req))
        check(got == expected, f"{name}: grouping_core.plan_request differs from the committed response\n"
                               f"got      {json.dumps(got)[:300]}\nexpected {json.dumps(expected)[:300]}")
        check(json.dumps(got, indent=2, ensure_ascii=False) + "\n"
              == json.dumps(expected, indent=2, ensure_ascii=False) + "\n",
              f"{name}: same data but different number formatting / key order")


@test
def test_make_fixtures_regenerates_the_grouping_fixtures_identically():
    spec = importlib.util.spec_from_file_location("make_fixtures_under_test", CONTRACT / "make_fixtures.py")
    mf = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mf)
    tmp = Path(tempfile.mkdtemp(prefix="fixtures_regen_"))
    try:
        mf.OUT = tmp
        # the same call order as make_fixtures.py's main: the seeded rng is shared between the generators
        mf.system_fixtures()
        mf.analyze_fixture()
        mf.grouping_fixtures()
        checked = 0
        for kind in ("GroupingPlanRequest", "GroupingPlanResponse"):
            for name in GOLDEN:
                fresh = (tmp / f"{kind}.{name}.json").read_bytes().replace(b"\r\n", b"\n")
                committed = (CONTRACT / "fixtures" / f"{kind}.{name}.json").read_bytes().replace(b"\r\n", b"\n")
                check(fresh == committed, f"{kind}.{name}.json differs from the committed fixture after regenerating")
                checked += 1
        check(checked == 6, f"compared {checked} files")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------------------
# 4. bad requests
# ---------------------------------------------------------------------------

def refused(req, part):
    try:
        gc.plan_request(req)
    except gc.GroupingRequestError as e:
        check(part in str(e), f"message {str(e)!r} should mention {part!r}")
        return
    raise AssertionError(f"the request should have been refused ({part!r})")


@test
def test_malformed_requests_are_refused_with_a_clear_message():
    good = read_fixture("GroupingPlanRequest.review_all")

    def mutated(fn):
        r = copy.deepcopy(good)
        fn(r)
        return r

    refused(mutated(lambda r: r.__setitem__("mode", "yolo")), "mode")
    refused(mutated(lambda r: r["stages"].append("telepathy")), "stages")
    refused(mutated(lambda r: r.__setitem__("stages", ["match", "match"])), "repeat")
    refused(mutated(lambda r: r.__setitem__("strictness", "reckless")), "strictness")
    refused(mutated(lambda r: r.__setitem__("strictness", ["strict"])), "strictness")
    refused(mutated(lambda r: r.__setitem__("max_suggestions_per_person", 0)), "max_suggestions_per_person")
    refused(mutated(lambda r: r.__setitem__("models", {})), "models")
    refused(mutated(lambda r: r["models"][0].__setitem__("members", [])), "members")
    refused(mutated(lambda r: r["models"][0].__setitem__("proto", "AAAA")), "proto")
    refused(mutated(lambda r: r["models"][0].__setitem__("proto", "###")), "base64")
    refused(mutated(lambda r: r["models"].append(copy.deepcopy(r["models"][0]))), "twice")
    refused(mutated(lambda r: r["pending"][0].__setitem__("embedding", b64(np.full(512, np.nan)))), "NaN")
    refused(mutated(lambda r: r["pending"].append(copy.deepcopy(r["pending"][0]))), "twice")
    refused(mutated(lambda r: r["pending"][0].__setitem__("quality", "high")), "quality")
    refused(mutated(lambda r: r["pending"][0].__setitem__("frame_key", 12)), "frame_key")
    refused(mutated(lambda r: r["pending"][0].__setitem__("id", True)), "id")
    refused(mutated(lambda r: r["bodies"][0].__setitem__("appearance", [0.1] * 79)), "appearance")
    refused(mutated(lambda r: r.__setitem__("distinct_pairs", [[1]])), "distinct_pairs")
    refused(mutated(lambda r: r.__setitem__("mode", "apply")), "duplicates")  # review_all asks for duplicates
    refused([], "JSON object")
    # ...and the unmodified request is fine
    check(gc.plan_request(copy.deepcopy(good))["mode"] == "review", "the good request works")


@test
def test_an_empty_library_gives_an_empty_plan():
    req = {"mode": "review", "stages": list(gc.STAGES), "strictness": "balanced", "models": [], "pending": [],
           "distinct_pairs": [], "bodies": []}
    out = gc.plan_request(req)
    check(out == {"mode": "review", "assignments": [], "groups": [], "duplicates": [], "body_links": [],
                  "unsorted_face_ids": []}, f"unexpected: {out}")
    req["mode"] = "apply"
    req["stages"] = ["match", "cluster", "bodies"]
    check(gc.plan_request(req)["unsorted_face_ids"] == [], "apply mode never lists unsorted faces")


@test
def test_grouping_core_imports_no_database():
    import ast
    tree = ast.parse((HERE / "grouping_core.py").read_text(encoding="utf-8"))
    modules = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            modules.update(a.name.split(".")[0] for a in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            modules.add(node.module.split(".")[0])
    check("database" not in modules and "gallery_grouping" not in modules, f"imports: {sorted(modules)}")


def main(argv):
    pattern = argv[0] if argv else ""
    selected = [t for t in _TESTS if pattern in t.__name__]
    if not selected:
        print(f"No test matches '{pattern}'.\nKnown: " + ", ".join(t.__name__ for t in _TESTS))
        return 1
    failed = 0
    for t in selected:
        try:
            t()
            print(f"[PASS] {t.__name__}")
        except Exception as e:  # noqa: BLE001
            failed += 1
            print(f"[FAIL] {t.__name__}: {e}")
            traceback.print_exc()
    print(f"\n{len(selected) - failed}/{len(selected)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
