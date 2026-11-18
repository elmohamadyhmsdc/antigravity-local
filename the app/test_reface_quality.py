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

from face_compositor import CompositeConfig, FaceCompositor, Prepared
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
    def test_restorer_cannot_whiten_the_whole_opening_during_speech(self):
        from face_compositor import limit_mouth_restoration
        target = np.full((256, 256, 3), 140, np.uint8)
        target[150:174, 80:170] = 20
        target[150:156, 85:165] = 220
        seg = np.ones(target.shape[:2], np.uint8)
        seg[150:174, 80:170] = 11
        swapped = target.copy()
        swapped[156:174, 80:170] = [35, 25, 60]
        enhanced = swapped.copy()
        enhanced[156:174, 80:170] = 205
        fixed = limit_mouth_restoration(swapped, enhanced, target, seg, seg)
        self.assertLess(float(fixed[166, 125].mean()), 85)
        self.assertGreater(int(fixed[166, 125, 2]), int(fixed[166, 125, 1]))
        np.testing.assert_array_equal(fixed[:140], enhanced[:140])
        unchanged = limit_mouth_restoration(enhanced, swapped, target, seg, seg)
        np.testing.assert_array_equal(unchanged, swapped)

    def test_mobile_source_references_follow_angle_without_switching_identity(self):
        from identity import build_source_from_faceset
        front, side = np.eye(512, dtype=np.float32)[:2]
        side = .89 * front + np.sqrt(1 - .89 ** 2) * side
        sources = Faceset("person")
        sources.add_face(FaceData("", front, (0, 0, 0), [], 1))
        sources.add_face(FaceData("", side, (55, 0, 0), [], 1))
        source = build_source_from_faceset(sources)
        def render_vector(yaw):
            return source.for_face(SimpleNamespace(pose=(0, yaw, 0)), 1).normed_embedding
        self.assertGreater(float(render_vector(55) @ side), float(render_vector(0) @ side))
        self.assertGreater(float(render_vector(55) @ source.normed_embedding), .97)
        np.testing.assert_array_equal(source.for_face(SimpleNamespace(kps=None), 1).normed_embedding,
                                      source.normed_embedding)

    def test_photo_mouth_preserves_teeth_only_when_both_openings_agree(self):
        comp = FaceCompositor(None, Masker(), CompositeConfig())
        seg = np.ones((512, 512), np.uint8)
        seg[300:340, 180:300] = 11
        frame = np.zeros((512, 512, 3), np.uint8)
        moved = np.ones_like(seg)
        moved[300:340, 290:410] = 11
        mask, _, _ = comp._build_mask(frame, frame, (seg, None), moved)
        self.assertTrue(np.all(mask[318, 200:400] > .99))
        mask, _, _ = comp._build_mask(frame, frame, (seg, None), seg)
        self.assertEqual(mask[320, 240], 0)
        self.assertGreater(mask[299, 240], .99)
        closed = np.ones_like(seg)
        mask, _, _ = comp._build_mask(frame, frame, (seg, None), closed)
        self.assertGreater(mask[320, 240], .99)

    def test_hyperswap_pixel_boost_uses_four_aligned_views_for_large_faces(self):
        from face_swappers import HyperSwapper, ARCFACE_128
        from unittest.mock import Mock
        swapper = HyperSwapper.__new__(HyperSwapper)
        swapper.size = 256
        swapper.pixel_boost = True
        swapper.swap_crop = Mock(side_effect=lambda crop, _: 255 - crop)
        frame = np.random.default_rng(12).integers(0, 256, (512, 512, 3), dtype=np.uint8)
        target = SimpleNamespace(kps=ARCFACE_128 * 512, bbox=[0, 0, 512, 512])
        source = SimpleNamespace(normed_embedding=unit(3))
        crop, matrix = swapper.get(frame, target, source)
        self.assertEqual(swapper.swap_crop.call_count, 4)
        self.assertTrue(all(call.args[0].shape == (256, 256, 3) for call in swapper.swap_crop.call_args_list))
        np.testing.assert_array_equal(crop, 255 - frame)
        np.testing.assert_allclose(matrix, np.eye(2, 3), atol=1e-5)
        target.bbox[3] = 288
        partial, _ = swapper.get(frame, target, source)
        ordinary = cv2.warpAffine(crop[::2, ::2], np.float32([[2, 0, 0], [0, 2, 0]]),
                                  (512, 512), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
        np.testing.assert_array_equal(partial, cv2.addWeighted(ordinary, .5, crop, .5, 0))
        for boost, height in ((False, 512), (True, 120)):
            swapper.pixel_boost, target.bbox[3] = boost, height
            swapper.swap_crop.reset_mock()
            crop, _ = swapper.get(frame, target, source)
            self.assertEqual(crop.shape[:2], (256, 256))
            self.assertEqual(swapper.swap_crop.call_count, 1)

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

    def test_moving_hand_leaves_no_original_face_trail(self):
        masker = Masker()
        comp = FaceCompositor(SimpleNamespace(available=False), masker,
                              CompositeConfig(temporal=True, relight=0, focus_match=False,
                                              grain_match=0))
        frame = np.full((512,512,3), 40, np.uint8)
        swapped = np.full_like(frame, 200)
        seg = masker.segment(frame)
        affine = np.array([[1,0,0],[0,1,0]], np.float32)
        # A hand enters, moves across the face, then leaves. Previously its
        # old position exposed 50%, 25%, ... of the original face afterwards.
        for covered in (None, (180,180), (300,180), None):
            occ = np.ones((512,512), np.float32)
            if covered:
                x, y = covered
                occ[y:y+60,x:x+60] = 0
            pre = Prepared(track_id=1, native_px=512, m_ffhq=affine,
                           orig_aligned=frame, base=swapped, orig_masks=(seg,occ), seg_res=seg)
            comp.begin_frame()
            result = comp.finish(pre, frame)
            for x, y in ((210,210), (330,210)):
                protected = covered is not None and (x,y) == (covered[0]+30,covered[1]+30)
                np.testing.assert_array_equal(result[y,x], [40]*3 if protected else [200]*3)
            np.testing.assert_array_equal(result[:30,:30], frame[:30,:30])

    def test_video_swaps_both_mouth_positions_instead_of_exposing_original_lips(self):
        comp = FaceCompositor(SimpleNamespace(available=False), Masker(), CompositeConfig(temporal=True))
        original_seg = np.zeros((512,512), np.uint8)
        original_seg[50:460,50:460] = 1
        swapped_seg = original_seg.copy()
        original_seg[290:330,180:240] = 11
        swapped_seg[290:330,280:340] = 11
        frame = np.zeros((512,512,3), np.uint8)
        mask, _, _ = comp._build_mask(frame, frame, (original_seg,None), swapped_seg)
        self.assertGreater(mask[310,210], .99)
        self.assertGreater(mask[310,310], .99)
        self.assertEqual(mask[20,20], 0)

    def test_video_does_not_copy_original_nose_and_lip_lines(self):
        comp = FaceCompositor(SimpleNamespace(available=False), Masker(),
                              CompositeConfig(temporal=True, relight=0, focus_match=False,
                                              grain_match=0, detail_transfer=.6))
        swapped = np.full((512,512,3), 128, np.uint8)
        original = swapped.copy()
        cv2.line(original, (240,180), (260,280), (30,30,30), 3)
        cv2.line(original, (190,330), (320,330), (40,40,40), 3)
        mask = np.ones((512,512), np.float32)
        result = comp._harmonize(swapped, original, mask, mask, mask, 1, 512)
        np.testing.assert_array_equal(result, swapped)
        # Still-photo skin finishing remains available.
        comp.config.temporal = False
        photo = comp._harmonize(swapped, original, mask, mask, mask, 1, 512)
        self.assertGreater(np.abs(photo.astype(float) - swapped).max(), 10)

    def test_video_matches_grain_even_for_large_faces_without_borrowed_texture(self):
        comp = FaceCompositor(SimpleNamespace(available=False), Masker(),
                              CompositeConfig(temporal=True, relight=0, focus_match=False))
        comp._rng = np.random.default_rng(19)
        swapped = np.full((512,512,3), 128, np.uint8)
        original = np.clip(128 + np.random.default_rng(18).normal(0,5,swapped.shape), 0,255).astype(np.uint8)
        mask = np.ones((512,512), np.float32)
        result = comp._harmonize(swapped, original, mask, mask, mask, 1, 512)
        self.assertGreater(float(result.std()), 1)
        correlation = np.corrcoef((result.astype(float)-128).ravel(), (original.astype(float)-128).ravel())[0,1]
        self.assertLess(abs(correlation), .05)

    def test_gentler_focus_matching_keeps_restored_texture_without_target_detail(self):
        from face_harmonize import laplacian_var
        yy, xx = np.indices((128,128))
        texture = np.clip(128 + 50*np.sin(xx/2) + 30*np.cos(yy/3), 0,255).astype(np.uint8)
        restored = np.repeat(texture[...,None], 3, axis=2)
        original = cv2.GaussianBlur(restored, (0,0), 3)
        mask = np.ones((128,128), np.float32)
        sharpness = []
        for strength in (1,.5,.25):
            comp = FaceCompositor(SimpleNamespace(available=False), Masker(),
                CompositeConfig(temporal=True, relight=0, grain_match=0,
                                focus_match_strength=strength))
            out = comp._harmonize(restored, original, mask, mask, mask, 1, 512)
            sharpness.append(laplacian_var(out))
        self.assertLess(sharpness[0], sharpness[1])
        self.assertLess(sharpness[1], sharpness[2])
        self.assertLessEqual(sharpness[2], laplacian_var(restored))

    def test_higher_output_profiles_preserve_more_pixels_after_real_h264_encoding(self):
        from reface_config import output_defaults
        yy, xx = np.indices((128,160), dtype=np.float32)
        frames = []
        for shift in range(6):
            gray = np.clip(128 + 45*np.sin((xx+shift)/2) + 35*np.cos(yy/3), 0,255).astype(np.uint8)
            frames.append(np.repeat(gray[...,None], 3, axis=2))
        scores = []
        with tempfile.TemporaryDirectory() as tmp:
            for profile in ('fast','balanced','detail'):
                config = output_defaults(profile)
                engine = RefaceEngineV3.__new__(RefaceEngineV3)
                engine.video_crf, engine.video_preset = config['video_crf'], config['video_preset']
                output = Path(tmp)/(profile+'.mp4')
                writer, proc = engine._open_writer(output,30000/1001,160,128)
                try:
                    for frame in frames:
                        engine._write(writer,proc,frame)
                    engine._close_writer(writer,proc)
                finally:
                    engine._abort_writer(writer,proc)
                validate_video(output,len(frames),30000/1001)
                self.assertEqual(engine._video_encoding['codec'], 'libx264')
                cap = cv2.VideoCapture(str(output))
                try:
                    errors = []
                    for frame in frames:
                        ok, decoded = cap.read()
                        self.assertTrue(ok)
                        self.assertEqual(decoded.shape, frame.shape)
                        errors.append(np.mean((decoded.astype(np.float32)-frame)**2))
                    scores.append(float(np.mean(errors)))
                finally:
                    cap.release()
        self.assertGreater(scores[0], scores[1])
        self.assertGreater(scores[1], scores[2])

    def test_invalid_encoder_settings_fail_before_loading_any_models(self):
        for value in (-1,52,1.5,True):
            with self.subTest(crf=value), self.assertRaisesRegex(ValueError,'Video CRF'):
                RefaceEngineV3(video_crf=value)
        with self.assertRaisesRegex(ValueError,'encoder preset'):
            RefaceEngineV3(video_preset='unsupported')

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

    def test_frontal_burst_does_not_filter_a_real_side_reference(self):
        fs = Faceset('angles')
        for _ in range(8):
            fs.add_face(FaceData('',unit(1),(0,0,0),[],.9))
        fs.add_face(FaceData('',unit(1)*.65+unit(2)*np.sqrt(1-.65**2),(45,0,0),[],.8))
        fs.add_face(FaceData('',unit(3),(0,0,0),[],.75))
        rows, _ = select_identity_faces(fs)
        self.assertEqual([row[0].pose[0] for row in rows], [0,45])

    def test_benchmark_scores_visible_target_misses_and_bystander_swaps(self):
        from eval_reface import run_clip
        from test_reface_video_continuity import face as detected
        target = detected(0, (10,15,50,65))
        other = detected(1, (70,5,150,95))
        frames = [np.full((100,160,3), i+20, np.uint8) for i in range(5)]
        class Engine:
            def _detect(self, frame, embeddings=True):
                return [target, other]
            def _make_selector(self, indices, refs):
                return FaceSelector(refs, indices)
            def begin_video(self):
                pass
            def locate_clip(self, frames, selector):
                return ((f, [], 0, 0) for f in frames)
            def render_frame(self, frame, source, i, **kwargs):
                faces = [[target,other],[other],[],[other],[target,other]][i]
                self._track_ids = [int(np.argmax(f.embedding)) for f in faces]
                self._frame_outcomes = [dict(status='swapped',track_id=self._track_ids[0])] if faces else []
                return frame.copy(), len(self._frame_outcomes), faces
        judge = SimpleNamespace(faces=lambda f: [target,other], embed=lambda img,f: f.normed_embedding)
        labels = {i: [10/160,.15,50/160,.65] for i in range(5)}
        labels[3] = None
        result = run_clip(Engine(), object(), frames, judge, unit(0), target_boxes=labels, fps=25)
        self.assertEqual(result['score_coverage'], .5)
        self.assertEqual(result['longest_visible_gap_frames'], 2)
        self.assertEqual(result['longest_visible_gap_seconds'], .08)
        self.assertEqual(result['wrong_face_swaps'], 2)
        self.assertEqual(result['visible_target_frames'], 4)

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
        # the engine now prepares a face (models) and finishes it (CPU) separately; the fake keeps one body for both
        def prepare(original,crop,matrix,kps,**kwargs):
            return SimpleNamespace(args=(crop,matrix,kps),kwargs=kwargs)
        def finish(pre,result):
            return composite(result,*pre.args,**pre.kwargs)
        engine.compositor = SimpleNamespace(reset=lambda:None,begin_frame=lambda:None,config=SimpleNamespace(temporal=False),
                                            composite=composite,prepare=prepare,finish=finish,
                                            last_status='swapped',last_reason='',_log_once=lambda *a:None)
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

    def test_reface_diagnostics_reporting_integration(self):
        from reface_diagnostics import RefaceDiagnostics, FrameOutcome, FrameTiming
        diag = RefaceDiagnostics(fps=30.0)
        diag.record_timing(FrameTiming(frame_index=0, timestamp_sec=0.0, total_frame_ms=25.0))
        diag.record_outcome(FrameOutcome(frame_index=0, timestamp_sec=0.0, track_id=1, status="swapped"))
        diag.record_timing(FrameTiming(frame_index=1, timestamp_sec=0.033, total_frame_ms=22.0))
        diag.record_outcome(FrameOutcome(frame_index=1, timestamp_sec=0.033, track_id=1, status="skipped", reason="not_detected"))
        diag.finish()
        summary = diag.summarize()
        self.assertEqual(summary["total_frames"], 2)
        self.assertEqual(summary["swapped_count"], 1)
        self.assertEqual(summary["skipped_count"], 1)
        self.assertEqual(summary["gap_count"], 1)
        self.assertIn("not_detected", summary["reasons"])


if __name__ == '__main__':
    unittest.main(verbosity=2)
