"""Reface correctness regressions; synthetic frames, no models or user library."""
import io
import itertools
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import cv2
import numpy as np

from face_compositor import CompositeConfig, FaceCompositor
from identity import build_identity_embedding, select_identity_faces
from reface_engine import FaceData, Faceset
from reface_engine_v3 import RefaceEngineV3, FaceSelector
from reface_tracking import FaceTracker, assignment
from reface_video_io import validate_video


def unit(seed):
    x = np.random.default_rng(seed).standard_normal(512).astype(np.float32)
    return x / np.linalg.norm(x)


def face(x, identity=1):
    return SimpleNamespace(kps=np.array([[x-20,90],[x+20,90],[x,110],[x-15,130],[x+15,130]], np.float32),
                           bbox=np.array([x-35,65,x+35,150], np.float32), embedding=unit(identity))


class Masker:
    occluder = True
    parser = True
    def __init__(self):
        self.occ = np.ones((512,512), np.float32)
    def segment(self, crop):
        seg = np.zeros((512,512), np.uint8)
        seg[50:460,50:460] = 1
        return seg
    def occlusion_mask(self, crop):
        return self.occ


class QualityTests(unittest.TestCase):
    def test_global_assignment_matches_exhaustive_minimum(self):
        rng = np.random.default_rng(18)
        for n, m in [(1,3),(2,4),(3,5)]:
            for _ in range(5):
                costs = rng.random((n,m))
                got = assignment(costs)
                best = min(sum(costs[i,j] for i,j in enumerate(cols)) for cols in itertools.permutations(range(m),n))
                self.assertAlmostEqual(sum(costs[i,got[i]] for i in range(n)), best)

    def test_crossing_people_keep_identity_even_when_detection_order_changes(self):
        tracker = FaceTracker()
        ids = tracker.update([face(100,1), face(160,2)])
        next_ids = tracker.update([face(110,2), face(150,1)])
        self.assertEqual(next_ids, [ids[1],ids[0]])

    def test_short_detection_gap_preserves_track(self):
        tracker = FaceTracker()
        old = tracker.update([face(100)])
        tracker.update([])
        self.assertEqual(tracker.update([face(105)]),old)

    def test_replaced_person_gets_new_track_at_same_position(self):
        tracker = FaceTracker()
        old = tracker.update([face(100,1)])
        self.assertNotEqual(tracker.update([face(100,2)]),old)

    def test_clear_does_not_reuse_cached_ids(self):
        tracker = FaceTracker()
        old = tracker.update([face(100)])
        tracker.clear()
        self.assertNotEqual(tracker.update([face(100)]),old)

    def test_selector_rejects_bystander_immediately_on_same_track(self):
        selector = FaceSelector([unit(1),unit(2)],[0])
        self.assertTrue(selector.wants(1,0,lambda:unit(1)))
        self.assertFalse(selector.wants(1,1,lambda:unit(2)))

    def test_scene_cut_resets_tracks_compositor_and_selector(self):
        engine = RefaceEngineV3.__new__(RefaceEngineV3)
        engine._reset_tracks()
        engine.compositor = SimpleNamespace(reset=lambda: calls.append('compositor'))
        calls = []
        selector = SimpleNamespace(reset=lambda:calls.append('selector'))
        ids = engine._tracker.update([face(100)])
        engine._check_scene(np.zeros((64,64,3),np.uint8),selector)
        engine._check_scene(np.full((64,64,3),255,np.uint8),selector)
        self.assertEqual(calls,['compositor','selector'])
        self.assertNotEqual(engine._tracker.update([face(100)]),ids)

    def test_hand_is_protected_on_first_frame_it_enters(self):
        masker = Masker()
        comp = FaceCompositor(SimpleNamespace(available=False),masker,
                              CompositeConfig(temporal=True))
        frame = np.zeros((512,512,3),np.uint8)
        crop = np.full_like(frame,120)
        from face_compositor import _FFHQ_512
        affine = np.array([[1,0,0],[0,1,0]],np.float32)
        masks = []
        comp._paste = lambda frame,crop,mask,*args: (masks.append(mask.copy()) or frame)
        comp.begin_frame()
        comp.composite(frame,crop,affine,_FFHQ_512,track_id=1)
        masker.occ[200:320,200:320] = 0
        comp.begin_frame()
        comp.composite(frame,crop,affine,_FFHQ_512,track_id=1)
        self.assertGreater(masks[0][260,260],.8)
        self.assertEqual(masks[1][260,260],0)

    def test_nonfinite_occlusion_fails_without_unprotected_paste(self):
        masker = Masker()
        masker.occ[:] = np.nan
        comp = FaceCompositor(SimpleNamespace(available=False),masker)
        from face_compositor import _FFHQ_512
        frame = np.zeros((512,512,3),np.uint8)
        got = comp.composite(frame,np.full_like(frame,120),np.array([[1,0,0],[0,1,0]],np.float32),_FFHQ_512)
        self.assertTrue(np.array_equal(got,frame))
        self.assertEqual(comp.last_status,'failed')

    def test_full_frame_compatibility_preserves_previous_faces(self):
        engine = RefaceEngineV3.__new__(RefaceEngineV3)
        engine.dfm = None
        engine.identity_boost = 0
        original = np.zeros((512,512,3),np.uint8)
        result = original.copy()
        result[:40,:40] = 77
        full = original.copy()
        full[150:350,150:350] = 180
        engine.swapper = SimpleNamespace(get=lambda *a,**k:full)
        engine.compositor = FaceCompositor(SimpleNamespace(available=False), Masker())
        from face_compositor import _FFHQ_512
        target = SimpleNamespace(kps=_FFHQ_512,bbox=np.array([150,150,350,350]))
        got = engine._process_face(result,original,target,SimpleNamespace(),1)
        np.testing.assert_array_equal(got[:40,:40],result[:40,:40])
        self.assertEqual(engine._frame_outcomes[-1]['status'],'swapped')

    def test_failed_swap_is_counted_as_failure(self):
        engine = RefaceEngineV3.__new__(RefaceEngineV3)
        engine.dfm,engine.identity_boost = None,0
        def fail(*a,**k): raise RuntimeError('model failed')
        engine.swapper = SimpleNamespace(get=fail)
        engine.compositor = SimpleNamespace(_log_once=lambda *a:None)
        frame = np.zeros((200,200,3),np.uint8)
        self.assertIs(engine._process_face(frame,frame,face(100),None),frame)
        self.assertEqual(engine._frame_outcomes[0]['status'],'failed')

    def test_identity_filters_outlier_and_duplicates(self):
        fs = Faceset('test')
        for i,(v,q) in enumerate([(unit(1),.8),(unit(1),.9),(unit(1)*.99+unit(3)*.12,.7),(unit(2),1)]):
            fs.add_face(FaceData('',v,(0,0,0),[],q))
        rows, report = select_identity_faces(fs)
        self.assertEqual(report['kept'],1)
        self.assertGreater(float(build_identity_embedding(fs) @ unit(1)),.99)
        self.assertEqual(rows[0][2],.9)

    def test_generated_faces_cannot_dominate_real_identity(self):
        fs = Faceset('mixed')
        real = unit(1)
        fs.add_face(FaceData('',real,(0,0,0),[],.8))
        for i in range(6):
            v = real*.7 + unit(i+10)*.7
            fd = FaceData('',v,(0,0,0),[],1)
            fd.generated = True
            fs.add_face(fd)
        rows,_ = select_identity_faces(fs)
        real_weight = sum(q for f,_,q in rows if not getattr(f,'generated',False))
        generated = sum(q for f,_,q in rows if getattr(f,'generated',False))
        self.assertLessEqual(generated,real_weight*.25+1e-6)
        self.assertGreater(float(build_identity_embedding(fs) @ real),.98)

    def test_benchmark_ranking_penalizes_poor_coverage(self):
        from eval_reface import rank
        def row(name,identity,coverage,failures):
            return dict(label=name,summary=dict(identity=identity,score_coverage=coverage,
                        failure_rate=failures,sharpness=1,flicker=1,leak=.2,id_wobble=.01))
        bad = row('bad',.95,.4,.2)
        good = row('good',.6,.99,0)
        ranked = rank([bad,good])
        self.assertEqual([r['label'] for r in ranked],['good','bad'])

    def test_benchmark_rejects_identical_held_out_input(self):
        import json
        from eval_reface import load_cases
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root/'photo.png').write_bytes(b'identical')
            (root/'cases.json').write_text(json.dumps(dict(people=dict(person=dict(build=['photo.png'],held_out=['photo.png'])))))
            with self.assertRaisesRegex(ValueError,'identical'): load_cases(root/'cases.json')

    def test_broken_pipe_is_not_ignored(self):
        engine = RefaceEngineV3.__new__(RefaceEngineV3)
        def fail(*a): raise BrokenPipeError('encoder died')
        proc = SimpleNamespace(poll=lambda:None,stdin=SimpleNamespace(write=fail))
        with self.assertRaises(BrokenPipeError):
            engine._write(None,proc,np.zeros((8,8,3),np.uint8))

    def test_stalled_frame_write_is_bounded_and_kills_encoder(self):
        import threading
        from concurrent.futures import ThreadPoolExecutor
        engine = RefaceEngineV3.__new__(RefaceEngineV3)
        engine.writer_timeout = .02
        released = threading.Event()
        state = {'code':None}
        class Input:
            closed = False
            def write(self, pixels):
                released.wait(5)
                return len(pixels)
            def flush(self): pass
            def close(self): self.closed=True
        def kill():
            state['code']=-1
            released.set()
        proc = SimpleNamespace(stdin=Input(),poll=lambda:state['code'],kill=kill,wait=lambda **k:state['code'],
                               _reface_writer=ThreadPoolExecutor(max_workers=1))
        try:
            with self.assertRaisesRegex(OSError,'stopped accepting'):
                engine._write(None,proc,np.zeros((8,8,3),np.uint8))
            self.assertEqual(state['code'],-1)
        finally:
            engine._abort_writer(None,proc)

    def test_partial_image_reports_one_success_and_one_failure(self):
        engine = RefaceEngineV3.__new__(RefaceEngineV3)
        engine.swapper = SimpleNamespace(get=lambda *a,**k:(np.ones((128,128,3),np.uint8),np.array([[1,0,0],[0,1,0]],np.float32)))
        engine.dfm, engine.identity_boost = None,0
        engine.effective_settings = lambda:{}
        def composite(result,crop,matrix,kps,**kwargs):
            if kwargs['track_id']==1: raise RuntimeError('second face failed')
            out=result.copy()
            out[65:150,65:135]=120
            return out
        engine.compositor = SimpleNamespace(reset=lambda:None,begin_frame=lambda:None,config=SimpleNamespace(temporal=False),
                                            composite=composite,last_status='swapped',last_reason='',_log_once=lambda *a:None)
        engine._detect=lambda image:[face(100),face(300,2)]
        faceset=Faceset('test')
        faceset.add_face(FaceData('',unit(3),(0,0,0),[],.8))
        with tempfile.TemporaryDirectory() as tmp:
            engine.output_dir=Path(tmp)
            target=Path(tmp)/'target.png'
            cv2.imwrite(str(target),np.zeros((200,400,3),np.uint8))
            result=engine.reface_image_v3(str(target),faceset)
            self.assertTrue(result.success)
            self.assertEqual(result.faces_swapped,1)
            self.assertEqual(result.details['faces_failed'],1)
            rendered=cv2.imread(result.output_path)
            self.assertEqual(int(rendered[100,300,0]),0)

    def test_nonzero_encoder_exit_is_failure(self):
        engine = RefaceEngineV3.__new__(RefaceEngineV3)
        proc = SimpleNamespace(stdin=io.BytesIO(),wait=lambda **k:1,poll=lambda:1)
        with self.assertRaisesRegex(OSError,'encoder failed'):
            engine._close_writer(None,proc)

    def test_encoder_timeout_kills_process(self):
        import subprocess
        engine = RefaceEngineV3.__new__(RefaceEngineV3)
        state = {'code':None,'killed':False}
        def wait(**kwargs):
            if state['code'] is None: raise subprocess.TimeoutExpired('ffmpeg',60)
            return state['code']
        def kill(): state.update(code=-1,killed=True)
        proc = SimpleNamespace(stdin=io.BytesIO(),wait=wait,poll=lambda:state['code'],kill=kill)
        with self.assertRaises(subprocess.TimeoutExpired): engine._close_writer(None,proc)
        self.assertTrue(state['killed'])

    def test_short_parts_keep_fractional_frame_rate_after_concat(self):
        import subprocess
        from ffmpeg_utils import build_concat_command
        engine=RefaceEngineV3.__new__(RefaceEngineV3)
        with tempfile.TemporaryDirectory() as tmp:
            directory=Path(tmp)
            paths=[]
            for index,count in enumerate([3,6]):
                path=directory/f'part-{index}.mp4'
                writer,proc=engine._open_writer(path,30000/1001,64,48)
                try:
                    for _ in range(count): engine._write(writer,proc,np.full((48,64,3),index*80,np.uint8))
                    engine._close_writer(writer,proc)
                finally: engine._abort_writer(writer,proc)
                paths.append(path)
            durations=[validate_video(path)['duration'] for path in paths]
            output=directory/'joined.mp4'
            subprocess.run(build_concat_command(paths,directory/'parts.txt',output,durations),check=True,capture_output=True)
            self.assertEqual(validate_video(output,9,30000/1001)['frames'],9)

    def test_real_encoder_handles_odd_dimensions_and_frame_count(self):
        engine = RefaceEngineV3.__new__(RefaceEngineV3)
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)/'odd.mp4'
            writer,proc = engine._open_writer(output,30000/1001,65,49)
            try:
                for i in range(5): engine._write(writer,proc,np.full((49,65,3),i*30,np.uint8))
                engine._close_writer(writer,proc)
            finally:
                engine._abort_writer(writer,proc)
            self.assertEqual(validate_video(output,5,30000/1001)['frames'],5)
            with self.assertRaisesRegex(ValueError,'expected 6'): validate_video(output,6)


if __name__ == '__main__':
    unittest.main(verbosity=2)
