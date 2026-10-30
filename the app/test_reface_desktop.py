"""Synthetic desktop routing/UI/worker regressions. No gallery or inference models."""
import ast
import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

import cv2
import numpy as np

from job_manager import Job, JobManager, JobStatus, run_single_job
from reface_desktop import gallery_faceset, selected_targets, select_target, stage_target_upload, target_files


def embedding(index=0):
    value = np.zeros(512, np.float32)
    value[index] = 1
    return value.tolist()


class DesktopAdaptersTests(unittest.TestCase):
    def test_gallery_reuses_saved_identity_without_detection_or_image_files(self):
        faceset = gallery_faceset('synthetic', [
            dict(embedding=embedding(), quality_score=.8, pose=[1, 2, 3]),
            dict(embedding=[0] * 512), dict(embedding=[float('nan')] * 512),
            dict(embedding=[1, 2]), dict(embedding=None),
        ])
        self.assertEqual(len(faceset.faces), 1)
        self.assertEqual(faceset.faces[0].pose, (1, 2, 3))
        np.testing.assert_array_equal(faceset.faces[0].embedding, embedding())

    def test_all_faces_ignores_old_ticks_and_selected_people_keep_bystander_references(self):
        state = dict(reface_replace_all=True, v2_selected_target_faces=[0],
                     v2_detected_faces=[dict(embedding=embedding()), dict(embedding=embedding(1))])
        self.assertEqual(selected_targets(state), (None, None))
        state['reface_replace_all'] = False
        selected, refs = selected_targets(state)
        self.assertEqual(selected, [0])
        self.assertEqual(refs, [embedding(), embedding(1)])
        for bad in ([], [None, None], [[1, 2], embedding(1)]):
            state['v2_detected_faces'] = [dict(embedding=value) for value in bad]
            with self.assertRaises(ValueError):
                selected_targets(state)
        state['v2_selected_target_faces'] = []
        with self.assertRaises(ValueError):
            selected_targets(state)

    def test_upload_reruns_reuse_bytes_and_same_name_replacement_invalidates_faces(self):
        with tempfile.TemporaryDirectory() as tmp:
            upload = SimpleNamespace(name='same.mp4', file_id='first', getbuffer=Mock(return_value=b'video one'))
            state = {}
            path = stage_target_upload(state, upload, tmp)
            state.update(v2_selected_target_faces=[0], v2_detected_faces=[dict(embedding=embedding())], v2_target_face_0=True)
            stage_target_upload(state, upload, tmp)
            upload.getbuffer.assert_called_once()
            self.assertEqual(state['v2_selected_target_faces'], [0])
            upload.file_id = 'second'
            upload.getbuffer.return_value = b'video two'
            stage_target_upload(state, upload, tmp)
            self.assertEqual(path.read_bytes(), b'video two')
            self.assertEqual(state['v2_detected_faces'], [])
            self.assertNotIn('v2_target_face_0', state)
            select_target(state, Path(tmp) / 'photo.png')
            self.assertFalse(state['v2_is_video'])

    def test_configured_folder_targets_keep_recursion_and_duplicate_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'nested').mkdir()
            (root / 'same.png').write_bytes(b'one')
            (root / 'nested' / 'same.png').write_bytes(b'two')
            (root / 'ignore.txt').write_text('ignore')
            self.assertEqual(len(target_files([dict(path=tmp, include_subfolders=False)])), 1)
            self.assertEqual(len(target_files([dict(path=tmp), dict(path=tmp)])), 2)


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.manager = JobManager(str(self.root / 'jobs'))
        self.source = SimpleNamespace(faces=[object()])
        self.output = self.root / 'part.mp4'
        self.output.write_bytes(b'synthetic rendered part')
        self.engine = SimpleNamespace(app=object(), load_faceset_by_name=Mock(return_value=self.source))
        self.engine.reface_image = Mock(side_effect=self.image)
        self.engine.reface_video = Mock(side_effect=self.video)
        self.engine.reface_with_faceset = Mock(side_effect=self.image)
        self.engine.reface_with_faceset_v2 = Mock(side_effect=self.image)
        self.engine.reface_image_v3 = Mock(side_effect=self.image)
        for name in ('reface.RefaceEngine', 'reface_engine.RefaceEngine', 'reface_engine_v2.RefaceEngineV2', 'reface_engine_v3.RefaceEngineV3'):
            patcher = patch(name, return_value=self.engine)
            setattr(self, name.split('.')[0], patcher.start())
            self.addCleanup(patcher.stop)
        self.finalize = patch('job_manager.finish_v3_video', side_effect=self.finish).start()
        self.addCleanup(patch.stopall)

    def result(self):
        return SimpleNamespace(success=True, output_path=str(self.output), message='Rendered',
                               details=dict(faces_swapped=3, settings=dict(engine='reface')))

    def image(self, *args, **kwargs):
        return self.result()

    def video(self, *args, **kwargs):
        kwargs['progress_callback'](3, 3)
        return self.result()

    def finish(self, job, part, count, *args):
        job.frames_done += count
        return self.root / 'final.mp4'

    def create(self, kind='reface_image', **params):
        job = Job(id='synthetic', job_type=kind, status=JobStatus.QUEUED, progress=0,
                  message='', created_at='2026-10-30', params=dict(
                      target_path=str(self.root / 'target.png'), faceset_name='synthetic', **params))
        self.manager.save_job(job)
        return job

    def run_job(self, job):
        with contextlib.redirect_stdout(io.StringIO()):
            completed = run_single_job(job.id, str(self.manager.jobs_dir))
        return completed, self.manager.load_job(job.id)

    def test_profiles_use_public_photo_method_and_pass_identity_references(self):
        for profile in ('fast', 'balanced', 'detail'):
            with self.subTest(profile=profile):
                job = self.create(quality_profile=profile, target_face_indices=[0],
                                  target_face_embeddings=[embedding(), embedding(1)])
                done, stored = self.run_job(job)
                self.assertTrue(done, stored.error)
                self.assertEqual(stored.status, JobStatus.COMPLETED)
                self.assertEqual(self.reface.call_args.kwargs['quality_profile'], profile)
                self.assertIsNone(self.reface.call_args.kwargs['use_parser'])
                self.assertEqual(self.engine.reface_image.call_args.kwargs['target_face_embeddings'], [embedding(), embedding(1)])
                self.reface_engine.assert_not_called()
                self.reface_engine_v2.assert_not_called()
                self.reface_engine_v3.assert_not_called()

    def test_video_pause_resume_keeps_counts_selection_trim_and_public_method(self):
        job = self.create('reface_video', quality_profile='fast', is_video=True,
                          target_face_indices=None, target_face_embeddings=None, start_time=1.25, end_time=8.5)
        self.manager.request_stop(job.id)
        done, paused = self.run_job(job)
        self.assertFalse(done)
        self.assertEqual(paused.status, JobStatus.PAUSED)
        self.assertEqual(paused.frames_done, 3)
        self.assertEqual(paused.details['faces_swapped'], 3)
        self.assertEqual(paused.part_files, [str(self.output)])
        self.finalize.assert_not_called()
        self.manager.resume_job(job.id)
        done, complete = self.run_job(job)
        self.assertTrue(done, complete.error)
        self.assertEqual(complete.frames_done, 6)
        self.assertEqual(complete.details['faces_swapped'], 6)
        kwargs = self.engine.reface_video.call_args.kwargs
        self.assertEqual(kwargs['resume_from_frame'], 3)
        self.assertEqual((kwargs['start_time'], kwargs['end_time']), (1.25, 8.5))
        self.assertIsNone(kwargs['target_face_indices'])
        self.assertFalse(kwargs['finalize'])
        self.finalize.assert_called_once()

    def test_saved_v1_v2_v3_jobs_keep_their_original_engine(self):
        for kind, constructor, method in (
            ('reface_image', self.reface_engine, self.engine.reface_with_faceset),
            ('reface_image_v2', self.reface_engine_v2, self.engine.reface_with_faceset_v2),
            ('reface_image_v3', self.reface_engine_v3, self.engine.reface_image_v3),
        ):
            with self.subTest(kind=kind):
                done, stored = self.run_job(self.create(kind))
                self.assertTrue(done, stored.error)
                constructor.assert_called_once()
                method.assert_called_once()
                self.reface.assert_not_called()

    def test_new_trained_identity_uses_public_engine_without_source_faceset(self):
        job = self.create(quality_profile='balanced', dfm_path='synthetic.dfm')
        del job.params['faceset_name']
        self.manager.save_job(job)
        done, stored = self.run_job(job)
        self.assertTrue(done, stored.error)
        self.assertEqual(self.reface.call_args.kwargs['dfm_path'], 'synthetic.dfm')
        self.engine.load_faceset_by_name.assert_not_called()
        self.assertIsNone(self.engine.reface_image.call_args.args[1])


