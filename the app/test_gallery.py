"""
Antigravity Local - gallery v2 tests (quality scoring, grouping, linking,
scanner, storage).

Standalone script (the repo has no pytest). CPU only, no models, no GPU, and it
never touches the real data/ folder - every test that stores anything uses a
temporary JsonDatabase.

    venv\\Scripts\\python.exe test_gallery.py             # everything
    venv\\Scripts\\python.exe test_gallery.py cluster     # only names containing "cluster"
"""

import shutil
import sys
import tempfile
import traceback
from pathlib import Path

import numpy as np

_TESTS = []


def test(fn):
    _TESTS.append(fn)
    return fn


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


def temp_db():
    from database import JsonDatabase
    tmp = Path(tempfile.mkdtemp(prefix="gallery_test_"))
    return JsonDatabase(data_dir=tmp), tmp


def identity(seed, n, spread=0.55, shift=0.0):
    """n embeddings of one made-up person: a shared direction plus per-face noise
    of length `spread` (so same-person cosine similarity is about 1/(1+spread^2),
    and two different seeds are near-orthogonal, like real embeddings).
    `shift` moves the whole batch along one extra direction - two batches of the
    same seed with different shifts act like one person in two different looks."""
    rng = np.random.default_rng(seed)
    base = rng.standard_normal(512).astype(np.float32)
    base /= np.linalg.norm(base)
    look = np.random.default_rng(seed + 9999).standard_normal(512).astype(np.float32)
    look /= np.linalg.norm(look)
    noise = rng.standard_normal((n, 512)).astype(np.float32)
    noise /= np.linalg.norm(noise, axis=1, keepdims=True)
    out = base[None] + look[None] * shift + noise * spread
    return out / np.linalg.norm(out, axis=1, keepdims=True)


class FakeFace:
    """Stand-in for an insightface Face."""

    def __init__(self, bbox, embedding=None, det_score=0.9, kps=None, pose=None):
        self.bbox = np.asarray(bbox, dtype=np.float32)
        self.embedding = None if embedding is None else np.asarray(embedding, dtype=np.float32)
        self.det_score = det_score
        x1, y1, x2, y2 = bbox
        w, h = x2 - x1, y2 - y1
        self.kps = np.asarray(kps if kps is not None else [
            [x1 + 0.3 * w, y1 + 0.35 * h], [x1 + 0.7 * w, y1 + 0.35 * h], [x1 + 0.5 * w, y1 + 0.55 * h],
            [x1 + 0.35 * w, y1 + 0.75 * h], [x1 + 0.65 * w, y1 + 0.75 * h]], dtype=np.float32)
        self.pose = pose

    @property
    def embedding_norm(self):
        return float(np.linalg.norm(self.embedding)) if self.embedding is not None else None

    @property
    def normed_embedding(self):
        return self.embedding / self.embedding_norm


class FakeBody:
    def __init__(self, bbox, kpts=None, kpt_scores=None, score=0.9):
        self.bbox = np.asarray(bbox, dtype=np.float32)
        self.score = score
        self.kpts = None if kpts is None else np.asarray(kpts, dtype=np.float32)
        self.kpt_scores = None if kpt_scores is None else np.asarray(kpt_scores, dtype=np.float32)


def body_with_head(x1, y1, x2, y2, head_xy):
    """A body box whose visible head keypoints sit at head_xy."""
    kpts = np.zeros((17, 2), dtype=np.float32)
    scores = np.zeros(17, dtype=np.float32)
    hx, hy = head_xy
    for i, (dx, dy) in enumerate([(0, 0), (-6, -4), (6, -4), (-12, -2), (12, -2)]):
        kpts[i] = (hx + dx, hy + dy)
        scores[i] = 0.9
    for i, (px, py) in [(5, (x1 + 10, y1 + 60)), (6, (x2 - 10, y1 + 60)),
                        (11, (x1 + 15, y1 + 140)), (12, (x2 - 15, y1 + 140))]:
        kpts[i] = px, py
        scores[i] = 0.8
    return FakeBody((x1, y1, x2, y2), kpts, scores)


# ---------------------------------------------------------------------------
# face_quality
# ---------------------------------------------------------------------------

@test
def test_quality_components_are_bounded_and_monotonic():
    from face_quality import components, score

    tiny = components(face_px=20, embedding_norm=17, sharp=10, yaw=70, pitch=40)
    great = components(face_px=300, embedding_norm=26, sharp=900, yaw=2, pitch=1)
    for parts in (tiny, great):
        for k, v in parts.items():
            check(0.0 <= v <= 1.0, f"{k} out of range: {v}")
    check(score(great) > score(tiny), "a big, sharp, frontal face must outscore a tiny blurry profile")
    check(score(great) > 0.9 and score(tiny) < 0.2, f"scores not spread out: {score(tiny)} / {score(great)}")


