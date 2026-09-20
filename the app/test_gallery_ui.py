"""
Antigravity Local - Gallery page smoke tests.

Runs dashboard.py headlessly with streamlit's AppTest against a throwaway
library (its own temp data/ folder, fixture JPEGs, no GPU, no models, no
scanning), so UI mistakes - a bad widget argument, a stale key, an exception in
a card - fail here instead of in the browser.

    venv\\Scripts\\python.exe test_gallery_ui.py
    venv\\Scripts\\python.exe test_gallery_ui.py review
"""

import os
import shutil
import sys
import tempfile
import traceback
from pathlib import Path

import numpy as np

for _stream in (sys.stdout, sys.stderr):  # emoji labels vs a cp1252 console
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

APP_DIR = Path(__file__).parent
_TESTS = []
_SANDBOX = None


def test(fn):
    _TESTS.append(fn)
    return fn


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


def build_sandbox() -> Path:
    """A small library: 2 people with faces and bodies, 1 photo, 1 loose face."""
    import cv2
    sys.path.insert(0, str(APP_DIR))
    from database import JsonDatabase
    import person_linking as pl

    root = Path(tempfile.mkdtemp(prefix="gallery_ui_"))
    (root / "extracted_faces").mkdir()
    (root / "extracted_bodies").mkdir()
    (root / "media").mkdir()
    db = JsonDatabase(data_dir=root / "data")

    def crop(path, color, size=(160, 160)):
        cv2.imwrite(str(path), np.full((size[1], size[0], 3), color, dtype=np.uint8))
        return str(path.relative_to(root))

    rng = np.random.default_rng(3)
    photo = root / "media" / "family.jpg"
    cv2.imwrite(str(photo), np.full((600, 800, 3), (70, 90, 120), dtype=np.uint8))
    outfit = pl.appearance_descriptor(np.full((400, 200, 3), (40, 40, 200), dtype=np.uint8),
                                      (10, 10, 190, 390))

    with db.batch():
        media_id = db.upsert_media(str(photo), {"type": "image", "width": 800, "height": 600,
                                                "scan_status": "done", "scan_version": 2,
                                                "size": photo.stat().st_size,
                                                "mtime": int(photo.stat().st_mtime),
                                                "detections": [], "frames_scanned": 1})
        detections = []
        for index, (name, color) in enumerate([("Amira", (90, 70, 200)), ("Youssef", (70, 160, 120))]):
            pid = db.create_person(name)
            base = rng.standard_normal(512).astype(np.float32)
            base /= np.linalg.norm(base)
            for i in range(4):
                vec = base + rng.standard_normal(512).astype(np.float32) * 0.02
                fid = db.add_face(vec / np.linalg.norm(vec), str(photo), person_id=pid,
                                  bbox={"x": 100 + index * 300, "y": 80, "w": 120, "h": 140},
                                  quality_score=0.9 - i * 0.12,
                                  image_path=crop(root / "extracted_faces" / f"f_{pid}_{i}.jpg", color),
                                  extra={"media_id": media_id, "frame_number": None, "timestamp": None,
                                         "quality_version": 2, "det_score": 0.9, "face_px": 120.0})
                if i == 0:
                    db.set_person_avatar(pid, fid)
                    bid = db.add_body({"media_id": media_id, "source_path": str(photo),
                                       "frame_number": None, "bbox": {"x": 60 + index * 300, "y": 40,
                                                                      "w": 200, "h": 520},
                                       "score": 0.93, "face_id": fid, "extent": "full",
                                       "appearance": [float(v) for v in outfit],
                                       "crop_path": crop(root / "extracted_bodies" / f"b_{pid}.jpg",
                                                         color, (160, 320))})
                    detections.append([None, None, "f", fid, 100 + index * 300, 80, 120, 140])
                    detections.append([None, None, "b", bid, 60 + index * 300, 40, 200, 520])
        # a body nobody claimed, and a loose face for the review queue
        db.add_body({"media_id": media_id, "source_path": str(photo), "frame_number": None,
                     "bbox": {"x": 600, "y": 40, "w": 180, "h": 520}, "score": 0.8, "extent": "upper",
                     "appearance": [float(v) for v in outfit],
                     "crop_path": crop(root / "extracted_bodies" / "b_loose.jpg", (120, 120, 120),
                                       (160, 320))})
        stray = rng.standard_normal(512).astype(np.float32)
        db.add_face(stray / np.linalg.norm(stray), str(photo), quality_score=0.7,
                    image_path=crop(root / "extracted_faces" / "f_loose.jpg", (150, 150, 150)),
                    extra={"media_id": media_id, "quality_version": 2})
        db.upsert_media(str(photo), {"detections": detections})
    return root


def sandbox() -> Path:
    global _SANDBOX
    if _SANDBOX is None:
        _SANDBOX = build_sandbox()
        os.chdir(_SANDBOX)
    return _SANDBOX


def run_app(query=None, session=None, timeout=120):
    """Run dashboard.py headlessly on the Gallery page."""
    from streamlit.testing.v1 import AppTest
    sandbox()
    app = AppTest.from_file(str(APP_DIR / "dashboard.py"), default_timeout=timeout)
    app.query_params["page"] = "gallery"
    for key, value in (query or {}).items():
        app.query_params[key] = value
    app.session_state["active_nav_page"] = "\U0001f465 Gallery"
    app.session_state["sources_loaded"] = True      # don't read the real data_sources.json
    app.session_state["data_sources"] = []
    for key, value in (session or {}).items():
        app.session_state[key] = value
    app.run()
    if app.exception:
        raise AssertionError("\n".join(str(e.value) for e in app.exception))
    return app


