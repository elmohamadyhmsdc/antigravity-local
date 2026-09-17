"""
Antigravity Local - lora_identity.py tests

Standalone script (the repo has no pytest). No GPU, no models: real photos and
generated portraits are stubbed with synthetic vectors, a fake face analyzer,
and a real (but temp-backed) JobManager. Prints results, exit(1) on failure.

    venv\\Scripts\\python.exe test_lora_identity.py            # everything
    venv\\Scripts\\python.exe test_lora_identity.py gate       # only names containing "gate"
"""

import sys
import traceback

_TESTS = []


def test(fn):
    _TESTS.append(fn)
    return fn


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


@test
def test_imports():
    import lora_identity  # noqa: F401


@test
def test_faceset_round_trip():
    import tempfile
    from pathlib import Path

    import numpy as np

    from identity import build_source_from_faceset
    from lora_identity import faceset_from_detections
    from reface_engine import FaceData, Faceset

    rng = np.random.default_rng(0)
    detections = [
        FaceData(image_path=f"face_{i}.jpg", embedding=(rng.normal(size=512) * 3).astype(np.float32),
                 pose=(float(i), -1.0, 2.5), bbox=[i, i, i + 10, i + 10], quality=0.5 + i * 0.1)
        for i in range(4)
    ]
    faceset = faceset_from_detections("rt_test", detections)

    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "rt_test.pkl"
        faceset.save(path)
        loaded = Faceset.load(path)

    check(len(loaded.faces) == 4, f"expected 4 faces after the round trip, got {len(loaded.faces)}")
    for original, restored in zip(detections, loaded.faces):
        check(restored.quality == original.quality, "quality should survive the round trip")
        check(list(restored.bbox) == list(original.bbox), "bbox should survive the round trip")
        check(tuple(restored.pose) == tuple(original.pose), "pose should survive the round trip")

    source = build_source_from_faceset(loaded)
    check(source is not None, "build_source_from_faceset should return a source for a non-empty faceset")
    check(source.normed_embedding.shape == (512,), f"expected shape (512,), got {source.normed_embedding.shape}")
    norm = float(np.linalg.norm(source.normed_embedding))
    check(abs(norm - 1.0) < 1e-5, f"expected unit norm, got {norm}")


@test
def test_filter_by_anchor_gate():
    import numpy as np

    from lora_identity import filter_by_anchor
    from reface_engine import FaceData

    anchor = np.zeros(512, dtype=np.float32)
    anchor[0] = 1.0

    def face_at(cos_theta, name):
        # A 2D construction in the (e0, e1) plane gives an exact known cosine similarity to `anchor`.
        sin_theta = (1 - cos_theta ** 2) ** 0.5
        v = np.zeros(512, dtype=np.float32)
        v[0], v[1] = cos_theta, sin_theta
        return FaceData(image_path=name, embedding=v, pose=(0.0, 0.0, 0.0), bbox=[0, 0, 1, 1], quality=1.0)

    faces = [face_at(0.9, "high"), face_at(0.5, "mid"), face_at(0.1, "low")]
    kept, dropped = filter_by_anchor(faces, anchor, min_similarity=0.4)

    check([f.image_path for f in kept] == ["high", "mid"], f"expected high+mid kept, got {[f.image_path for f in kept]}")
    check([f.image_path for f, _ in dropped] == ["low"], f"expected low dropped, got {dropped}")
    _, dropped_score = dropped[0]
    check(abs(dropped_score - 0.1) < 1e-4, f"dropped entry should carry its similarity score, got {dropped_score}")