@test
def test_quality_sharpness_separates_blur():
    import cv2
    from face_quality import sharpness

    rng = np.random.default_rng(0)
    sharp = rng.integers(0, 255, (112, 112, 3)).astype(np.uint8)
    blurred = cv2.GaussianBlur(sharp, (0, 0), 4)
    check(sharpness(sharp) > sharpness(blurred) * 5,
          f"blur should drop sharpness a lot: {sharpness(sharp):.0f} vs {sharpness(blurred):.0f}")
    check(sharpness(None) == 0.0, "no image -> zero sharpness")


@test
def test_quality_gate_rejects_small_and_unsure_detections():
    from face_quality import passes_gate, tier

    good = FakeFace((0, 0, 200, 200), det_score=0.9)
    check(passes_gate(good, 0.4, 0.8), "a big confident face should pass")
    check(not passes_gate(good, 0.4, 0.2), "quality below the gate must fail")
    check(not passes_gate(FakeFace((0, 0, 20, 20), det_score=0.9), 0.4, 0.9), "20px face must fail")
    check(not passes_gate(FakeFace((0, 0, 200, 200), det_score=0.3), 0.4, 0.9), "unsure detection must fail")
    check(tier(0.9)[0] == "great" and tier(0.6)[0] == "good" and tier(0.1)[0] == "poor", "tier boundaries")


@test
def test_quality_assess_uses_pose_and_reports_fields():
    from face_quality import QUALITY_VERSION, assess

    face = FakeFace((100, 100, 300, 300), embedding=np.full(512, 1.0), pose=(5.0, -10.0, 2.0))
    out = assess(face, np.zeros((112, 112, 3), dtype=np.uint8))
    check(out["quality_version"] == QUALITY_VERSION, "quality_version must be stamped")
    check(out["pose"]["yaw"] == -10.0 and out["face_px"] == 200.0, f"pose/size not reported: {out}")
    check(set(out["quality_parts"]) == {"norm", "size", "sharp", "pose"}, "components must be stored")

    profile = FakeFace((100, 100, 300, 300), embedding=np.full(512, 1.0), pose=(5.0, -75.0, 2.0))
    check(assess(profile, None)["quality_score"] < out["quality_score"], "a profile must score lower")


# ---------------------------------------------------------------------------
# person_linking - matching
# ---------------------------------------------------------------------------

@test
def test_match_faces_assigns_known_person_and_ignores_strangers():
    import person_linking as pl

    a, b = identity(1, 10), identity(2, 10)
    models = pl.build_person_models(np.vstack([a[:8], b[:8]]), [1] * 8 + [2] * 8, [0.8] * 16)
    params = pl.params_for("balanced")

    hits = pl.match_faces(np.vstack([a[8:], b[8:]]), models, params)
    check([m.person_id for m in hits] == [1, 1, 2, 2], f"wrong people: {[m.person_id for m in hits]}")
    check(all(m.decision == "auto" for m in hits), f"held-out faces should auto-match: {hits}")

    stranger = pl.match_faces(identity(99, 3), models, params)
    check(all(m.decision is None for m in stranger),
          f"an unknown person must not be auto-assigned: {stranger}")


@test
def test_match_faces_respects_not_this_person_feedback():
    import person_linking as pl

    a = identity(3, 10)
    models = pl.build_person_models(a[:8], [7] * 8, [0.8] * 8)
    params = pl.params_for("balanced")
    check(pl.match_faces(a[8:9], models, params)[0].decision == "auto", "sanity: should match")
    rejected = pl.match_faces(a[8:9], models, params, rejected=[{7}])
    check(rejected[0].decision is None, f"a rejected person must not come back: {rejected[0]}")


@test
def test_match_faces_never_puts_one_person_twice_in_a_frame():
    import person_linking as pl

    a = identity(4, 12)
    models = pl.build_person_models(a[:10], [5] * 10, [0.8] * 10)
    params = pl.params_for("balanced")
    # Two faces from the SAME photo that both look like person 5
    both = pl.match_faces(a[10:12], models, params, frame_keys=[("photo.jpg", None)] * 2)
    assigned = [m.person_id for m in both if m.decision == "auto"]
    check(len(assigned) <= 1, f"only one face per photo may be person 5: {both}")
    # The same two faces in different photos are both allowed
    apart = pl.match_faces(a[10:12], models, params, frame_keys=[("a.jpg", None), ("b.jpg", None)])
    check(sum(m.decision == "auto" for m in apart) == 2, f"different photos should both match: {apart}")


# ---------------------------------------------------------------------------
# person_linking - clustering
# ---------------------------------------------------------------------------

@test
def test_cluster_faces_finds_the_right_number_of_people():
    import person_linking as pl

    e = np.vstack([identity(10, 12), identity(11, 9), identity(12, 6)])
    clusters = pl.cluster_faces(e, [0.8] * 27, pl.params_for("balanced"))
    check(len(clusters) == 3, f"expected 3 groups, got {len(clusters)} sized {[len(c.indices) for c in clusters]}")
    truth = [0] * 12 + [1] * 9 + [2] * 6
    for c in clusters:
        check(len({truth[i] for i in c.indices}) == 1, "a group mixed two people")
    check(sum(len(c.indices) for c in clusters) == 27, "every face should land in a group")


