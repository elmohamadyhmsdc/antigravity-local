"""
analysis.analyze_frame - the pure frame-analysis core shared by the gallery scanner and the
mobile API. CPU only, no models: faces and bodies are scripted fakes.

    venv\\Scripts\\python.exe test_analysis.py
"""

import sys
import traceback

import numpy as np

_TESTS = []


def test(fn):
    _TESTS.append(fn)
    return fn


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


def _img(w=640, h=480):
    return np.random.default_rng(0).integers(0, 255, (h, w, 3), dtype=np.uint8)


@test
def test_analyze_frame_returns_faces_quality_gate_bodies_and_pairs():
    from analysis import AnalyzeOptions, analyze_frame
    from mobile_api.testing import FakeBody, FakeFace, unit
    import face_quality

    good = FakeFace((60, 50, 200, 230), unit(1))
    weak = FakeFace((400, 60, 424, 90), unit(2), det_score=0.4)  # fails the detector gate
    body = FakeBody((20, 30, 260, 460), (130, 90))

    class Bodies:
        available = True

        def analyze(self, img, score_thr=0.5):
            return [body]

    img = _img()
    result = analyze_frame(None, Bodies(), img, AnalyzeOptions(),
                           detect=lambda im: [good, weak],
                           assess=lambda im, f: face_quality.assess(f, None))
    check(result.passes_gate == [True, False], f"gate: {result.passes_gate}")
    check(len(result.quality) == 2 and result.quality[0]["quality_version"] == face_quality.QUALITY_VERSION,
          "quality v2 must be attached to every face")
    check(result.pairs and result.pairs[0][0] == 0 and result.pairs[0][1] == 0, f"pairs: {result.pairs}")
    check(result.body_of_face == {0: 0} and result.face_of_body == {0: 0}, "pair lookups")
    check(len(result.appearances) == 1 and result.appearances[0] is not None and len(result.appearances[0]) == 80,
          "each body needs its 80-float outfit descriptor")
    check((result.image_w, result.image_h) == (640, 480), "image size")
    check({"detect", "quality", "body"} <= set(result.timings_ms), f"timings: {result.timings_ms}")


@test
def test_analyze_frame_preserves_human_bodies_when_character_detection_is_enabled():
    from analysis import AnalyzeOptions, analyze_frame
    from mobile_api.testing import FakeBody, FakeFace, unit
    import face_quality

    good = FakeFace((60, 50, 200, 230), unit(1))
    body = FakeBody((20, 30, 260, 460), (130, 90))

    class Bodies:
        available = True

        def analyze(self, img, score_thr=0.5):
            return [body]

    img = _img()
    opts = AnalyzeOptions(detect_bodies=True, detect_characters=True)
    result = analyze_frame(None, Bodies(), img, opts,
                           detect=lambda im: [good],
                           assess=lambda im, f: face_quality.assess(f, None))
    check(len(result.faces) == 1, f"human face preserved: {len(result.faces)}")
    check(len(result.bodies) == 1, f"human body preserved with character scan on: {len(result.bodies)}")
    check(len(result.pairs) == 1, f"pair created: {len(result.pairs)}")
    check(len(result.characters) == 0, f"no false character: {len(result.characters)}")


@test
def test_analyze_frame_skips_bodies_when_off_or_unavailable():
    from analysis import AnalyzeOptions, analyze_frame
    from mobile_api.testing import FakeFace, unit
    import face_quality

    called = []

    class Bodies:
        available = True

        def analyze(self, img, score_thr=0.5):
            called.append(score_thr)
            return []

    class Broken:
        available = False

        def analyze(self, img, score_thr=0.5):
            raise AssertionError("must not be called when unavailable")

    face = FakeFace((60, 50, 200, 230), unit(1))
    kw = dict(detect=lambda im: [face], assess=lambda im, f: face_quality.assess(f, None))
    analyze_frame(None, Bodies(), _img(), AnalyzeOptions(detect_bodies=False), **kw)
    check(not called, "detect_bodies=False must not run the body model")
    r = analyze_frame(None, Broken(), _img(), AnalyzeOptions(), **kw)
    check(r.bodies == [] and r.pairs == [], "an unavailable body model means no bodies, not a crash")
    r = analyze_frame(None, None, _img(), AnalyzeOptions(), **kw)
    check(r.bodies == [], "no body analyzer at all")
    analyze_frame(None, Bodies(), _img(), AnalyzeOptions(body_score=0.7), **kw)
    check(called == [0.7], f"body_score must reach the detector: {called}")