@test
def test_clean_generated_images_filter():
    import shutil
    import tempfile
    from datetime import datetime

    import lora_generate_job
    from job_manager import Job, JobManager, JobStatus
    from lora_identity import clean_generated_images

    out_dir = lora_generate_job.generation_output_dir("Test Identity Person")
    with tempfile.TemporaryDirectory() as jobs_tmp:
        jobs = JobManager(jobs_tmp)
        now = datetime.now().isoformat()
        jobs.save_job(Job(id="aaaa1111", job_type="generate_lora_images", status=JobStatus.COMPLETED, progress=1.0,
                          message="", created_at=now, params={"person_name": "Test Identity Person"}))
        jobs.save_job(Job(id="bbbb2222", job_type="generate_lora_images", status=JobStatus.COMPLETED, progress=1.0,
                          message="", created_at=now,
                          params={"person_name": "Test Identity Person", "reference_image": "some_ref.png"}))
        # A third file ("cccc3333") deliberately has no matching job record at all.

        out_dir.mkdir(parents=True, exist_ok=True)
        try:
            (out_dir / "reference_aaaa1111_01_seed5.png").write_bytes(b"x")
            (out_dir / "reference_bbbb2222_01_seed6.png").write_bytes(b"x")
            (out_dir / "reference_cccc3333_01_seed7.png").write_bytes(b"x")
            (out_dir / "not_a_reference_image.png").write_bytes(b"x")

            kept, excluded = clean_generated_images("Test Identity Person", jobs)
            check([p.name for p in kept] == ["reference_aaaa1111_01_seed5.png"],
                 f"expected only the clean job's portrait kept, got {[p.name for p in kept]}")
            excluded_names = {p.name: reason for p, reason in excluded}
            check("reference_bbbb2222_01_seed6.png" in excluded_names,
                 "the reference-image job's portrait should be excluded")
            check("reference_cccc3333_01_seed7.png" in excluded_names,
                 "a portrait with no matching job record should be excluded")
            check("not_a_reference_image.png" not in excluded_names,
                 "a file that doesn't match the reference_*_NN_seed*.png pattern should be ignored entirely")
        finally:
            shutil.rmtree(out_dir, ignore_errors=True)


@test
def test_real_photo_embeddings_source_order():
    import database
    from lora_identity import real_photo_embeddings

    original = database.get_faces_by_person
    try:
        database.get_faces_by_person = lambda person_id: [
            {"embedding": [0.1] * 512, "quality_score": 0.7, "image_path": "g1.jpg",
             "bbox_x": 0, "bbox_y": 0, "bbox_width": 10, "bbox_height": 10}]
        faces, source = real_photo_embeddings(999999, "Nonexistent Lora Identity Person", face_app=None)
        check(source == "gallery", f"gallery faces should take priority over the training set, got source={source!r}")
        check(len(faces) == 1, f"expected 1 gallery face, got {len(faces)}")

        database.get_faces_by_person = lambda person_id: []
        faces, source = real_photo_embeddings(999999, "Nonexistent Lora Identity Person", face_app=None)
        check(faces == [] and source == "", f"expected no real photos when neither source has data, got {(faces, source)}")
    finally:
        database.get_faces_by_person = original


@test
def test_build_lora_faceset_handles_empty_input():
    import tempfile
    from pathlib import Path

    import cv2
    import numpy as np

    import database
    from lora_identity import MODE_LORA, build_lora_faceset

    class _NoFaceApp:
        def get(self, image):
            return []

    class _StubJobs:
        def load_job(self, job_id):
            return None

    original = database.get_faces_by_person
    try:
        database.get_faces_by_person = lambda person_id: [
            {"embedding": [0.1] * 512, "quality_score": 0.7, "image_path": "g1.jpg",
             "bbox_x": 0, "bbox_y": 0, "bbox_width": 10, "bbox_height": 10}]

        with tempfile.TemporaryDirectory() as tmp:
            readable = Path(tmp) / "no_face.jpg"
            cv2.imwrite(str(readable), np.zeros((64, 64, 3), dtype=np.uint8))
            unreadable = Path(tmp) / "does_not_exist.jpg"

            person = {"id": 424242, "name": "Nonexistent Lora Identity Person"}
            faceset, report = build_lora_faceset(person, MODE_LORA, [str(readable), str(unreadable)],
                                                 _NoFaceApp(), _StubJobs())
            check(faceset is None, f"no faces should survive detection, so faceset should be None, got {faceset}")
            check("reason" in report, f"report should explain why nothing was built, got {report}")
            check(report.get("portraits_no_face") == 2, f"both portraits should be counted as no-face, got {report}")
    finally:
        database.get_faces_by_person = original


@test
def test_faceset_name_is_unique_per_build():
    import time

    from lora_identity import faceset_name

    a = faceset_name(42)
    time.sleep(1.1)  # the name is timestamped to the second
    b = faceset_name(42)
    check(a != b, f"two builds for the same person should produce different names, got {a} == {b}")
    check(a.startswith("lora_p42_") and b.startswith("lora_p42_"), f"unexpected name shape: {a}, {b}")


def main(argv):
    pattern = argv[0] if argv else ""
    selected = [t for t in _TESTS if pattern in t.__name__]
    if not selected:
        print(f"No tests match {pattern!r}")
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