@test
def test_cluster_faces_keeps_same_photo_faces_apart():
    import person_linking as pl

    e = identity(13, 6)  # six near-identical faces...
    keys = [("same.jpg", None)] * 6  # ...all claimed to be in one photo
    clusters = pl.cluster_faces(e, [0.8] * 6, pl.params_for("balanced"), frame_keys=keys)
    check(clusters == [], f"faces from one photo must never be grouped together: {clusters}")
    apart = pl.cluster_faces(e, [0.8] * 6, pl.params_for("balanced"),
                             frame_keys=[(f"{i}.jpg", None) for i in range(6)])
    check(len(apart) == 1 and len(apart[0].indices) == 6, f"in separate photos they are one person: {apart}")


@test
def test_cluster_faces_uses_quality_and_group_size():
    import person_linking as pl

    params = pl.params_for("balanced")
    e = np.vstack([identity(14, 5), identity(15, 1)])
    clusters = pl.cluster_faces(e, [0.9] * 5 + [0.9], params)
    check(len(clusters) == 1 and len(clusters[0].indices) == 5,
          f"a lone face must not become a group: {[len(c.indices) for c in clusters]}")

    low = pl.cluster_faces(identity(16, 6), [0.1] * 6, params)
    check(low == [], f"faces below seed quality must not start groups: {low}")


@test
def test_cluster_merge_folds_split_groups_of_one_person():
    import person_linking as pl

    # One person in two looks (e.g. with and without glasses): tight average
    # linkage splits them, the merge pass should put them back together.
    e = np.vstack([identity(17, 8, spread=0.3), identity(17, 8, spread=0.3, shift=0.9)])
    tight = pl.with_overrides(pl.params_for("balanced"), cluster_distance=0.2, merge_auto=2.0)
    merging = pl.with_overrides(tight, merge_auto=0.6)
    check(len(pl.cluster_faces(e, [0.8] * 16, tight)) == 2, "fixture should split into two looks")
    merged = pl.cluster_faces(e, [0.8] * 16, merging)
    check(len(merged) == 1 and len(merged[0].indices) == 16, f"the two looks should be folded: {merged}")

    # Two different people must not be folded together by the same pass
    two = np.vstack([identity(18, 8, spread=0.3), identity(19, 8, spread=0.3)])
    check(len(pl.cluster_faces(two, [0.8] * 16, merging)) == 2, "different people must stay apart")


@test
def test_suggest_merges_flags_the_same_person_only():
    import person_linking as pl

    a, b = identity(20, 16), identity(21, 16)
    models = pl.build_person_models(np.vstack([a[:8], a[8:], b]), [1] * 8 + [2] * 8 + [3] * 16, [0.8] * 32)
    params = pl.params_for("balanced")
    pairs = pl.suggest_merges(models, params)
    check([(p[0], p[1]) for p in pairs] == [(1, 2)], f"only the split person should be suggested: {pairs}")
    check(pl.suggest_merges(models, params, distinct=[(1, 2)]) == [],
          "a pair marked as different people must not come back")


# ---------------------------------------------------------------------------
# person_linking - faces <-> bodies
# ---------------------------------------------------------------------------

@test
def test_associate_faces_bodies_matches_crossing_pairs():
    import person_linking as pl

    # Two people side by side; the face boxes are given in the opposite order
    left = body_with_head(0, 0, 100, 300, (50, 30))
    right = body_with_head(120, 0, 220, 300, (170, 30))
    faces = [np.array([150, 10, 190, 60]), np.array([30, 10, 70, 60])]
    pairs = pl.associate_faces_bodies(faces, [left, right], face_kps=None)
    check(sorted(pairs)[0][:2] == (0, 1) and sorted(pairs)[1][:2] == (1, 0),
          f"faces matched to the wrong bodies: {pairs}")


@test
def test_associate_faces_bodies_is_one_to_one_and_rejects_bad_pairs():
    import person_linking as pl

    body = body_with_head(0, 0, 100, 300, (50, 30))
    close = np.array([30, 10, 70, 60])
    elsewhere = np.array([400, 400, 440, 450])
    pairs = pl.associate_faces_bodies([close, elsewhere], [body])
    check(len(pairs) == 1 and pairs[0][0] == 0, f"only the contained face may match: {pairs}")

    feet = np.array([30, 250, 70, 295])  # inside the box, but at the feet
    check(pl.face_body_score(feet, body.bbox, None, body.kpts, body.kpt_scores)
          < pl.face_body_score(close, body.bbox, None, body.kpts, body.kpt_scores),
          "a face at the feet should score below a face at the head")


