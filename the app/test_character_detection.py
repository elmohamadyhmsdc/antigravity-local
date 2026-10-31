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


if __name__ == '__main__':
    unittest.main(verbosity=2)
