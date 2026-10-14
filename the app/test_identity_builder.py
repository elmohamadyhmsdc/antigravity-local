"""
Antigravity Local - identity builder tests

Standalone script (the repo has no pytest). CPU only, fake faces, no models.

    venv\\Scripts\\python.exe test_identity_builder.py           # everything
    venv\\Scripts\\python.exe test_identity_builder.py assign    # names containing "assign"
"""

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


_RNG = np.random.default_rng(42)


def _unit(v):
    v = np.asarray(v, np.float32)
    return v / np.linalg.norm(v)


P = _unit(_RNG.standard_normal(512))      # the person
Q = _unit(_RNG.standard_normal(512))      # somebody else


def _shot(base, spread=0.8):
    """Another photo of the same person: cosine ~0.6-0.8 to the others, like real photos."""
    return _unit(base + spread * _unit(_RNG.standard_normal(512)))


def _cand(emb, quality=0.7, face_px=200, det=0.9, yaw=0.0, pitch=0.0, source="x.jpg", frame=None):
    from identity_builder import Candidate
    return Candidate(source=source, frame=frame, embedding=np.asarray(emb, np.float32) * 22.0,
                     quality=quality, face_px=face_px, det_score=det, yaw=yaw, pitch=pitch)


@test
def test_assign_picks_the_person_not_the_most_confident_face():
    """faces[0] (what the old builder took) is the detector's favourite, not the person."""
    from identity_builder import assign_identity

    groups = [[_cand(_shot(P))] for _ in range(5)]                     # P alone
    groups += [[_cand(_shot(Q)), _cand(_shot(P))] for _ in range(3)]   # Q first, P second
    groups += [[_cand(_shot(Q))] for _ in range(2)]                    # Q alone
    picked, anchor = assign_identity(groups)
    check(len(picked) == 8, f"P is in 8 pictures, picked {len(picked)}")
    check(float(anchor @ P) > 0.9, f"identity should be P, cos={float(anchor @ P):.2f}")
    check(all(float(f.unit @ P) > float(f.unit @ Q) for f in picked), "every pick must be P")


@test
def test_assign_follows_a_seed():
    from identity_builder import assign_identity

    groups = [[_cand(_shot(P)), _cand(_shot(Q))] for _ in range(4)]
    picked, anchor = assign_identity(groups, seed=Q)
    check(len(picked) == 4 and float(anchor @ Q) > 0.9, "with a seed of Q, Q is picked in every photo")


@test
def test_assign_skips_an_ambiguous_picture():
    from identity_builder import assign_identity

    twin = _unit(P + 0.05 * _unit(_RNG.standard_normal(512)))
    groups = [[_cand(_shot(P))] for _ in range(4)] + [[_cand(_shot(P, 0.3)), _cand(twin)]]
    picked, _ = assign_identity(groups)
    check(len(picked) == 4, f"two near-identical faces in one photo must be skipped, picked {len(picked)}")


@test
def test_filters_drop_small_blurry_duplicate_and_outlier_faces():
    from identity_builder import filter_faces, weighted_identity

    good = [_cand(_shot(P), quality=0.6 + 0.02 * i) for i in range(8)]
    small = _cand(_shot(P), face_px=40)
    blurry = _cand(_shot(P), quality=0.2)
    dup = _cand(good[0].unit * 1.0 + 0.0, quality=0.5)                 # same shot again
    stranger = _cand(_shot(Q), quality=0.9)                             # slipped through assignment
    faces = good + [small, blurry, dup, stranger]
    kept, dropped = filter_faces(faces, weighted_identity(good))
    reasons = {id(f): f.status for f in dropped}
    check(id(small) in reasons and "smaller" in reasons[id(small)], "a tiny face is dropped")
    check(id(blurry) in reasons and "quality" in reasons[id(blurry)], "a low-quality face is dropped")
    check(id(dup) in reasons and "duplicate" in reasons[id(dup)], "the same shot twice counts once")
    check(id(stranger) in reasons and "unlike" in reasons[id(stranger)], "an outlier is dropped")
    check(len(kept) == 8, f"the 8 good shots survive, got {len(kept)}")


@test
def test_pose_diverse_selection_caps_one_pose():
    from identity_builder import PER_POSE_BUCKET, select_pose_diverse

    front = [_cand(_shot(P), quality=0.5 + i * 0.01, yaw=2.0) for i in range(20)]
    side = [_cand(_shot(P), yaw=40.0) for _ in range(3)]
    kept, dropped = select_pose_diverse(front + side)
    check(sum(1 for f in kept if f.yaw < 10) == PER_POSE_BUCKET, "frontal frames are capped")
    check(sum(1 for f in kept if f.yaw > 30) == 3, "rare poses are all kept")
    check(max(f.quality for f in kept if f.yaw < 10) == max(f.quality for f in front),
          "the best frontal frames are the ones kept")