@test
def test_body_extent_reads_visible_keypoints():
    import person_linking as pl

    scores = np.zeros(17, dtype=np.float32)
    scores[[0, 5, 6]] = 0.9
    check(pl.body_extent(scores) == "head", "only head/shoulders visible")
    scores[[11, 12]] = 0.9
    check(pl.body_extent(scores) == "upper", "hips visible -> upper body")
    scores[[15, 16]] = 0.9
    check(pl.body_extent(scores) == "full", "ankles visible -> full body")
    check(pl.body_extent(None) is None, "no keypoints -> unknown")


# ---------------------------------------------------------------------------
# person_linking - outfits and faceless bodies
# ---------------------------------------------------------------------------

def outfit_image(torso_bgr, legs_bgr, size=(400, 200)):
    img = np.full((size[0], size[1], 3), 30, dtype=np.uint8)
    img[80:210, 40:160] = torso_bgr
    img[215:370, 50:150] = legs_bgr
    return img


@test
def test_appearance_descriptor_matches_the_same_outfit():
    import person_linking as pl

    red_blue = pl.appearance_descriptor(outfit_image((40, 40, 200), (150, 60, 40)), (20, 40, 180, 390))
    red_blue2 = pl.appearance_descriptor(outfit_image((45, 45, 205), (155, 65, 45)), (20, 40, 180, 390))
    green_white = pl.appearance_descriptor(outfit_image((60, 180, 60), (240, 240, 240)), (20, 40, 180, 390))
    check(len(red_blue) == 2 * pl.REGION_LEN, f"descriptor length {len(red_blue)}")
    same = pl.appearance_similarity(red_blue, red_blue2)
    different = pl.appearance_similarity(red_blue, green_white)
    check(same > 0.9, f"the same outfit should match: {same:.3f}")
    check(different < 0.4, f"different outfits should not: {different:.3f}")
    check(pl.appearance_similarity(red_blue, None) == 0.0, "missing descriptor -> no similarity")


@test
def test_appearance_similarity_compares_shared_regions_only():
    import person_linking as pl

    full = pl.appearance_descriptor(outfit_image((40, 40, 200), (150, 60, 40)), (20, 40, 180, 390))
    torso_only = np.concatenate([full[:pl.REGION_LEN], np.zeros(pl.REGION_LEN, dtype=np.float32)])
    check(pl.appearance_similarity(full, torso_only) > 0.95,
          "an upper-body shot should still match the same outfit")


@test
def test_link_faceless_bodies_uses_outfit_within_one_video():
    import person_linking as pl

    red = pl.appearance_descriptor(outfit_image((40, 40, 200), (150, 60, 40)), (20, 40, 180, 390))
    red2 = pl.appearance_descriptor(outfit_image((44, 44, 198), (152, 62, 42)), (20, 40, 180, 390))
    green = pl.appearance_descriptor(outfit_image((60, 180, 60), (240, 240, 240)), (20, 40, 180, 390))
    bodies = [
        {"id": 1, "media_id": 9, "frame_number": 0, "appearance": red, "face_id": 11},     # anchor: person 5
        {"id": 2, "media_id": 9, "frame_number": 30, "appearance": red2},                  # same outfit later
        {"id": 3, "media_id": 9, "frame_number": 30, "appearance": green},                 # someone else
        {"id": 4, "media_id": 8, "frame_number": 0, "appearance": red2},                   # other file
    ]
    anchors = {1: 5}
    links = pl.link_faceless_bodies(bodies, lambda b: anchors.get(b["id"]), {}, pl.params_for("balanced"))
    by_id = {l.body_id: l for l in links}
    check(2 in by_id and by_id[2].person_id == 5 and by_id[2].decision == "auto",
          f"the same outfit in the same video should link: {links}")
    check(3 not in by_id, f"a different outfit must not link: {links}")
    check(4 not in by_id, "outfits must not link across different files")


@test
def test_link_faceless_bodies_uses_a_weak_face_and_frame_conflicts():
    import person_linking as pl

    a = identity(30, 10)
    models = pl.build_person_models(a[:8], [4] * 8, [0.8] * 8)
    params = pl.params_for("balanced")
    bodies = [{"id": 1, "media_id": 3, "frame_number": 5, "weak_face_embedding": a[9]}]
    links = pl.link_faceless_bodies(bodies, lambda b: None, models, params)
    check(links and links[0].person_id == 4 and links[0].method == "weak_face",
          f"a low-quality face that clearly matches should link: {links}")

    anchor_outfit = pl.appearance_descriptor(outfit_image((40, 40, 200), (150, 60, 40)), (20, 40, 180, 390))
    bodies = [
        {"id": 1, "media_id": 3, "frame_number": 0, "appearance": anchor_outfit, "face_id": 1},
        {"id": 2, "media_id": 3, "frame_number": 0, "appearance": anchor_outfit},  # same frame as the anchor
    ]
    links = pl.link_faceless_bodies(bodies, lambda b: 4 if b["id"] == 1 else None, models, params)
    check(links == [], f"a body in the same frame as that person can't be them too: {links}")


