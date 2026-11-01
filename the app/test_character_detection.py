"""CPU regressions with synthetic drawings; no models, network or real library."""
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import cv2
import numpy as np

from analysis import AnalyzeOptions, analyze_frame
from character_detection import DIM, MODEL_ID, describe, detect_characters, similarity


def drawing(hair=(0, 220, 255), shirt=(230, 80, 20), background=245):
    img = np.full((256, 128, 3), background, np.uint8)
    cv2.rectangle(img, (40, 10), (88, 72), hair, -1)
    cv2.rectangle(img, (24, 74), (104, 164), shirt, -1)
    cv2.rectangle(img, (36, 166), (92, 244), (30, 35, 45), -1)
    return img


def body(box=(0, 0, 128, 256)):
    return SimpleNamespace(bbox=np.array(box, np.float32), score=.95, kpts=None, kpt_scores=None)


class CharacterTests(unittest.TestCase):
    def test_descriptor_is_finite_versioned_and_scale_stable(self):
        img = drawing()
        descriptor = describe(img, [0, 0, 128, 256])
        self.assertEqual(descriptor.shape, (DIM,))
        self.assertTrue(np.isfinite(descriptor).all())
        self.assertTrue(((descriptor >= 0) & (descriptor <= 1)).all())
        bigger = cv2.resize(img, (256, 512), interpolation=cv2.INTER_NEAREST)
        self.assertGreater(similarity(descriptor, describe(bigger, [0, 0, 256, 512])), .99)

    def test_background_shift_does_not_change_identity(self):
        self.assertGreater(similarity(describe(drawing(), [0, 0, 128, 256]),
                                      describe(drawing(background=220), [0, 0, 128, 256])), .98)

    def test_same_uniform_different_hair_does_not_auto_match(self):
        a = describe(drawing(), [0, 0, 128, 256])
        b = describe(drawing(hair=(220, 20, 180)), [0, 0, 128, 256])
        self.assertLess(similarity(a, b), .93)

    def test_same_hair_different_clothes_does_not_auto_match(self):
        a = describe(drawing(), [0, 0, 128, 256])
        b = describe(drawing(shirt=(40, 240, 80)), [0, 0, 128, 256])
        self.assertLess(similarity(a, b), .93)

    def test_invalid_boxes_and_uniform_background_are_not_characters(self):
        for box in ([0, 0, 1, 1], [-40, -40, -10, -10], [100, 200, 20, 30], [0, 0, np.nan, 100]):
            self.assertIsNone(describe(drawing(), box))
        self.assertIsNone(describe(np.full((256, 128, 3), 245, np.uint8), [0, 0, 128, 256]))

    def test_missing_regions_and_other_model_dimensions_cannot_match(self):
        a = describe(drawing(), [0, 0, 128, 256])
        b = a.copy()
        b[:32] = 0
        self.assertEqual(similarity(a, b), 0)
        self.assertEqual(similarity(a, np.ones(512)), 0)
        b[0] = np.nan
        self.assertEqual(similarity(a, b), 0)

    def test_character_mode_without_faces_ignores_body_toggle(self):
        class Bodies:
            available = True
            def analyze(self, img, score_thr):
                return [body()]
        result = analyze_frame(None, Bodies(), drawing(),
                               AnalyzeOptions(detect_bodies=False, detect_characters=True), detect=lambda _: [])
        self.assertEqual((result.faces, result.bodies, result.pairs), ([], [], []))
        self.assertEqual(len(result.characters), 1)
        self.assertEqual(result.characters[0].model_id, MODEL_ID)

    def test_a_clear_real_face_is_a_person_not_a_character(self):
        """Real photos in an anime album: the body around a good face is not a character."""
        class Bodies:
            available = True
            def analyze(self, img, score_thr):
                return [body((0, 0, 128, 256)), body((20, 0, 100, 120))]
        face = SimpleNamespace(bbox=np.array([40, 10, 88, 72], np.float32), det_score=.9, kps=None,
                               embedding=np.ones(512, np.float32))
        def options():
            return AnalyzeOptions(detect_bodies=False, detect_characters=True)
        real = analyze_frame(None, Bodies(), drawing(), options(), detect=lambda _: [face],
                             assess=lambda img, f: {"quality_score": .7})
        self.assertEqual(len(real.faces), 1)
        self.assertEqual(real.passes_gate, [True])
        self.assertEqual(real.bodies, [])
        # Both boxes contain the face centre (64, 41), so neither is a character.
        self.assertEqual(real.characters, [])
        drawn = analyze_frame(None, Bodies(), drawing(), options(), detect=lambda _: [face],
                              assess=lambda img, f: {"quality_score": .45})
        self.assertEqual(drawn.faces, [])
        self.assertEqual(len(drawn.characters), 2)

    def test_real_person_with_detect_bodies_and_characters_preserves_body(self):
        class Bodies:
            available = True
            def analyze(self, img, score_thr):
                return [body((0, 0, 128, 256))]
        face = SimpleNamespace(bbox=np.array([40, 10, 88, 72], np.float32), det_score=.9, kps=None,
                               embedding=np.ones(512, np.float32))
        opts = AnalyzeOptions(detect_bodies=True, detect_characters=True)
        res = analyze_frame(None, Bodies(), drawing(), opts, detect=lambda _: [face],
                            assess=lambda img, f: {"quality_score": .7})
        self.assertEqual(len(res.faces), 1)
        self.assertEqual(len(res.bodies), 1)
        self.assertEqual(len(res.pairs), 1)
        self.assertEqual(res.characters, [])

    def test_missing_body_model_is_an_error_not_an_empty_success(self):
        with self.assertRaisesRegex(RuntimeError, 'HumanArt'):
            analyze_frame(None, None, drawing(), AnalyzeOptions(detect_characters=True))

    def test_scanner_stores_face_free_characters_and_skips_unchanged_sources(self):
        from database import JsonDatabase
        from library_scanner import LibraryScanner, ScanOptions
        class Bodies:
            available = True
            def analyze(self, img, score_thr):
                return [body()]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            db = JsonDatabase(root / 'library')
            for name in ('one.png', 'two.png'):
                cv2.imwrite(str(root / name), drawing())
            scanner = LibraryScanner(db, ScanOptions(detect_characters=True, detect_bodies=False),
                                     body=Bodies(), body_crop_dir=root / 'crops' / 'bodies')
            scanner.detect_faces = lambda img: []  # a drawing: no real face
            paths = [root / 'one.png', root / 'two.png']
            summary = scanner.scan_paths(paths)
            self.assertEqual(summary.characters_new, 2)
            self.assertEqual(len(db.character_identities), 1)
            self.assertFalse(db.faces)
            self.assertEqual(scanner.scan_paths(paths).files_skipped, 2)
            self.assertTrue(all(m['detections'][0][2] == 'c' for m in db.media.values()))

    def test_authenticated_image_route_passes_character_mode_without_face_model(self):
        from fastapi.testclient import TestClient
        from mobile_api.app import create_app
        from mobile_api.testing import make_test_context
        class Bodies:
            available = True
            def analyze(self, img, score_thr):
                return [body()]
        class Engine:
            model_id = 'buffalo_l@1'
            def analyze(self, img, options):
                return analyze_frame(None, Bodies(), img, options)
            def unload(self):
                pass
        with tempfile.TemporaryDirectory() as tmp:
            ctx = make_test_context(Path(tmp), engines=Engine())
            device = ctx.auth.add_device('Synthetic phone')
            with TestClient(create_app(ctx)) as client:
                ok, jpeg = cv2.imencode('.jpg', drawing())
                self.assertTrue(ok)
                response = client.post('/v1/analyze/image',
                    headers={'Authorization': 'Bearer ' + device['token']},
                    files={'image': ('synthetic.jpg', jpeg.tobytes(), 'image/jpeg')},
                    data={'options': json.dumps(dict(detect_characters=True, detect_bodies=False,
                                                     model_id='different-human-model'))})
                self.assertEqual(response.status_code, 200, response.text)
                result = response.json()
                self.assertEqual(result['faces'], [])
                self.assertEqual(len(result['characters']), 1)

    def test_anime_face_detector_in_analyze_frame(self):
        class Bodies:
            available = True
            def analyze(self, img, score_thr):
                return []
        img = drawing()
        options = AnalyzeOptions(detect_characters=True, detect_bodies=False)
        result = analyze_frame(None, Bodies(), img, options)
        self.assertIsInstance(result.characters, list)

    def test_worker_and_wire_roundtrip_keep_character_descriptor_and_no_faces(self):
        from analysis import FrameAnalysis
        from mobile_api.scan_worker import encode_result, decode_result
        from mobile_api.schemas import AnalyzeRequestOptions, analysis_to_response, parse_analyze_options
        result = FrameAnalysis([], [], [], [], [], [], image_w=128, image_h=256,
                               characters=detect_characters(drawing(), [body()]))
        decoded = decode_result(json.loads(json.dumps(encode_result(result))))
        wire = analysis_to_response(decoded, drawing(), AnalyzeRequestOptions(detect_characters=True))
        self.assertEqual(len(wire['characters'][0]['descriptor']), DIM)
        self.assertTrue(wire['characters'][0]['crop_jpeg'])
        self.assertEqual(wire['faces'], [])
        opts = parse_analyze_options('{"detect_characters":true,"detect_bodies":false}')
        self.assertTrue(opts.detect_characters)
        self.assertFalse(opts.detect_bodies)
        with self.assertRaises(Exception):
            parse_analyze_options('{"detect_characters":1}')

    def test_character_has_face_and_body_like_a_person_through_worker_and_wire(self):
        import base64
        from analysis import FrameAnalysis
        from character_detection import attach_identity
        from mobile_api.scan_worker import encode_result, decode_result
        from mobile_api.schemas import AnalyzeRequestOptions, analysis_to_response

        class Embedder:
            def embed_crop(self, crop):
                v = np.zeros(768, np.float32)
                v[0] = 1.0
                return v

        img = drawing()
        face = {'bbox': [40, 10, 88, 72], 'score': .9}
        with_both, face_only = detect_characters(img, [body()], anime_faces=[face]), \
            detect_characters(img, [], anime_faces=[face])
        self.assertEqual(len(with_both), 1)  # the body is used by its face, not a second figure
        c = with_both[0]
        self.assertEqual(list(c.face_bbox), [40, 10, 88, 72])
        self.assertEqual(list(c.body_bbox), [0, 0, 128, 256])
        self.assertIsNone(face_only[0].body_bbox)
        attach_identity(img, [c, face_only[0]], Embedder())
        self.assertEqual(c.face_embedding.shape, (768,))
        self.assertIsNotNone(c.body_appearance)
        self.assertIsNone(face_only[0].body_appearance)

        result = FrameAnalysis([], [], [], [], [], [], image_w=128, image_h=256, characters=[c, face_only[0]])
        decoded = decode_result(json.loads(json.dumps(encode_result(result))))
        wire = analysis_to_response(decoded, img, AnalyzeRequestOptions(detect_characters=True))
        first, second = wire['characters']
        raw = base64.b64decode(first['face']['embedding'], validate=True)
        self.assertEqual(len(raw), 768 * 4)
        self.assertEqual(first['face']['embedding_model_id'], 'ccip-caformer24@1')
        self.assertTrue(first['face']['crop_jpeg'])
        self.assertEqual(len(first['body']['appearance']), len(c.body_appearance))
        self.assertTrue(first['body']['crop_jpeg'])
        self.assertIsNone(second['body'])
        self.assertEqual(len(first['descriptor']), DIM)

    def test_desktop_persistence_same_frame_constraint_rescan_and_reload(self):
        from character_library import store_character
        from database import JsonDatabase
        with tempfile.TemporaryDirectory() as tmp:
            db = JsonDatabase(Path(tmp) / 'library')
            media = db.upsert_media('synthetic.png', {'type': 'image'})
            img = drawing()
            first = detect_characters(img, [body()])[0]
            a, new = store_character(db, first, media, None, None, Path(tmp) / 'crops', img)
            self.assertTrue(new)
            again, new = store_character(db, first, media, None, None, Path(tmp) / 'crops', img)
            self.assertEqual(a, again)
            self.assertFalse(new)
            second = type(first)(np.array([150, 0, 278, 256], np.float32), .95, first.descriptor)
            canvas = np.concatenate([img, np.full((256, 22, 3), 245, np.uint8), img], axis=1)
            b, _ = store_character(db, second, media, None, None, Path(tmp) / 'crops', canvas)
            self.assertNotEqual(db.character_samples[a]['identity_id'], db.character_samples[b]['identity_id'])
            # Separate photo, no competing twin: exact appearance joins its identity.
            other = db.upsert_media('other.png', {'type': 'image'})
            hair_other = detect_characters(drawing(hair=(220, 20, 180)), [body()])[0]
            c, _ = store_character(db, hair_other, other, None, None, Path(tmp) / 'crops', img)
            third = db.upsert_media('third.png', {'type': 'image'})
            d, _ = store_character(db, hair_other, third, None, None, Path(tmp) / 'crops', img)
            self.assertEqual(db.character_samples[c]['identity_id'], db.character_samples[d]['identity_id'])
            loaded = JsonDatabase(Path(tmp) / 'library')
            self.assertEqual(len(loaded.character_samples), 4)
            self.assertFalse(loaded.faces)
            loaded.delete_media(third, delete_children=True)
            self.assertNotIn(d, loaded.character_samples)