class DesktopUITests(unittest.TestCase):
    def setUp(self):
        from streamlit.testing.v1 import AppTest
        from face_restore import RESTORER_FILES
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = gallery_faceset('synthetic', [dict(embedding=embedding())])
        (self.root / 'facesets').mkdir()
        self.source.save(self.root / 'facesets' / 'synthetic.pkl')
        self.output = self.root / 'result.png'
        cv2.imwrite(str(self.output), np.zeros((32, 32, 3), np.uint8))
        for name in ('codeformer', 'gpen_bfr_512', 'gpen_bfr_1024'):
            (self.root / RESTORER_FILES[name]).write_bytes(b'metadata only; not an inference model')
        for name, value in (
            ('face_restore.MODELS_DIR', self.root),
            ('face_swappers.available_swappers', Mock(return_value=['inswapper_128'])),
            ('identity_builder.list_identities', Mock(return_value=[])),
            ('dfl_bridge.available', Mock(return_value=None)),
            ('dfl_bridge.dfm_for', Mock(return_value=None)),
        ):
            patcher = patch(name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.created, self.queued = [], []

        def create_engine(**kwargs):
            engine = SimpleNamespace(load_faceset_by_name=lambda name: self.source)
            result = SimpleNamespace(success=True, output_path=str(self.output), message='Synthetic result', details={})
            engine.reface_image = Mock(return_value=result)
            engine.reface_video = Mock(return_value=result)
            self.created.append((kwargs, engine))
            return engine

        def queue(kind, params):
            self.queued.append((kind, params))
            return SimpleNamespace(id='synthetic')

        for name, value in (('reface.RefaceEngine', create_engine), ('job_manager.add_job_to_queue', queue)):
            patcher = patch(name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        # Render the real page with a temporary application directory and synthetic
        # gallery fixtures. Never import dashboard.py (its top level opens the DB).
        tree = ast.parse(Path(__file__).with_name('dashboard.py').read_text(encoding='utf-8'))
        branch = next(node for node in ast.walk(tree) if isinstance(node, ast.If)
                      and isinstance(node.test, ast.Compare) and isinstance(node.test.left, ast.Name)
                      and node.test.left.id == 'page' and isinstance(node.test.comparators[0], ast.Constant)
                      and node.test.comparators[0].value == '🎭 Reface')
        eta = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == 'ETACalculator')
        prelude = f'''import os, time, json, io, zipfile, shutil, subprocess
from pathlib import Path
from datetime import datetime
import streamlit as st
import numpy as np
from reface_desktop import gallery_faceset
def get_all_persons():
    return [dict(id=7, name="Synthetic person", face_count=1)]
def get_faces_for_person(person_id):
    return [dict(embedding={embedding()!r})]
st.session_state.setdefault("data_sources", [])
'''
        harness = self.root / 'harness.py'
        harness.write_text(prelude + ast.unparse(eta) + '\n' + '\n'.join(ast.unparse(node) for node in branch.body), encoding='utf-8')
        self.at = AppTest.from_file(str(harness), default_timeout=30).run()
        self.assertFalse(self.at.exception)

    def test_all_profiles_use_identical_options_for_direct_and_queued_photo_and_video(self):
        at = self.at
        at.radio(key='v2_source_mode').set_value('📦 Use Faceset').run()
        at.button(key='v2_use_faceset').click().run()
        for is_video in (False, True):
            at.session_state['v2_target_path'] = str(self.output)
            at.session_state['v2_is_video'] = is_video
            at.run()
            self.assertTrue(at.checkbox(key='reface_replace_all').value)
            for profile in ('fast', 'balanced', 'detail'):
                with self.subTest(video=is_video, profile=profile):
                    at.selectbox(key='reface_quality_profile').set_value(profile).run()
                    expected = dict(fast='none', balanced='gpen_bfr_512', detail='gpen_bfr_1024')[profile]
                    self.assertTrue(any(f'Automatic starts with {expected}' in item.value for item in at.caption))
                    next(widget for widget in at.checkbox if widget.label == '🔄 Run in Background').set_value(False).run()
                    next(button for button in at.button if button.label == '🚀 Process Reface').click().run()
                    self.assertFalse(at.exception)
                    self.assertFalse(at.error, [item.value for item in at.error])
                    options, engine = self.created[-1]
                    self.assertEqual(options['quality_profile'], profile)
                    self.assertEqual(options['use_parser'], profile != 'fast')
                    render = engine.reface_video if is_video else engine.reface_image
                    self.assertIsNone(render.call_args.kwargs['target_face_indices'])
                    self.assertIsNone(render.call_args.kwargs['target_face_embeddings'])
                    next(widget for widget in at.checkbox if widget.label == '🔄 Run in Background').set_value(True).run()
                    next(button for button in at.button if button.label == '🚀 Process Reface').click().run()
                    self.assertFalse(at.exception)
                    kind, params = self.queued[-1]
                    self.assertEqual(kind, 'reface_video' if is_video else 'reface_image')
                    self.assertEqual({key: params[key] for key in options}, options)
                    self.assertIsNone(params['target_face_indices'])
        self.assertEqual((len(self.created), len(self.queued)), (6, 6))

    def test_gallery_source_and_combined_history_survive_reruns(self):
        at = self.at
        at.radio(key='v2_source_mode').set_value('👥 Gallery Person').run()
        at.button(key='reface_use_gallery_person').click().run()
        self.assertFalse(at.exception)
        self.assertEqual(at.session_state['v2_selected_faceset'], 'gallery_person_7')
        self.assertTrue((self.root / 'facesets' / 'gallery_person_7.pkl').is_file())
        output_dir = self.root / 'reface_output'
        for prefix in ('refaced_', 'refaced_v2_', 'refaced_v3_'):
            for index in range(5):
                (output_dir / f'{prefix}{index}.png').write_bytes(self.output.read_bytes())
        at.run()
        first = [item.value for item in at.caption if item.value.startswith('📁 ')]
        self.assertEqual(len(first), 12)
        at.selectbox(key='reface_results_page').set_value(2).run()
        second = [item.value for item in at.caption if item.value.startswith('📁 ')]
        self.assertEqual(len(set(first + second)), 15)
        self.assertFalse(at.exception)
        self.assertFalse(self.created)

    def test_selected_face_mode_requires_selection_and_forwards_all_references(self):
        at = self.at
        at.radio(key='v2_source_mode').set_value('📦 Use Faceset').run()
        at.button(key='v2_use_faceset').click().run()
        at.session_state['v2_target_path'] = str(self.output)
        at.session_state['v2_is_video'] = False
        at.run()
        at.checkbox(key='reface_replace_all').set_value(False).run()
        self.assertTrue(next(button for button in at.button if button.label == '🚀 Process Reface').disabled)
        at.session_state['v2_detected_faces'] = [
            dict(index=index, crop_path=str(self.output), embedding=embedding(index)) for index in range(2)]
        at.session_state['v2_selected_target_faces'] = [0]
        at.run()
        next(button for button in at.button if button.label == '🚀 Process Reface').click().run()
        self.assertFalse(at.exception)
        self.assertFalse(at.error)
        kwargs = self.created[-1][1].reface_image.call_args.kwargs
        self.assertEqual(kwargs['target_face_indices'], [0])
        self.assertEqual(kwargs['target_face_embeddings'], [embedding(), embedding(1)])


if __name__ == '__main__':
    unittest.main(verbosity=2)