# ---------------------------------------------------------------------------
# storage
# ---------------------------------------------------------------------------

@test
def test_database_bodies_media_and_feedback():
    db, tmp = temp_db()
    try:
        p1, p2 = db.create_person("A"), db.create_person("B")
        fid = db.add_face(np.random.rand(512), "clip.mp4", person_id=p1, quality_score=0.8,
                          extra={"media_id": 1, "frame_number": 30})
        check(db.get_face(fid)["frame_number"] == 30, "extra metadata must be stored")
        mid = db.upsert_media("clip.mp4", {"type": "video", "detections": [[30, 1.0, "f", fid, 0, 0, 5, 5]]})
        check(db.get_media_by_path("CLIP.MP4")["id"] == mid, "media lookup is path-normalised")
        b1 = db.add_body({"media_id": mid, "face_id": fid, "bbox": {"x": 0, "y": 0, "w": 9, "h": 9}})
        b2 = db.add_body({"media_id": mid, "bbox": {"x": 0, "y": 0, "w": 9, "h": 9}})
        check(db.body_person_id(db.get_body(b1)) == p1, "a body follows its face's person")
        check(db.body_person_id(db.get_body(b2)) is None, "an unlinked body belongs to nobody")
        db.link_body_to_person(b2, p1, "appearance", 0.9)
        check(len(db.get_bodies_by_person(p1)) == 2, "both bodies should be under the person")
        check(db.media_person_ids(mid) == {p1}, "media should report who is in it")

        db.reject_face_from_person(fid, p1)
        check(db.get_face(fid)["person_id"] is None and db.get_face(fid)["rejected_person_ids"] == [p1],
              "rejecting must unassign and remember")
        db.mark_persons_distinct(p1, p2)
        check(db.distinct_pairs() == [(p1, p2)], "distinct pairs must round-trip")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@test
def test_database_merge_moves_everything():
    db, tmp = temp_db()
    try:
        p1, p2, p3 = db.create_person("A"), db.create_person("B"), db.create_person("C")
        fid = db.add_face(np.random.rand(512), "a.jpg", person_id=p1, quality_score=0.9)
        other = db.add_face(np.random.rand(512), "b.jpg", quality_score=0.9)
        db.reject_face_from_person(other, p1)
        bid = db.add_body({"media_id": 1, "bbox": {}})
        db.link_body_to_person(bid, p1, "manual")
        db.set_person_avatar(p1, fid)
        db.mark_persons_distinct(p1, p3)

        check(db.merge_persons(p1, p2), "merge should succeed")
        check(db.get_face(fid)["person_id"] == p2, "faces move to the target")
        check(db.get_body(bid)["person_id"] == p2, "bodies move to the target")
        check(db.get_face(other)["rejected_person_ids"] == [p2], "'not this person' follows the merge")
        check(db.persons[p2]["avatar_face_id"] == fid, "the target with no cover takes the source's")
        check(db.distinct_pairs() == [(min(p2, p3), max(p2, p3))], "'different people' follows the merge")
        check(db.persons[p2]["face_count"] == 1, "face_count must be kept straight")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@test
def test_database_batch_writes_once_and_reloads_outside_changes():
    import json
    import os

    db, tmp = temp_db()
    try:
        db.create_person("A")
        before = os.stat(tmp / "faces.json").st_mtime_ns if (tmp / "faces.json").exists() else None
        with db.batch():
            for i in range(10):
                db.add_face(np.random.rand(512), f"{i}.jpg", quality_score=0.5)
            now = os.stat(tmp / "faces.json").st_mtime_ns if (tmp / "faces.json").exists() else None
            check(now == before, "writes must be deferred inside batch()")
        check(os.stat(tmp / "faces.json").st_mtime_ns != before, "batch() must write on exit")

        raw = json.load(open(tmp / "persons.json", encoding="utf-8"))
        pid = next(iter(raw["items"]))
        raw["items"][pid]["name"] = "Changed elsewhere"
        json.dump(raw, open(tmp / "persons.json", "w", encoding="utf-8"))
        db.create_person("C")
        check(db.get_person(int(pid))["name"] == "Changed elsewhere",
              "a change made by another process must not be clobbered")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@test
def test_database_embedding_cache_tracks_added_faces():
    db, tmp = temp_db()
    try:
        vecs = identity(40, 5)
        ids = [db.add_face(v, f"{i}.jpg", quality_score=0.7) for i, v in enumerate(vecs)]
        matrix, cached_ids = db._get_embedding_matrix()
        check(matrix.shape == (5, 512) and cached_ids == ids, f"cache out of step: {matrix.shape}, {cached_ids}")
        dup = db.find_duplicate(vecs[2].tolist(), 0.05)
        check(dup and dup[0] == ids[2], f"duplicate lookup should find the identical face: {dup}")
        db.delete_face(ids[2], delete_file=False)
        matrix, cached_ids = db._get_embedding_matrix()
        check(matrix.shape[0] == 4 and ids[2] not in cached_ids, "cache must drop deleted faces")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------------------