class KindCorrectionTests(unittest.TestCase):
    """The user's "this is a person / a character" corrections (force_kind, kind_overrides)."""

    def setUp(self):
        import analysis
        self.analysis = analysis
        self.saved = analysis._anime_detector, analysis._ccip_embedder
        anime = self.anime = []

        class Anime:
            def detect(self, img, score_thresh):
                return list(anime)

        class Embedder:
            def embed_crop(self, crop):
                v = np.zeros(768, np.float32)
                v[1] = 1.0
                return v
        analysis._anime_detector, analysis._ccip_embedder = Anime(), Embedder()

    def tearDown(self):
        self.analysis._anime_detector, self.analysis._ccip_embedder = self.saved

    @staticmethod
    def bodies(*boxes):
        class Bodies:
            available = True
            def analyze(self, img, score_thr):
                return [body(b) for b in boxes]
        return Bodies()

    @staticmethod
    def face(box=(40, 10, 88, 72), score=.9):
        return SimpleNamespace(bbox=np.array(box, np.float32), det_score=score, kps=None,
                               embedding=np.ones(512, np.float32))

    def run_frame(self, faces, bodies, quality=.7, **opts):
        options = AnalyzeOptions(detect_bodies=True, detect_characters=True, **opts)
        return analyze_frame(None, bodies, drawing(), options, detect=lambda _: list(faces),
                             assess=lambda img, f: {"quality_score": quality})

    def test_a_real_face_called_a_character_becomes_the_characters_face(self):
        box = (40 / 128, 10 / 256, 88 / 128, 72 / 256)
        res = self.run_frame([self.face()], self.bodies((0, 0, 128, 256)),
                             kind_overrides=(("character", "face", box),))
        self.assertEqual(res.faces, [])
        self.assertEqual(res.bodies, [])
        self.assertEqual(len(res.characters), 1)
        c = res.characters[0]
        self.assertEqual(list(c.face_bbox), [40, 10, 88, 72])
        self.assertEqual(list(c.body_bbox), [0, 0, 128, 256])
        self.assertEqual(c.face_embedding.shape, (768,))

    def test_an_anime_face_called_a_person_is_kept_as_a_forced_person(self):
        self.anime.append({"bbox": np.array([40, 10, 88, 72], np.float32), "score": .9})
        box = (40 / 128, 10 / 256, 88 / 128, 72 / 256)
        # Low quality and below the gate: still a person, because the user said so.
        res = self.run_frame([self.face(score=.9)], self.bodies((0, 0, 128, 256)), quality=.2,
                             min_face_quality=.4, kind_overrides=(("person", "face", box),))
        self.assertEqual(len(res.faces), 1)
        self.assertEqual(res.forced, [True])
        self.assertEqual(res.passes_gate, [True])
        self.assertEqual(res.characters, [])
        self.assertEqual(len(res.bodies), 1)
        self.assertEqual(len(res.pairs), 1)

    def test_a_person_face_missed_by_the_full_frame_pass_is_searched_around_its_box(self):
        calls = []

        def detect(img):
            calls.append(img.shape)
            if len(calls) == 1:
                return []  # the whole frame: nothing
            return [self.face((20, 20, 40, 44))]  # the crop: a face, in crop coordinates
        options = AnalyzeOptions(detect_bodies=False, detect_characters=True,
                                 kind_overrides=(("person", "face", (40 / 128, 30 / 256, 60 / 128, 54 / 256)),))
        res = analyze_frame(None, self.bodies(), drawing(), options, detect=detect,
                            assess=lambda img, f: {"quality_score": .7})
        self.assertEqual(len(calls), 2)
        self.assertEqual(len(res.faces), 1)
        self.assertEqual([float(v) for v in res.faces[0].bbox], [40.0, 26.0, 60.0, 50.0])  # crop starts at (20, 6)

    def drawn_face(self, box=(40, 10, 88, 72), score=.9):
        import drawn_faces
        f = self.face(box, score)
        f.embedding = (drawn_faces._direction * 20).astype(np.float32)
        return f

    def test_a_drawn_face_is_boxed_by_the_people_detector(self):
        """Both detectors see the face: the character keeps the people detector's box."""
        self.anime.append({"bbox": np.array([30, 0, 100, 90], np.float32), "score": .6})
        res = self.run_frame([self.drawn_face()], self.bodies((0, 0, 128, 256)))
        self.assertEqual(res.faces, [])
        self.assertEqual(len(res.characters), 1)
        c = res.characters[0]
        self.assertEqual(list(c.face_bbox), [40, 10, 88, 72])
        self.assertAlmostEqual(c.face_score, .9, places=5)
        self.assertEqual(list(c.body_bbox), [0, 0, 128, 256])
        self.assertEqual(c.face_embedding.shape, (768,))

    def test_a_drawn_face_the_anime_detector_missed_is_still_the_characters_face(self):
        res = self.run_frame([self.drawn_face()], self.bodies((0, 0, 128, 256)))
        self.assertEqual(len(res.characters), 1)
        self.assertEqual(list(res.characters[0].face_bbox), [40, 10, 88, 72])
        # Below the gate (hair, fabric look "drawn" too) it is no face unless the anime
        # detector agrees; then the body is a faceless figure.
        weak = self.run_frame([self.drawn_face()], self.bodies((0, 0, 128, 256)), quality=.2,
                              min_face_quality=.4)
        self.assertEqual(len(weak.characters), 1)
        self.assertIsNone(weak.characters[0].face_bbox)
        self.anime.append({"bbox": np.array([38, 8, 90, 74], np.float32), "score": .7})
        agreed = self.run_frame([self.drawn_face()], self.bodies((0, 0, 128, 256)), quality=.2,
                                min_face_quality=.4)
        self.assertEqual(list(agreed.characters[0].face_bbox), [40, 10, 88, 72])

    def test_in_an_ordinary_photo_a_drawn_looking_face_alone_is_no_character(self):
        """A dog's face also looks "drawn": outside a drawing it needs the anime detector."""
        res = self.run_frame([self.drawn_face()], self.bodies(), faceless_characters=False)
        self.assertEqual(res.characters, [])
        self.assertEqual(res.faces, [])
        self.anime.append({"bbox": np.array([10, 150, 40, 190], np.float32), "score": .8})
        seen = self.run_frame([self.drawn_face()], self.bodies(), faceless_characters=False)
        self.assertEqual(sorted(list(c.face_bbox) for c in seen.characters),
                         [[10, 150, 40, 190], [40, 10, 88, 72]])

    def test_the_anime_detector_fills_in_faces_the_people_detector_missed(self):
        self.anime.append({"bbox": np.array([10, 150, 40, 190], np.float32), "score": .8})
        res = self.run_frame([self.drawn_face()], self.bodies((0, 0, 128, 256)))
        boxes = sorted(list(c.face_bbox) for c in res.characters if c.face_bbox is not None)
        self.assertEqual(boxes, [[10, 150, 40, 190], [40, 10, 88, 72]])

    def test_a_clear_real_face_in_a_drawing_still_vetoes_and_stays_a_person(self):
        self.anime.append({"bbox": np.array([40, 10, 88, 72], np.float32), "score": .9})
        res = self.run_frame([self.face()], self.bodies((0, 0, 128, 256)))
        self.assertEqual(len(res.faces), 1)
        self.assertEqual(res.characters, [])

    def test_force_person_keeps_drawn_faces_and_makes_no_characters(self):
        import drawn_faces
        self.anime.append({"bbox": np.array([40, 10, 88, 72], np.float32), "score": .9})
        saved = drawn_faces.is_drawn
        drawn_faces.is_drawn = lambda e: True
        try:
            res = self.run_frame([self.face()], self.bodies((0, 0, 128, 256)), force_kind="person")
        finally:
            drawn_faces.is_drawn = saved
        self.assertEqual(len(res.faces), 1)
        self.assertEqual(res.forced, [True])
        self.assertEqual(res.characters, [])
        self.assertEqual(len(res.bodies), 1)

    def test_force_character_turns_a_real_face_and_its_body_into_a_character(self):
        res = self.run_frame([self.face()], self.bodies((0, 0, 128, 256)), force_kind="character")
        self.assertEqual((res.faces, res.bodies), ([], []))
        self.assertEqual(len(res.characters), 1)
        self.assertIsNotNone(res.characters[0].face_bbox)

    def test_a_single_correction_wins_over_the_whole_frame(self):
        box = (40 / 128, 10 / 256, 88 / 128, 72 / 256)
        res = self.run_frame([self.face()], self.bodies((0, 0, 128, 256)), force_kind="character",
                             kind_overrides=(("person", "face", box), ("person", "body", (0, 0, 1, 1))))
        self.assertEqual(len(res.faces), 1)
        self.assertEqual(len(res.bodies), 1)
        self.assertEqual(res.characters, [])

    def test_bodies_called_people_or_characters_follow_the_user(self):
        to_person = self.run_frame([], self.bodies((0, 0, 128, 256)),
                                   kind_overrides=(("person", "body", (0, 0, 1, 1)),))
        self.assertEqual((len(to_person.bodies), to_person.characters), (1, []))
        # A real face elsewhere would normally make this faceless body a person.
        to_char = self.run_frame([self.face((100, 200, 124, 228))], self.bodies((0, 0, 90, 190)),
                                 kind_overrides=(("character", "body", (0, 0, 90 / 128, 190 / 256)),))
        self.assertEqual(len(to_char.characters), 1)
        self.assertEqual(to_char.bodies, [])

    def test_a_faceless_body_in_an_ordinary_photo_stays_a_person(self):
        photo = self.run_frame([], self.bodies((0, 0, 128, 256)), faceless_characters=False)
        self.assertEqual((len(photo.bodies), photo.characters), (1, []))
        illustrated = self.run_frame([], self.bodies((0, 0, 128, 256)))
        self.assertEqual((illustrated.bodies, len(illustrated.characters)), ([], 1))
        # Next to a drawn face, a faceless figure is a character even in an ordinary photo.
        self.anime.append({"bbox": np.array([2, 2, 20, 20], np.float32), "score": .9})
        drawn = self.run_frame([], self.bodies((40, 60, 128, 256)), faceless_characters=False)
        self.assertEqual(len(drawn.characters), 2)

    def test_wire_options_corrections_and_forced_faces(self):
        from analysis import FrameAnalysis
        from mobile_api.schemas import analysis_to_response, parse_analyze_options
        opts = parse_analyze_options(json.dumps({
            "detect_characters": True, "faceless_characters": False, "force_kind": "character",
            "kind_overrides": [{"kind": "person", "part": "face", "box": [.25, .5, .5, .25]},
                               {"kind": "character", "part": "body", "box": [0, 0, 1, 1], "timestamp_ms": 2000}]}))
        self.assertFalse(opts.faceless_characters)
        self.assertEqual(opts.force_kind, "character")
        self.assertEqual(opts.kind_overrides[0], ("person", "face", (.25, .5, .75, .75), None))
        engine = opts.engine_options(timestamp_ms=5000, tolerance_ms=500)
        self.assertEqual(engine.kind_overrides, (("person", "face", (.25, .5, .75, .75)),))
        self.assertEqual(len(opts.engine_options(timestamp_ms=2400, tolerance_ms=500).kind_overrides), 2)
        self.assertEqual(len(opts.engine_options().kind_overrides), 2)
        for bad in ({"force_kind": "robot"},
                    {"kind_overrides": [{"kind": "person", "part": "hand", "box": [0, 0, 1, 1]}]},
                    {"kind_overrides": [{"kind": "person", "part": "face", "box": [0, 0, 0, 1]}]},
                    {"kind_overrides": [{"kind": "person", "part": "face", "box": [0, 0, 1, 1], "timestamp_ms": -1}]},
                    {"kind_overrides": "all"}):
            with self.assertRaises(Exception):
                parse_analyze_options(json.dumps(bad))
        q = {"quality_score": .7, "quality_version": 2, "quality_parts": {}, "det_score": .9, "face_px": 48,
             "sharpness": 1.0, "embedding_norm": 20.0, "pose": None}
        face = SimpleNamespace(bbox=np.array([40, 10, 88, 72], np.float32), det_score=.9,
                               kps=np.zeros((5, 2), np.float32),
                               normed_embedding=np.ones(512, np.float32) / 512 ** .5)
        result = FrameAnalysis([face, face], [q, q], [True, True], [], [], [], image_w=128, image_h=256,
                               forced=[True, False])
        wire = analysis_to_response(result, drawing(), opts)
        self.assertIs(wire["faces"][0]["forced"], True)
        self.assertNotIn("forced", wire["faces"][1])

    def test_character_body_gets_extent_and_outline_through_worker_and_wire(self):
        from analysis import FrameAnalysis
        from mobile_api.scan_worker import decode_result, encode_result
        from mobile_api.schemas import AnalyzeRequestOptions, analysis_to_response
        kb = SimpleNamespace(bbox=np.array([0, 0, 128, 256], np.float32), score=.95,
                             kpts=np.full((17, 2), 64, np.float32), kpt_scores=np.full(17, .9, np.float32))
        c = detect_characters(drawing(), [kb])[0]
        c.body_outline = np.array([[0, 0], [100, 0], [100, 200]], np.float32)
        result = FrameAnalysis([], [], [], [], [], [], image_w=128, image_h=256, characters=[c])
        decoded = decode_result(json.loads(json.dumps(encode_result(result))))
        self.assertEqual(decoded.characters[0].body_outline.shape, (3, 2))
        wire = analysis_to_response(decoded, drawing(), AnalyzeRequestOptions(detect_characters=True,
                                                                                return_outlines=True))
        self.assertEqual(wire["characters"][0]["body"]["extent"], "full")
        self.assertIsNotNone(wire["characters"][0]["body"]["outline"])
        plain = analysis_to_response(decoded, drawing(), AnalyzeRequestOptions(detect_characters=True))
        self.assertNotIn("outline", plain["characters"][0]["body"])

    def test_outline_engine_draws_character_bodies(self):
        from outlines import OutlineEngine
        engine = OutlineEngine.__new__(OutlineEngine)
        seen = []
        engine.face_outline = lambda img, face: None

        def shapes(img, bodies):
            seen.append(len(bodies))
            return [np.zeros((3, 2))] * len(bodies)
        engine.body_outlines = shapes
        c = detect_characters(drawing(), [body()])[0]
        result = SimpleNamespace(faces=[], passes_gate=[], bodies=[], characters=[c], timings_ms={})
        engine.compute(drawing(), result)
        self.assertEqual(seen, [0, 1])
        self.assertEqual(c.body_outline.shape, (3, 2))


if __name__ == '__main__':
    unittest.main(verbosity=2)