@test
def test_coverage_and_grade():
    from identity_builder import coverage, grade

    faces = [_cand(P, yaw=0), _cand(P, yaw=-35), _cand(P, yaw=35), _cand(P, pitch=20)]
    c = coverage(faces)
    check(c["front"] == 1 and c["left"] == 1 and c["right"] == 1 and c["up"] == 1, f"coverage {c}")
    check(grade(40, c, 0.78) in ("A", "B"), "many consistent, varied faces grade well")
    check(grade(3, {"front": 3}, 0.5) == "D", "three frontal faces grade poorly")


class _FakeFace:
    def __init__(self, emb, bbox, det=0.9):
        self.embedding = np.asarray(emb, np.float32) * 22.0
        self.bbox = np.asarray(bbox, np.float32)
        x1, y1, x2, y2 = bbox
        cx, cy, w = (x1 + x2) / 2, (y1 + y2) / 2, (x2 - x1)
        self.kps = np.array([[cx - w * 0.18, cy - w * 0.1], [cx + w * 0.18, cy - w * 0.1], [cx, cy + w * 0.05],
                             [cx - w * 0.14, cy + w * 0.25], [cx + w * 0.14, cy + w * 0.25]], np.float32)
        self.det_score = det
        self.pose = np.array([0.0, 0.0, 0.0], np.float32)

    @property
    def embedding_norm(self):
        return float(np.linalg.norm(self.embedding))


class _FakeApp:
    """Returns preset faces per image, keyed by the image's top-left pixel value."""

    def __init__(self, faces_by_key):
        self.faces_by_key = faces_by_key

    def get(self, img):
        return self.faces_by_key.get(int(img[0, 0, 0]), [])


@test
def test_build_identity_end_to_end_and_save():
    import cv2
    import identity_builder as ib
    from identity import build_source_from_faceset
    from reface_engine import Faceset

    tmp = Path(tempfile.mkdtemp())
    rng = np.random.default_rng(7)
    faces_by_key, paths = {}, []
    for k in range(1, 9):
        img = (rng.integers(0, 255, (480, 480, 3))).astype(np.uint8)
        img = cv2.GaussianBlur(img, (0, 0), 1.0)
        img[0, 0, 0] = k
        p = tmp / f"photo_{k}.jpg"
        cv2.imwrite(str(p), img, [cv2.IMWRITE_JPEG_QUALITY, 100])
        img = cv2.imread(str(p))
        key = int(img[0, 0, 0])
        group = [_FakeFace(_shot(P), (140, 120, 340, 360))]
        if k > 5:   # group photos: someone else is the detector's first, bigger face
            group.insert(0, _FakeFace(_shot(Q), (20, 20, 260, 300), det=0.99))
        faces_by_key[key] = group
        paths.append(str(p))

    import face_quality
    original_assess = face_quality.assess
    face_quality.assess = lambda face, aligned: {"quality_score": 0.7, "face_px": float(face.bbox[2] - face.bbox[0]),
                                                 "sharpness": 100.0, "pose": {"yaw": 0.0, "pitch": 0.0}}
    try:
        identity, report = ib.build_identity("Test Person", paths + [str(tmp / "missing.jpg")], _FakeApp(faces_by_key))
    finally:
        face_quality.assess = original_assess

    check(identity is not None, f"identity expected, report {report}")
    check(report["unreadable"] == [str(tmp / "missing.jpg")], "unreadable files are reported")
    check(report["pictures_with_the_person"] == 8, f"P is in all 8 photos: {report}")
    check(float(identity.vector @ P) > 0.9, "the identity is P, not the bigger face in group photos")

    folder = ib.save_identity(identity, root=tmp / "identities", facesets_dir=tmp / "facesets")
    check((folder / "manifest.json").exists() and (folder / "embeddings.npy").exists(), "identity files written")
    check(len(list((folder / "crops").glob("*.jpg"))) == identity.report["kept"], "one aligned crop per kept face")
    fs = Faceset.load(tmp / "facesets" / f"{identity.slug}.pkl")
    src = build_source_from_faceset(fs)
    check(src is not None and float(src.normed_embedding @ P) > 0.9, "the faceset the engines load is P")
    check(ib.list_identities(tmp / "identities") == [identity.slug], "identity is listed")


def main(argv):
    pattern = argv[0] if argv else ""
    selected = [t for t in _TESTS if pattern in t.__name__]
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