# library_scanner
# ---------------------------------------------------------------------------

class StubScanner:
    """LibraryScanner with the models replaced by scripted detections."""

    def __new__(cls, db, faces_per_frame, tmp, bodies_per_frame=None):
        from library_scanner import LibraryScanner, ScanOptions

        scanner = LibraryScanner(db=db, options=ScanOptions(detect_bodies=bodies_per_frame is not None,
                                                            save_body_crops=False),
                                 log=lambda *_: None,
                                 face_crop_dir=tmp / "faces", body_crop_dir=tmp / "bodies")
        scanner._frame = 0
        scanner.detect_faces = lambda img: faces_per_frame(scanner._frame)
        scanner.assess_face = lambda img, face: _stub_quality(face)
        if bodies_per_frame is not None:
            class _Body:
                available = True

                def analyze(self, img, score_thr=0.5):
                    return bodies_per_frame(scanner._frame)
            scanner._body = _Body()
        inner = scanner._scan_frame

        def counting(img, state, frame_number, timestamp, summary):
            out = inner(img, state, frame_number, timestamp, summary)
            scanner._frame += 1
            return out
        scanner._scan_frame = counting
        return scanner


def _stub_quality(face):
    import face_quality
    parts = face_quality.components(face_px=float(face.bbox[2] - face.bbox[0]),
                                    embedding_norm=face.embedding_norm, sharp=500.0, yaw=0.0, pitch=0.0)
    return {"quality_score": face_quality.score(parts), "quality_version": face_quality.QUALITY_VERSION,
            "quality_parts": parts, "det_score": face.det_score,
            "face_px": float(face.bbox[2] - face.bbox[0]), "sharpness": 500.0,
            "embedding_norm": face.embedding_norm, "pose": {"yaw": 0.0, "pitch": 0.0, "roll": 0.0}}


def write_photo(path, color=(60, 90, 160)):
    import cv2
    img = np.full((600, 400, 3), color, dtype=np.uint8)
    cv2.imwrite(str(path), img)
    return img


@test
def test_scanner_stores_faces_bodies_and_media_for_a_photo():
    from library_scanner import is_video

    db, tmp = temp_db()
    try:
        photo = tmp / "party.jpg"
        write_photo(photo)
        vecs = identity(50, 2)
        faces = [FakeFace((40, 40, 140, 140), vecs[0]), FakeFace((240, 40, 340, 140), vecs[1])]
        bodies = [body_with_head(20, 30, 160, 500, (90, 90)), body_with_head(220, 30, 360, 500, (290, 90))]
        scanner = StubScanner(db, lambda i: faces, tmp, lambda i: bodies)
        summary = scanner.scan_file(photo)

        check(summary.faces_new == 2 and summary.bodies_new == 2, f"expected 2 faces + 2 bodies: {summary}")
        media = db.get_media_by_path(photo)
        check(media["type"] == "image" and media["scan_status"] == "done", f"media record wrong: {media}")
        check(len(media["detections"]) == 4, f"all detections should be recorded: {media['detections']}")
        stored = [f for f in db.faces.values()]
        check(all(f["media_id"] == media["id"] for f in stored), "faces must point at the media record")
        check(all(f["quality_version"] == 2 for f in stored), "quality v2 must be stamped")
        linked = {b["face_id"] for b in db.get_bodies_by_media(media["id"])}
        check(linked == {f["id"] for f in stored}, f"each body should carry its own face: {linked}")
        check(all(b["appearance"] for b in db.get_all_bodies()), "bodies need an outfit descriptor")
        check(not is_video(photo), "sanity: a .jpg is not a video")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@test
