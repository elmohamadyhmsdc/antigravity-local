"""Video continuity regressions using synthetic pixels; no models or user media."""
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

import cv2
import numpy as np
from insightface.app.common import Face

from reface_engine import FaceData, Faceset
from reface_engine_v2 import RefaceEngineV2, VideoConfig
from reface_selection import FaceSelector
from reface_video_detection import VideoFaceRecovery, detect_faces
from reface_video_io import validate_video


def unit(index):
    vector = np.zeros(512, np.float32)
    vector[index] = 1
    return vector


def face(index=0, box=(80, 60, 120, 110)):
    x, y, x1, y1 = box
    return Face(bbox=np.array(box, np.float32),
                           kps=np.array([[x+10,y+10],[x1-10,y+10],[(x+x1)/2,y+25],
                                         [x+10,y1-10],[x1-10,y1-10]], np.float32),
                           embedding=unit(index),
                           pose=np.array([30, 0, 0]), landmark_3d_68=None)


class ContinuityTests(unittest.TestCase):
    def test_multiple_selected_poses_do_not_cancel_the_same_person(self):
        other_pose = unit(0) + .1 * unit(10)
        other_pose /= np.linalg.norm(other_pose)
        selector = FaceSelector([unit(0), other_pose, unit(1)], [0, 1])
        for embedding in (unit(0), other_pose, (unit(0) + other_pose) / 2):
            self.assertTrue(selector.wants(0, 0, lambda: embedding))
        self.assertFalse(selector.wants(0, 1, lambda: unit(1)))
        # The same near-tie with an unselected lookalike must still be rejected.
        selector = FaceSelector([unit(0), other_pose], [0])
        self.assertFalse(selector.wants(0, 0, lambda: (unit(0) + other_pose) / 2))

    def test_missed_person_is_redetected_from_current_pixels_and_coordinates_restored(self):
        recovery = VideoFaceRecovery()
        selector = FaceSelector([unit(0), unit(1)], [0])
        accepts = lambda f: selector.wants(0, 0, lambda: f.normed_embedding)
        frame = np.full((180, 240, 3), 80, np.uint8)
        recovery.detect(frame, lambda image: [face()], accepts)
        shapes = []
        def detector(image):
            shapes.append(image.shape)
            if image.shape == frame.shape:
                return [face(1, (160, 60, 200, 110))]
            self.assertTrue(np.all(image == 81))
            # Previous box was expanded by (24, 30), so the ROI begins at (56, 30).
            return [face(0, (24, 30, 64, 80))]
        recovered = recovery.detect(frame + 1, detector, accepts)
        selected = [f for f in recovered if accepts(f)]
        self.assertEqual(len(selected), 1)
        np.testing.assert_array_equal(selected[0].bbox, [80, 60, 120, 110])
        np.testing.assert_array_equal(selected[0].kps[0], [90, 70])
        self.assertEqual(len(recovered), 2)
        self.assertEqual(len(shapes), 2)
        self.assertEqual(recovery.recovered, 1)

    def test_recovery_never_reuses_a_face_when_current_pixels_are_a_bystander(self):
        recovery = VideoFaceRecovery()
        selector = FaceSelector([unit(0), unit(1)], [0])
        accepts = lambda f: selector.wants(0, 0, lambda: f.normed_embedding)
        frame = np.full((180, 240, 3), 80, np.uint8)
        recovery.detect(frame, lambda image: [face()], accepts)
        for _ in range(4):
            current = recovery.detect(frame, lambda image: [face(1)], accepts)
            self.assertFalse(any(accepts(f) for f in current))
        self.assertEqual(recovery.previous, [])
        self.assertEqual(recovery.recovered, 0)

    def test_scene_cut_discards_search_regions(self):
        recovery = VideoFaceRecovery()
        recovery.detect(np.zeros((180,240,3), np.uint8), lambda image: [face()])
        detector = Mock(return_value=[])
        self.assertEqual(recovery.detect(np.full((180,240,3), 255, np.uint8), detector), [])
        self.assertEqual(detector.call_count, 1)
        self.assertEqual(recovery.previous, [])

    def test_regular_frames_do_not_repeat_detection_or_return_duplicate_faces(self):
        recovery = VideoFaceRecovery()
        frame = np.zeros((180,240,3), np.uint8)
        detector = Mock(side_effect=lambda image: [face()])
        for _ in range(6):
            self.assertEqual(len(recovery.detect(frame, detector)), 1)
        self.assertEqual(detector.call_count, 6)

    def test_detector_skips_age_gender_and_unused_landmarks(self):
        def embed(image, detected):
            detected.embedding = unit(0)
        app = SimpleNamespace(
            det_model=SimpleNamespace(detect=Mock(return_value=(
                np.array([[20,20,40,48,.99]], np.float32), np.ones((1,5,2), np.float32)))),
            models={name: SimpleNamespace(get=Mock(side_effect=embed if name == 'recognition' else None))
                    for name in ('recognition', 'landmark_3d_68', 'landmark_2d_106', 'genderage')})
        detections = detect_faces(app, np.zeros((64,64,3), np.uint8), landmarks=True)
        self.assertEqual(len(detections), 1)
        self.assertEqual(app.models['recognition'].get.call_count, 1)
        self.assertEqual(app.models['landmark_3d_68'].get.call_count, 1)
        self.assertEqual(app.models['genderage'].get.call_count, 0)
        self.assertEqual(app.models['landmark_2d_106'].get.call_count, 0)

    def test_v2_swaps_every_frame_through_detection_misses_and_keeps_fractional_fps(self):
        engine = RefaceEngineV2.__new__(RefaceEngineV2)
        engine.app = None
        engine.neural_enhancer = engine.occlusion_handler = engine.temporal_stabilizer = None
        engine.video_config = VideoConfig(temporal_smoothing=False)
        engine._advanced_color_correction = lambda result, original, mask: result
        seen_sources = []
        def swap(image, target, source, **kwargs):
            seen_sources.append(source.normed_embedding.copy())
            out = image.copy()
            x, y, x1, y1 = target.bbox.astype(int)
            out[y:y1,x:x1] = 230
            return out
        engine.swapper = SimpleNamespace(get=swap)
        full_frames = 0
        missing_frames = {3, 5}
        def detector(image):
            nonlocal full_frames
            if image.shape[:2] == (64,64):
                full_frames += 1
                if full_frames in missing_frames:
                    return []
                return [face(0, (20,20,40,48))]
            # The expanded region begins at (8, 3).
            return [face(0, (12,17,32,45))]
        engine._detect_video_faces = detector
        sources = Faceset('mobile')
        # Every mobile source has an empty path; pose matching must use the actual item.
        sources.add_face(FaceData('', unit(2), (0,0,0), [], .8))
        sources.add_face(FaceData('', unit(3), (30,0,0), [], .8))
        other_pose = unit(0) + .1 * unit(10)
        other_pose /= np.linalg.norm(other_pose)
        references = [unit(0), other_pose, unit(1)]
        with tempfile.TemporaryDirectory() as tmp:
            engine.output_dir = Path(tmp)
            source = Path(tmp) / 'source.avi'
            fps = 30000 / 1001
            writer = cv2.VideoWriter(str(source), cv2.VideoWriter_fourcc(*'MJPG'), fps, (64,64))
            self.assertTrue(writer.isOpened())
            for _ in range(8):
                writer.write(np.full((64,64,3), 80, np.uint8))
            writer.release()
            result = engine.reface_video_with_faceset_v2(str(source), sources,
                target_face_indices=[0,1], target_face_embeddings=references, finalize=False)
            self.assertTrue(result.success, result.message)
            self.assertEqual(result.faces_swapped, 8)
            self.assertEqual(result.details['frames_recovered'], 2)
            validate_video(result.output_path, 8, fps)
            cap = cv2.VideoCapture(result.output_path)
            for _ in range(8):
                ok, rendered = cap.read()
                self.assertTrue(ok)
                self.assertGreater(float(rendered[25:40,25:35].mean()), 210)
            cap.release()
            seen_sources.clear()
            full_frames = 0
            missing_frames = {4, 6}
            resumed = engine.reface_video_with_faceset_v2(str(source), sources,
                target_face_indices=[0,1], target_face_embeddings=references,
                resume_from_frame=3, finalize=False)
            self.assertTrue(resumed.success, resumed.message)
            self.assertNotEqual(resumed.output_path, result.output_path)
            self.assertEqual(resumed.faces_swapped, 5)
            self.assertEqual(resumed.details['frames_recovered'], 2)
            validate_video(resumed.output_path, 5, fps)
        self.assertEqual(full_frames, 8)
        self.assertEqual(len(seen_sources), 5)
        for embedding in seen_sources:
            np.testing.assert_allclose(embedding, unit(3))


if __name__ == '__main__':
    unittest.main(verbosity=2)