@test
def test_quality_gate_follows_the_requested_minimum():
    from analysis import AnalyzeOptions, analyze_frame
    from mobile_api.testing import FakeFace, unit
    import face_quality

    face = FakeFace((60, 50, 200, 230), unit(1))
    kw = dict(detect=lambda im: [face], assess=lambda im, f: face_quality.assess(f, None))
    lenient = analyze_frame(None, None, _img(), AnalyzeOptions(min_face_quality=0.1), **kw)
    strict = analyze_frame(None, None, _img(), AnalyzeOptions(min_face_quality=0.99), **kw)
    check(lenient.passes_gate == [True] and strict.passes_gate == [False], "min_face_quality is the gate")


@test
def test_crops_pad_and_clamp_like_the_scanner_does():
    from analysis import body_crop, face_crop
    from mobile_api.testing import FakeBody, FakeFace, unit

    img = _img(640, 480)
    face = FakeFace((100, 100, 200, 200), unit(1))
    c = face_crop(img, face)  # 100px box + 20 % pad each side
    check(c.shape[:2] == (140, 140), f"face crop with 20% pad: {c.shape}")
    edge = FakeFace((0, 0, 50, 50), unit(1))
    check(face_crop(img, edge).shape[:2] == (60, 60), "crop is clamped at the image border (50px + 10px pad on one side)")
    tall = FakeBody((10, 0, 110, 470), (60, 20))
    check(body_crop(img, tall.bbox, max_height=100).shape[0] <= 100, "body crops are capped in height")


@test
def test_library_scanner_still_routes_through_analysis():
    """LibraryScanner keeps detect_faces/assess_face as instance-overridable hooks (test_gallery stubs them)."""
    import analysis
    import library_scanner

    check(library_scanner.LibraryScanner.det_sizes(_img(800, 600)) == analysis.det_sizes(_img(800, 600)),
          "det_sizes must be the shared implementation")
    check(library_scanner._FileState._face_crop is analysis.face_crop, "face crops must be shared")
    check(library_scanner._FileState._body_crop is analysis.body_crop, "body crops must be shared")


def main(argv):
    pattern = argv[0] if argv else ""
    selected = [t for t in _TESTS if pattern in t.__name__]
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


@test
def test_empty_preview_detection_retries_finer_grid_and_keeps_original_coordinates():
    from types import SimpleNamespace
    from unittest.mock import patch
    import analysis

    image = _img(1280, 720)
    calls = []
    seen_images = []
    def detect(img, input_size, max_num):
        check(img is image and max_num == 0, "the original pixels are reused")
        calls.append(input_size)
        if input_size == [(1280, 1280)]:
            return np.array([[10, 20, 40, 60, .9]], dtype=np.float32), None
        return np.empty((0, 5)), None
    def recognize(img, face):
        seen_images.append(img)
        face.embedding = np.ones(512, dtype=np.float32)
    app = SimpleNamespace(det_model=SimpleNamespace(detect=detect),
                          models={"recognition": SimpleNamespace(get=recognize)})
    with patch.dict(sys.modules, {"insightface.app.common": SimpleNamespace(Face=lambda **kw: SimpleNamespace(**kw))}):
        faces = analysis.detect_faces(app, image)
    check(calls == [[(128, 128), (640, 640)], [(1280, 1280)]], "one bounded high-resolution retry")
    check(len(faces) == 1 and list(faces[0].bbox) == [10, 20, 40, 60], "boxes stay in original frame coordinates")
    check(len(seen_images) == 1 and seen_images[0] is image, "recognition still receives original frame pixels")


@test
def test_finer_grid_retry_is_skipped_for_found_faces_and_already_detailed_frames():
    from types import SimpleNamespace
    from unittest.mock import patch
    import analysis

    for width, found in [(1280, True), (1920, False), (1280, False)]:
        calls = []
        def detect(img, input_size, max_num):
            calls.append(input_size)
            return (np.array([[1, 2, 30, 40, .9]]) if found else np.empty((0, 5))), None
        app = SimpleNamespace(det_model=SimpleNamespace(detect=detect), models={})
        with patch.dict(sys.modules, {"insightface.app.common": SimpleNamespace(Face=lambda **kw: SimpleNamespace(**kw))}):
            faces = analysis.detect_faces(app, _img(width, 720))
        check(len(calls) == (2 if width == 1280 and not found else 1), "no redundant detector work or retry loop")
        check(len(faces) == int(found), "an empty frame stays empty; no fabricated detections")