def test_scanner_skips_unchanged_files_and_links_rescanned_faces():
    db, tmp = temp_db()
    try:
        photo = tmp / "one.jpg"
        write_photo(photo)
        vec = identity(51, 1)[0]
        faces = [FakeFace((40, 40, 140, 140), vec)]
        scanner = StubScanner(db, lambda i: faces, tmp)
        scanner.scan_file(photo)
        check(len(db.faces) == 1, "first scan stores the face")

        second = scanner.scan_file(photo)
        check(second.files_skipped == 1 and len(db.faces) == 1, f"unchanged file must be skipped: {second}")

        scanner.options.rescan = True
        third = scanner.scan_file(photo)
        check(len(db.faces) == 1, f"a re-scan must link, not duplicate: {len(db.faces)} faces")
        check(third.faces_linked == 1, f"the face should be reported as linked: {third}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@test
def test_scanner_keeps_one_record_for_near_identical_video_frames():
    import cv2

    db, tmp = temp_db()
    try:
        clip = tmp / "clip.avi"
        writer = cv2.VideoWriter(str(clip), cv2.VideoWriter_fourcc(*"MJPG"), 10.0, (400, 600))
        for _ in range(30):
            writer.write(np.full((600, 400, 3), 100, dtype=np.uint8))
        writer.release()
        check(clip.exists(), "fixture video not written")

        base = identity(52, 1)[0]
        drift = [base, base * 0.999 + 0.001 * identity(53, 1)[0], identity(54, 1)[0]]
        drift = [v / np.linalg.norm(v) for v in drift]
        scanner = StubScanner(db, lambda i: [FakeFace((40, 40, 140, 140), drift[min(i, 2)])], tmp)
        summary = scanner.scan_file(clip)

        check(summary.faces_new == 2, f"near-identical frames should not pile up: {summary}")
        media = db.get_media_by_path(clip)
        check(media["frames_scanned"] >= 3, f"frames should be sampled: {media['frames_scanned']}")
        stored = list(db.faces.values())
        check(all(f["frame_number"] is not None for f in stored), "video faces need frame numbers")
        check(all(f["timestamp"] is not None for f in stored), "video faces need timestamps")
        check(len(media["detections"]) >= 3, "every sampled detection should be recorded for the timeline")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@test
def test_scanner_falls_back_when_a_file_is_unreadable():
    from library_scanner import LibraryScanner, ScanOptions, collect_media

    db, tmp = temp_db()
    try:
        broken = tmp / "broken.jpg"
        broken.write_bytes(b"not an image")
        good = tmp / "good.jpg"
        write_photo(good)
        scanner = StubScanner(db, lambda i: [FakeFace((40, 40, 140, 140), identity(55, 1)[0])], tmp)
        summary = scanner.scan_paths([broken, good])
        check(summary.errors and "broken.jpg" in summary.errors[0], f"the error should be reported: {summary}")
        check(summary.faces_new == 1, "the readable file must still be scanned")
        check(len(collect_media(tmp)) >= 2, "collect_media should find the fixtures")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@test
def test_scanner_handles_non_ascii_paths():
    from library_scanner import imread, imwrite

    tmp = Path(tempfile.mkdtemp(prefix="gallery_unicode_"))
    try:
        path = tmp / "صورة_عائلية.jpg"
        img = np.full((40, 30, 3), 77, dtype=np.uint8)
        check(imwrite(path, img), "writing to a non-ASCII path should work")
        back = imread(path)
        check(back is not None and back.shape == (40, 30, 3), "reading a non-ASCII path should work")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------------------
# gallery_grouping
# ---------------------------------------------------------------------------

def seed_library(db, people=3, per_person=6, assigned_first=True):
    """A synthetic library: `people` identities, first one optionally curated."""
    ids = []
    with db.batch():
        for p in range(people):
            vecs = identity(60 + p, per_person)
            pid = None
            if assigned_first and p == 0:
                pid = db.create_person(f"Known {p}")
            for i, v in enumerate(vecs):
                ids.append(db.add_face(v, f"p{p}_{i}.jpg", person_id=pid if i < 3 else None,
                                       quality_score=0.8, extra={"media_id": 100 + p * 10 + i}))
    return ids


@test
def test_group_library_matches_known_people_and_creates_new_ones():
    import gallery_grouping as gg

    db, tmp = temp_db()
    try:
        seed_library(db)
        summary = gg.group_library(db, "balanced", log=lambda *_: None)
        check(summary.assigned_to_existing == 3,
              f"the 3 loose faces of the known person should be matched: {summary}")
        check(summary.new_people == 2, f"the two unknown people should be created: {summary}")
        check(summary.pending_faces == 0, f"nothing should be left over: {summary}")
        names = sorted(p["name"] for p in db.get_all_persons())
        check(any(p.get("auto_created") for p in db.get_all_persons()), f"new people are flagged: {names}")
        for person in db.get_all_persons():
            check(db.get_person_avatar_face(person["id"]), f"{person['name']} should resolve a cover face")
            if person.get("auto_created"):
                check(person.get("avatar_face_id"), "a new person should get an explicit cover")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@test
def test_group_library_leaves_uncertain_faces_for_review():
    import gallery_grouping as gg

    db, tmp = temp_db()
    try:
        with db.batch():
            pid = db.create_person("Known")
            for v in identity(70, 4):
                db.add_face(v, "known.jpg", person_id=pid, quality_score=0.8)
            lone = db.add_face(identity(71, 1)[0], "stranger.jpg", quality_score=0.8)
        summary = gg.group_library(db, "balanced", log=lambda *_: None)
        check(summary.new_people == 0, "one stray face is not a person")
        check(db.get_face(lone)["person_id"] is None, "a stranger must not be forced onto a known person")
        check(summary.pending_faces == 1, f"the stray face should be pending: {summary}")

        state = gg.review_state(db, "balanced")
        check(state.unsorted_face_ids == [lone], f"it should show up as unsorted: {state.unsorted_face_ids}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@test
def test_review_state_suggests_faces_groups_and_duplicates():
    import gallery_grouping as gg

    db, tmp = temp_db()
    try:
        with db.batch():
            # one known person, curated from half of their faces
            vecs = identity(80, 10)
            pid = db.create_person("Known")
            for v in vecs[:5]:
                db.add_face(v, "known.jpg", person_id=pid, quality_score=0.8)
            borderline = [db.add_face(v, f"loose{i}.jpg", quality_score=0.8) for i, v in enumerate(vecs[5:])]
            # a second person, split into two curated halves -> duplicate suggestion
            other = identity(81, 10)
            p2, p3 = db.create_person("Split A"), db.create_person("Split B")
            for v in other[:5]:
                db.add_face(v, "a.jpg", person_id=p2, quality_score=0.8)
            for v in other[5:]:
                db.add_face(v, "b.jpg", person_id=p3, quality_score=0.8)

        state = gg.review_state(db, "balanced")
        check(pid in state.suggestions and state.suggestions[pid], f"loose faces should be suggested: {state}")
        check({s.face_id for s in state.suggestions[pid]} <= set(borderline), "wrong faces suggested")
        check(any({a, b} == {p2, p3} for a, b, _ in state.duplicates),
              f"the split person should be flagged as a duplicate: {state.duplicates}")
        check(state.total > 0 and state.suggested_face_count == len(state.suggestions[pid]), "counters")

        gg.reject_faces(db, [state.suggestions[pid][0].face_id], pid)
        after = gg.review_state(db, "balanced")
        check(state.suggestions[pid][0].face_id not in {s.face_id for s in after.suggestions.get(pid, [])},
              "a rejected suggestion must not come back")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@test
def test_group_library_links_bodies_by_outfit():
    import gallery_grouping as gg
    import person_linking as pl

    db, tmp = temp_db()
    try:
        red = pl.appearance_descriptor(outfit_image((40, 40, 200), (150, 60, 40)), (20, 40, 180, 390))
        with db.batch():
            pid = db.create_person("Known")
            fid = db.add_face(identity(90, 1)[0], "clip.mp4", person_id=pid, quality_score=0.8,
                              extra={"media_id": 7, "frame_number": 0})
            anchor = db.add_body({"media_id": 7, "frame_number": 0, "face_id": fid,
                                  "appearance": [float(v) for v in red], "bbox": {}})
            faceless = db.add_body({"media_id": 7, "frame_number": 90,
                                    "appearance": [float(v) for v in red], "bbox": {}})
            stranger = db.add_body({"media_id": 7, "frame_number": 90, "bbox": {},
                                    "appearance": [float(v) for v in pl.appearance_descriptor(
                                        outfit_image((60, 180, 60), (240, 240, 240)), (20, 40, 180, 390))]})
        summary = gg.group_library(db, "balanced", log=lambda *_: None)
        check(summary.bodies_linked == 1, f"only the matching outfit should link: {summary}")
        check(db.body_person_id(db.get_body(faceless)) == pid, "the faceless body should join the person")
        check(db.get_body(faceless)["link_method"] == "appearance", "the link method should be recorded")
        check(db.body_person_id(db.get_body(stranger)) is None, "a different outfit must stay unlinked")

        db.reject_body_from_person(faceless, pid)
        gg.group_library(db, "balanced", log=lambda *_: None)
        check(db.body_person_id(db.get_body(faceless)) is None, "a rejected body link must not come back")
        check(db.body_person_id(db.get_body(anchor)) == pid, "the anchor body stays with its face")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@test
def test_group_library_respects_manual_body_links():
    import gallery_grouping as gg

    db, tmp = temp_db()
    try:
        with db.batch():
            pid = db.create_person("Known")
            db.add_face(identity(91, 1)[0], "a.jpg", person_id=pid, quality_score=0.8, extra={"media_id": 5})
            manual = db.add_body({"media_id": 5, "frame_number": 0, "bbox": {}})
        db.link_body_to_person(manual, pid, "manual")
        gg.group_library(db, "balanced", log=lambda *_: None)
        check(db.get_body(manual)["link_method"] == "manual", "a manual link must survive regrouping")
        check(db.body_person_id(db.get_body(manual)) == pid, "and keep its person")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main(argv):
    pattern = argv[0] if argv else ""
    selected = [t for t in _TESTS if pattern in t.__name__]
    if not selected:
        known = ", ".join(t.__name__ for t in _TESTS)
        print(f"No test matches '{pattern}'.\nKnown: {known}")
        return 1

    failed = 0
    for t in selected:
        try:
            t()
            print(f"[PASS] {t.__name__}")
        except Exception as e:
            failed += 1
            print(f"[FAIL] {t.__name__}: {e}")
            traceback.print_exc()

    print(f"\n{len(selected) - failed}/{len(selected)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