def text_of(app) -> str:
    parts = [m.value for m in app.markdown] + [c.value for c in app.caption]
    parts += [b.label for b in app.button] + [getattr(i, "value", "") for i in app.info]
    parts += [t.label for t in app.tabs] if hasattr(app, "tabs") else []
    return "\n".join(str(p) for p in parts)


def click(app, label_contains: str, index: int = 0):
    matches = [b for b in app.button if label_contains.lower() in b.label.lower()]
    check(len(matches) > index, f"no button matching {label_contains!r}; "
                                f"have: {[b.label for b in app.button][:25]}")
    matches[index].click().run()
    if app.exception:
        raise AssertionError("\n".join(str(e.value) for e in app.exception))
    return app


# ---------------------------------------------------------------------------

@test
def test_people_view_lists_everyone():
    app = run_app()
    body = text_of(app)
    check("Gallery" in body, "the page title should render")
    check("Amira" in body and "Youssef" in body, f"both people should be listed:\n{body[:600]}")
    check("Scan library" in body, "the scan action should be offered")
    switcher = [c for c in app.get("button_group") if c.label == "View"]
    check(switcher and switcher[0].value == "People", f"the People view should be showing: {switcher}")
    check(any("(2)" in v for v in switcher[0].formatted_values),
          f"the switcher should show how many people there are: {switcher[0].formatted_values}")


@test
def test_person_detail_opens_with_tabs_and_actions():
    app = run_app(query={"view": "people"})
    click(app, "Open")
    body = text_of(app)
    check("All people" in body, "there should be a way back")
    check("Train LoRA" in body and "Use in Reface" in body, f"cross-page actions missing:\n{body[:600]}")
    check("faces" in body.lower() and "bodies" in body.lower(), "counts should be shown")
    check(any("Suggestions" in t for t in [tab.label for tab in app.tabs]),
          f"tabs missing: {[t.label for t in app.tabs]}")


@test
def test_review_view_offers_decisions():
    app = run_app(query={"view": "unassigned"})
    body = text_of(app)
    check("Review" in body, "the review view should render")
    check("Group automatically" in body or "Nothing to review" in body,
          f"review controls missing:\n{body[:600]}")


@test
def test_media_view_shows_the_photo_and_people_in_it():
    app = run_app(query={"view": "media"})
    body = text_of(app)
    check("family.jpg" in body, f"the scanned photo should be listed:\n{body[:600]}")
    check("Amira" in body or "Youssef" in body, "the people in the photo should be named")
    check(any("Inspect" in b.label for b in app.button), "each card should be inspectable")


@test
def test_insights_view_renders_charts():
    app = run_app(query={"view": "insights"})
    body = text_of(app)
    check("Face quality" in body, f"quality chart missing:\n{body[:600]}")
    check("Biggest people" in body, "top people chart missing")
    check(any("sorted" in str(m.label).lower() for m in app.metric), "coverage metric missing")


@test
def test_person_faces_can_be_reassigned():
    from database import JsonDatabase

    app = run_app()
    click(app, "Open")                       # first person
    click(app, "Not this person")            # via the per-face popover
    db = JsonDatabase(data_dir=sandbox() / "data")
    loose = [f for f in db.faces.values() if f.get("person_id") is None]
    check(any(f.get("rejected_person_ids") for f in loose),
          "rejecting a face should unassign it and remember the correction")


@test
def test_view_switcher_offers_every_view():
    app = run_app()
    controls = [c for c in app.get("button_group") if c.label == "View"]
    check(controls, "the view switcher should render")
    options = [str(o) for o in controls[0].options]
    check([o.split(" (")[0] for o in options] == ["People", "Review", "Media", "Insights"],
          f"unexpected views: {options}")


@test
def test_strictness_can_be_changed_from_review_without_key_clashes():
    app = run_app(query={"view": "unassigned"})
    controls = [c for c in app.get("button_group") if c.key == "gal_strictness_review"]
    check(controls, "the review view should offer the grouping strictness")
    controls[0].set_value("strict").run()
    check(not app.exception, f"changing strictness raised: {app.exception}")
    shared = app.session_state["gal_strictness"]
    check(shared == "strict", f"the shared value should follow the control, got {shared!r}")


def main(argv):
    pattern = argv[0] if argv else ""
    selected = [t for t in _TESTS if pattern in t.__name__]
    if not selected:
        print("No test matches. Known: " + ", ".join(t.__name__ for t in _TESTS))
        return 1
    failed = 0
    try:
        for t in selected:
            try:
                t()
                print(f"[PASS] {t.__name__}")
            except Exception as e:
                failed += 1
                print(f"[FAIL] {t.__name__}: {e}")
                traceback.print_exc()
    finally:
        os.chdir(APP_DIR)
        if _SANDBOX:
            shutil.rmtree(_SANDBOX, ignore_errors=True)
    print(f"\n{len(selected) - failed}/{len(selected)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