@test
def test_analyze_frame_leaves_outline_lists_empty():
    from analysis import AnalyzeOptions, analyze_frame
    from mobile_api.testing import FakeFace, unit
    import face_quality

    face = FakeFace((60, 50, 200, 230), unit(1))
    r = analyze_frame(None, None, _img(), AnalyzeOptions(outlines=True),
                      detect=lambda im: [face],
                      assess=lambda im, f: face_quality.assess(f, None))
    check(r.face_outlines == [], "analyze_frame leaves face_outlines empty")
    check(r.body_outlines == [], "analyze_frame leaves body_outlines empty")


def _real_embedding(seed):
    """A face embedding with no component along the drawn-face direction (a photographed face)."""
    import drawn_faces
    v = np.random.default_rng(seed).normal(size=512).astype(np.float32)
    return v - (v @ drawn_faces._direction) * drawn_faces._direction


@test
def test_a_big_drawn_face_does_not_turn_the_real_people_into_crowd_background():
    """2026-11-11: two people (100 px faces) in front of a cartoon poster (400 px drawn face). The crowd rule
    measured the people against the drawn face, called both "background" and stored neither."""
    from analysis import AnalyzeOptions, analyze_frame
    from mobile_api.testing import FakeFace
    import drawn_faces
    import face_quality

    people = [FakeFace((100, 300, 200, 400), _real_embedding(1)), FakeFace((300, 300, 400, 400), _real_embedding(2))]
    poster = FakeFace((900, 100, 1300, 500), drawn_faces._direction)
    img = _img(1400, 900)
    alone = analyze_frame(None, None, img, AnalyzeOptions(detect_bodies=False), detect=lambda im: list(people),
                          assess=lambda im, f: face_quality.assess(f, None))
    check(alone.passes_gate == [True, True], f"the two people alone pass: {alone.passes_gate}")
    r = analyze_frame(None, None, img, AnalyzeOptions(detect_bodies=False), detect=lambda im: people + [poster],
                      assess=lambda im, f: face_quality.assess(f, None))
    check(len(r.faces) == 2, f"the drawn face is dropped, the people stay: {len(r.faces)} faces")
    check(r.passes_gate == [True, True], f"the people are still stored next to a poster: {r.passes_gate}")


@test
def test_a_real_persons_body_survives_an_anime_print_when_characters_are_detected():
    """2026-11-11: with character detection on (the phone's cartoon setting), a body that contained the centre
    of any drawn face was a character's body - so a real person in an anime-print shirt lost their body (and
    their face lost its body link), while the same photo without character detection kept it."""
    from types import SimpleNamespace
    import analysis
    import drawn_faces
    from analysis import AnalyzeOptions, analyze_frame
    from mobile_api.testing import FakeBody

    saved = analysis._anime_detector, analysis._ccip_embedder
    analysis._anime_detector = SimpleNamespace(detect=lambda img, score_thresh: [])
    analysis._ccip_embedder = SimpleNamespace(embed_crop=lambda crop: np.eye(768, dtype=np.float32)[1])
    try:
        person = FakeBody((0, 0, 128, 256), (64, 40))

        class Bodies:
            available = True

            def analyze(self, img, score_thr=0.5):
                return [person]

        real = SimpleNamespace(bbox=np.array([40, 10, 88, 72], np.float32), det_score=.9, kps=None,
                               embedding=_real_embedding(3))
        shirt = SimpleNamespace(bbox=np.array([39, 110, 89, 160], np.float32), det_score=.9, kps=None,
                                embedding=(drawn_faces._direction * 20).astype(np.float32))   # 50 px drawn print
        img = _img(128, 256)
        for faceless in (False, True):
            r = analyze_frame(None, Bodies(), img,
                              AnalyzeOptions(detect_bodies=True, detect_characters=True, faceless_characters=faceless),
                              detect=lambda im: [real, shirt], assess=lambda im, f: {"quality_score": .7})
            check(len(r.faces) == 1 and len(r.bodies) == 1 and [(fi, bi) for fi, bi, _ in r.pairs] == [(0, 0)],
                  f"faceless_characters={faceless}: the person keeps face + body + link "
                  f"(faces={len(r.faces)}, bodies={len(r.bodies)}, pairs={r.pairs})")
            check(all(c.body_bbox is None for c in r.characters), "no character takes the person's body")
    finally:
        analysis._anime_detector, analysis._ccip_embedder = saved


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
