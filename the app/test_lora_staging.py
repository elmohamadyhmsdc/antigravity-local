"""lora_staging.py: the Character LoRA page's on-disk staging for uploads and folder imports. No GPU, no models."""
import os
import tempfile
from pathlib import Path

try:
    from lora_staging import (FINGERPRINT_BYTES, clear_staged, fingerprint_data, fingerprint_file, import_folder,
                              list_staged, move_staged, stage_bytes, staging_dir, summarize_staging)

    def fail(message):
        print(message)
        exit(1)

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)

        # --- fingerprints agree between bytes in memory and the same bytes on disk ---
        for size in (0, 10, FINGERPRINT_BYTES, FINGERPRINT_BYTES + 5, 3 * FINGERPRINT_BYTES + 7):
            data = os.urandom(size)
            (tmp / "fp.bin").write_bytes(data)
            if fingerprint_data(data) != fingerprint_file(tmp / "fp.bin"):
                fail(f"fingerprint_data and fingerprint_file disagree for a {size}-byte file")
        big = bytearray(os.urandom(3 * FINGERPRINT_BYTES))
        tweaked = bytearray(big)
        tweaked[-1] ^= 0xFF
        if fingerprint_data(bytes(big)) == fingerprint_data(bytes(tweaked)):
            fail("A change in the last MiB should change the fingerprint")

        # --- stage_bytes: dedupe, name clashes, non-ASCII names, unsupported types ---
        stage = tmp / "stage"
        known = set()
        outcomes = [
            stage_bytes(stage, "IMG_0001.JPG", b"photo one", known),
            stage_bytes(stage, "copy of it.jpg", b"photo one", known),      # same content, other name
            stage_bytes(stage, "IMG_0001.jpg", b"photo two", known),        # other content, same name
            stage_bytes(stage, "صورة.png", b"arabic name", known),
            stage_bytes(stage, "clip.MP4", b"video bytes", known),
            stage_bytes(stage, "notes.txt", b"not media", known),
            stage_bytes(stage, "photo.heic", b"heic", known),
        ]
        if outcomes != ["added", "duplicate", "added", "added", "added", "unsupported", "unsupported"]:
            fail(f"Unexpected stage_bytes outcomes: {outcomes}")
        if stage_bytes(stage, "again.jpg", b"photo two") != "duplicate":  # `known` rebuilt from the folder itself
            fail("stage_bytes should find duplicates already on disk when no `known` set is passed")
        staged = list_staged(stage)
        names = sorted(p.name for p in staged["images"])
        if len(staged["images"]) != 3 or len(staged["videos"]) != 1 or "IMG_0001.jpg" not in names or "IMG_0001_2.jpg" not in names:
            fail(f"Unexpected staged files: {staged}")
        if not any(n.startswith("media_") and n.isascii() for n in names):
            fail(f"A non-ASCII file name should be replaced with an ASCII one (OpenCV can't open it): {names}")
        (stage / "half.jpg.part").write_bytes(b"partial")
        (stage / "_frames").mkdir()
        (stage / "_frames" / "frame_00.jpg").write_bytes(b"frame")
        if len(list_staged(stage)["images"]) != 3:
            fail("list_staged should ignore .part files and subfolders")

        # --- import_folder: recursion, dedupe on re-run, unsupported count, skipping the staging folder ---
        source = tmp / "phone"
        (source / "DCIM" / "Camera").mkdir(parents=True)
        (source / "WhatsApp").mkdir()
        (source / "a.jpg").write_bytes(b"A")
        (source / "DCIM" / "Camera" / "b.jpg").write_bytes(b"B")
        (source / "DCIM" / "Camera" / "clip.mp4").write_bytes(b"CLIP" * 1000)
        (source / "WhatsApp" / "a.jpg").write_bytes(b"A")          # same photo twice
        (source / "WhatsApp" / "c.heic").write_bytes(b"C")
        (source / "WhatsApp" / "thumbs.db").write_bytes(b"x")
        target = source / "staged_here"                            # staging folder inside the source folder
        target.mkdir()
        (target / "old.jpg").write_bytes(b"OLD")

        calls = []
        result = import_folder(source, target, recursive=True, progress=lambda f, text: calls.append(f))
        if (result["found"], result["added"], result["duplicate"], result["unsupported"], result["failed"]) != (4, 3, 1, 1, 0):
            fail(f"Unexpected recursive import result: {result}")
        if not calls or calls[-1] != 1.0 or any(not 0 <= f <= 1 for f in calls):
            fail(f"progress should get fractions in [0, 1] ending at 1.0: {calls}")
        imported = list_staged(target)
        if sorted(p.name for p in imported["images"]) != ["a.jpg", "b.jpg", "old.jpg"] or len(imported["videos"]) != 1:
            fail(f"Unexpected files after import: {imported}")
        if (target / "b.jpg").read_bytes() != b"B":
            fail("Imported file content should match the original")

        again = import_folder(source, target)
        if again["added"] != 0 or again["duplicate"] != 4:
            fail(f"Re-running an import should only skip duplicates: {again}")
        (source / "DCIM" / "d.png").write_bytes(b"D")
        shallow = import_folder(source, target, recursive=False)
        if shallow["found"] != 1 or shallow["added"] != 0:
            fail(f"recursive=False should only look at the top folder: {shallow}")
        if import_folder(source, target)["added"] != 1:
            fail("A new file in a subfolder should be picked up by the next recursive import")

        try:
            import_folder(tmp / "missing", target)
            fail("import_folder should raise for a folder that doesn't exist")
        except NotADirectoryError:
            pass

        # --- clear_staged leaves originals alone (hard links) ---
        removed = clear_staged(target)
        if removed != 5 or list_staged(target)["images"] or not (source / "DCIM" / "Camera" / "b.jpg").exists():
            fail(f"clear_staged should remove the 5 staged files and keep the originals (removed {removed})")

        # --- move_staged: files staged before a name was typed ---
        early, named = tmp / "unnamed", tmp / "named"
        stage_bytes(early, "x.jpg", b"X")
        stage_bytes(early, "y.jpg", b"Y")
        stage_bytes(named, "y.jpg", b"Y")
        moved = move_staged(early, named)
        if moved != {"added": 1, "duplicate": 1} or list_staged(early)["images"] or len(list_staged(named)["images"]) != 2:
            fail(f"move_staged should move new files and drop duplicates: {moved}")

    if staging_dir("") != staging_dir("   ") or staging_dir("").name != "unnamed":
        fail(f"An empty name should stage into 'unnamed': {staging_dir('')}")
    if staging_dir("Aya Selim").name != "aya_selim":
        fail(f"staging_dir should use the dataset slug: {staging_dir('Aya Selim')}")
    line = summarize_staging({"added": 3, "duplicate": 1, "unsupported": 2, "failed": 1})
    if not all(s in line for s in ("3 new", "1 already staged", "2 in formats", "1 failed")):
        fail(f"Unexpected summary: {line}")

    print("lora_staging verification successful! Staging dedupes, never overwrites, imports folders and survives re-runs.")
except ImportError as e:
    print(f"Import failed: {e}")
    exit(1)
