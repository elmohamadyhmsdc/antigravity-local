try:
    from database import JsonDatabase, add_person, get_person_lora_info, set_person_lora_info

    db = JsonDatabase()
    pid = add_person("LoRA Test Person")

    info = get_person_lora_info(pid)
    if info.get("trigger_word") is not None or info.get("lora_path") is not None:
        print(f"Expected empty lora info for a new person, got: {info}")
        exit(1)

    set_person_lora_info(pid, trigger_word="sks7", lora_path="models/loras/lora_test_person.safetensors")
    info = get_person_lora_info(pid)
    if info["trigger_word"] != "sks7":
        print(f"trigger_word not persisted: {info}")
        exit(1)
    if info["lora_path"] != "models/loras/lora_test_person.safetensors":
        print(f"lora_path not persisted: {info}")
        exit(1)

    db.delete_person(pid)
    print("Task 1 verification successful! Person LoRA metadata round-trips correctly.")

    # --- Task 2: person bbox helper ---
    import numpy as np
    from mask_utils import get_person_bbox

    synthetic = np.zeros((480, 640, 3), dtype=np.uint8)
    synthetic[100:400, 150:500] = 200  # a bright rectangular "person" blob

    class _FakeFace:
        bbox = np.array([250, 120, 380, 220], dtype=np.float32)
        det_score = 0.9

    class _FakeFaceApp:
        def get(self, image_bgr):
            return [_FakeFace()]

    bbox = get_person_bbox(synthetic, _FakeFaceApp())
    if bbox is None:
        print("get_person_bbox returned None for a synthetic person image")
        exit(1)
    x1, y1, x2, y2 = bbox
    if not (0 <= x1 < x2 <= 640 and 0 <= y1 < y2 <= 480):
        print(f"get_person_bbox returned an invalid box: {bbox}")
        exit(1)
    print(f"Task 2 verification successful! get_person_bbox -> {bbox}")

    # --- Task 3: extract_face_and_body_crop ---
    import cv2
    from pathlib import Path
    from lora_dataset import extract_face_and_body_crop

    # Build a small fixture image on disk (a plain color image is enough:
    # we're testing the code path and fallback behavior, not detection quality).
    fixture_dir = Path("temp_lora_test")
    fixture_dir.mkdir(exist_ok=True)
    fixture_path = fixture_dir / "fixture.jpg"
    fixture_img = np.full((480, 640, 3), 180, dtype=np.uint8)
    cv2.imwrite(str(fixture_path), fixture_img)

    face_record_image = {
        "source_path": str(fixture_path),
        "bbox_x": 250, "bbox_y": 120, "bbox_width": 130, "bbox_height": 100,
        "quality_score": 0.8,
        "image_path": str(fixture_path),
    }
    result = extract_face_and_body_crop(face_record_image, _FakeFaceApp())
    if result["face_crop"] is None:
        print("extract_face_and_body_crop returned no face_crop for a valid image source")
        exit(1)
    if result["skipped_body"]:
        print("Body crop unexpectedly skipped for an image source")
        exit(1)

    # Video source_path must always fall back to face-only (frame_number isn't persisted).
    face_record_video = {
        "source_path": "some_video.mp4",
        "bbox_x": 250, "bbox_y": 120, "bbox_width": 130, "bbox_height": 100,
        "quality_score": 0.8,
        "image_path": str(fixture_path),
    }
    result_video = extract_face_and_body_crop(face_record_video, _FakeFaceApp())
    if not result_video["skipped_body"]:
        print("Expected skipped_body=True for a video source_path")
        exit(1)
    if result_video["face_crop"] is None:
        print("extract_face_and_body_crop should still fall back to the saved face crop for a video source")
        exit(1)

    import shutil as _shutil
    _shutil.rmtree(fixture_dir, ignore_errors=True)
    print("Task 3 verification successful! extract_face_and_body_crop handles image and video sources.")

    # --- Task 5: captioning ---
    from lora_dataset import build_caption

    # A flat-color image has zero edge variance, i.e. it looks "blurry" to the
    # Laplacian-variance heuristic regardless of quality_score - that's
    # correct blur-detection behavior, so the "not blurry" case needs a
    # synthetic image with real texture/edges instead of a solid fill.
    rng = np.random.default_rng(42)
    textured_image = rng.integers(0, 255, size=(512, 512, 3), dtype=np.uint8)

    caption_good = build_caption(textured_image, trigger_word="sks7", quality_score=0.9)
    if not caption_good.startswith("sks7 person"):
        print(f"Caption must start with the trigger word + class, got: {caption_good!r}")
        exit(1)
    if "low quality" in caption_good or "blurry" in caption_good:
        print(f"High-quality image should not get quality-flag tags: {caption_good!r}")
        exit(1)

    caption_bad = build_caption(np.full((512, 512, 3), 180, dtype=np.uint8),
                                 trigger_word="sks7", quality_score=0.2)
    if "low quality" not in caption_bad:
        print(f"Low-quality image should get a 'low quality' tag: {caption_bad!r}")
        exit(1)

    print("Task 5 verification successful! build_caption applies trigger word and quality flags.")

    # --- Task 6: build_dataset orchestrator ---
    from lora_dataset import build_dataset
    from database import add_face, get_faces_by_person

    pid2 = add_person("Dataset Build Test")
    fixture_dir2 = Path("temp_lora_test2")
    fixture_dir2.mkdir(exist_ok=True)
    created_face_ids = []
    for i in range(3):
        p = fixture_dir2 / f"src_{i}.jpg"
        cv2.imwrite(str(p), np.full((480, 640, 3), 150 + i * 10, dtype=np.uint8))
        fid = add_face(
            embedding=[0.0] * 512,
            source_path=str(p),
            person_id=pid2,
            bbox={"x": 250, "y": 120, "w": 130, "h": 100},
            quality_score=0.9,
            image_path=str(p),
        )
        created_face_ids.append(fid)

    # Each of the 3 faces yields a face crop AND a body crop: get_person_bbox
    # falls back to the face box (+margin) when the selfie segmenter model
    # isn't downloaded, so skipped_body is False and both crops are written -
    # 3 faces x 2 crops = 6 images (verified behavior from Tasks 2 and 3).
    report = build_dataset(pid2, "Dataset Build Test", _FakeFaceApp(), output_root=Path("temp_lora_test2_out"))
    if report["image_count"] != 6:
        print(f"Expected 6 images written (3 faces x face+body crop), got: {report}")
        exit(1)
    dataset_dir = Path(report["dataset_dir"])
    jpgs = list(dataset_dir.glob("*.jpg"))
    txts = list(dataset_dir.glob("*.txt"))
    if len(jpgs) != 6 or len(txts) != 6:
        print(f"Expected 6 jpg + 6 txt files in {dataset_dir}, found {len(jpgs)} jpg / {len(txts)} txt")
        exit(1)

    db.delete_person(pid2)
    # delete_person() only unassigns faces (person_id -> None), it doesn't
    # delete the face records themselves, and database.py has no
    # delete_face(). Remove the fixture faces directly so repeated test runs
    # don't leak orphaned entries into the real data/faces.json.
    for fid in created_face_ids:
        db.faces.pop(fid, None)
    db.save_db()
    _shutil.rmtree(fixture_dir2, ignore_errors=True)
    _shutil.rmtree(Path("temp_lora_test2_out"), ignore_errors=True)
    print("Task 6 verification successful! build_dataset writes the sd-scripts folder layout.")

    # --- Upload-based dataset path (mirrors Reface V2's "Upload New" mode):
    # photos supplied directly, with no pre-existing gallery person/face
    # records required at all. ---
    from lora_dataset import build_dataset_from_uploads, detect_face_record_from_image

    pid3 = add_person("Upload Path Test")
    fixture_dir3 = Path("temp_lora_test3")
    fixture_dir3.mkdir(exist_ok=True)
    upload_paths = []
    for i in range(2):
        p = fixture_dir3 / f"upload_{i}.jpg"
        cv2.imwrite(str(p), np.full((480, 640, 3), 160 + i * 10, dtype=np.uint8))
        upload_paths.append(str(p))
    # One path with no readable image at all, to exercise the "no face
    # detected" skip path without needing a real photo of a real face.
    missing_path = str(fixture_dir3 / "does_not_exist.jpg")
    upload_paths.append(missing_path)

    record = detect_face_record_from_image(upload_paths[0], _FakeFaceApp())
    if record is None or record["source_path"] != upload_paths[0]:
        print(f"detect_face_record_from_image did not return a usable record: {record}")
        exit(1)
    if record["bbox_width"] <= 0 or record["bbox_height"] <= 0:
        print(f"detect_face_record_from_image returned a degenerate bbox: {record}")
        exit(1)

    upload_report = build_dataset_from_uploads(upload_paths, pid3, "Upload Path Test", _FakeFaceApp(),
                                                output_root=Path("temp_lora_test3_out"))
    if upload_report["skipped_no_face_count"] != 1:
        print(f"Expected exactly 1 unreadable upload to be skipped, got: {upload_report}")
        exit(1)
    if upload_report["image_count"] != 4:  # 2 valid uploads x (face + body) crop each
        print(f"Expected 4 images written (2 uploads x face+body crop), got: {upload_report}")
        exit(1)

    db.delete_person(pid3)
    _shutil.rmtree(fixture_dir3, ignore_errors=True)
    _shutil.rmtree(Path("temp_lora_test3_out"), ignore_errors=True)
    print("Upload-path verification successful! build_dataset_from_uploads works without pre-existing gallery faces.")
except ImportError as e:
    print(f"Import failed: {e}")
    exit(1)
except Exception as e:
    print(f"An error occurred: {e}")
    exit(1)
