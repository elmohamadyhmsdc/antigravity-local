"""Real image/video codecs, bounded output and native-process failure recovery; no GPU."""
import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

from mobile_api.media_decode import (DecoderProcess, ImageTooLarge, IsolatedCapture,
                                     MediaDecodeError, ffmpeg_exe, ffmpeg_frame,
                                     read_video_sample)


class MediaDecodeTests(unittest.TestCase):
    def test_video_native_diagnostics_are_captured_per_request(self):
        script = ("import os, sys\n"
                  "for i, line in enumerate(sys.stdin.buffer):\n"
                  "    if i == 0: os.write(2, b'[h264] Missing reference picture\\n' * 5000)\n"
                  "    print('AG_MEDIA_RESULT {}', flush=True)\n")
        decoder = DecoderProcess(command=[sys.executable, '-u', '-c', script],
                                 capture_diagnostics=True, timeout=5)
        try:
            self.assertTrue(decoder.request({'op': 'frame'})['codec_diagnostics'])
            self.assertFalse(decoder.request({'op': 'frame'})['codec_diagnostics'])
        finally:
            decoder.close()

    def test_diagnosed_frame_is_retried_before_delivering_pixels(self):
        decoder = Mock()
        decoder.close.side_effect = lambda: setattr(decoder, 'process', None)
        decoder.request.side_effect = [
            {'fps': 2, 'total': 5},
            {'pixels': 'AAAA', 'shape': [1, 1, 3], 'codec_diagnostics': True},
            {'fps': 3, 'total': 5},
            {'pixels': 'AQID', 'shape': [1, 1, 3]},
        ]
        with patch('mobile_api.media_decode.DecoderProcess', return_value=decoder):
            capture = IsolatedCapture('input.video')
        capture.set(cv2.CAP_PROP_POS_FRAMES, 2)
        ok, image = capture.read()
        self.assertTrue(ok)
        self.assertEqual(image.tolist(), [[[1, 2, 3]]])
        opened = decoder.request.call_args_list[2].args[0]
        self.assertTrue(opened['ffmpeg_only'])
        self.assertEqual(decoder.request.call_args.args[0]['seconds'], 1)

    def test_nearby_sample_advances_decoder_without_reseeking(self):
        cap = Mock()
        cap.get.return_value = 4
        cap.read.return_value = (True, 'pixels')
        self.assertEqual(read_video_sample(cap, 7), 'pixels')
        self.assertEqual(cap.grab.call_count, 3)
        cap.set.assert_not_called()
        self.assertEqual(read_video_sample(cap, 2), 'pixels')
        cap.set.assert_called_once_with(cv2.CAP_PROP_POS_FRAMES, 2)

    def test_strict_video_fallback_discards_output_from_failed_decode(self):
        with patch('mobile_api.media_decode.subprocess.run', return_value=
                   subprocess.CompletedProcess([], 1, stdout=b'incomplete pixels')) as run:
            self.assertIsNone(ffmpeg_frame('input.video', 1, 320))
        args = run.call_args.args[0]
        self.assertIn('-xerror', args)
        self.assertIn('explode', args)

        def concealed_error(args, **kwargs):
            kwargs['stderr'].write(b'[h264] co located POCs unavailable\n')
            return subprocess.CompletedProcess(args, 0, stdout=b'concealed pixels')

        with patch('mobile_api.media_decode.subprocess.run', side_effect=concealed_error):
            self.assertIsNone(ffmpeg_frame('input.video', 1, 320))

    def test_image_transfer_avoids_base64_and_cleans_scratch_files(self):
        data = io.BytesIO()
        Image.new('RGB', (1024, 768), (210, 40, 20)).save(data, 'PNG')
        decoder = DecoderProcess()
        try:
            with patch('mobile_api.media_decode.base64.b64encode', side_effect=AssertionError('large base64 copy')), patch.object(decoder, 'request', wraps=decoder.request) as request:
                frame = decoder.image(data.getvalue(), 4096)
            self.assertEqual(frame.shape, (768, 1024, 3))
            payload = request.call_args.args[0]
            self.assertNotIn('encoded_image', payload)
            self.assertFalse(Path(payload['path']).exists())
            self.assertFalse(Path(payload['pixels_path']).exists())
        finally:
            decoder.close()

    def test_worker_memory_pressure_is_not_misreported_as_bad_image(self):
        script = "import sys; sys.stdin.buffer.readline(); print('AG_MEDIA_RESULT {\"out_of_memory\":true}', flush=True)"
        decoder = DecoderProcess(command=[sys.executable, '-u', '-c', script])
        try:
            with self.assertRaises(MemoryError):
                decoder.image(b'test', 4096)
        finally:
            decoder.close()

    def test_phone_and_animated_image_formats(self):
        try:
            import pillow_heif
            pillow_heif.register_heif_opener()
        except ImportError:
            self.fail('Install requirements_mobile_api.txt to enable HEIC/HEIF decoding.')
        decoder = DecoderProcess()
        try:
            for format in ('JPEG', 'PNG', 'BMP', 'TIFF', 'GIF', 'WEBP', 'AVIF', 'HEIF'):
                with self.subTest(format=format):
                    data = io.BytesIO()
                    Image.new('RGB', (640, 480), (210, 40, 20)).save(data, format=format)
                    frame = decoder.image(data.getvalue(), 4096)
                    self.assertEqual(frame.shape, (480, 640, 3))
                    self.assertGreater(int(frame[240, 320, 2]), int(frame[240, 320, 0]) + 100)
        finally:
            decoder.close()

    def test_exif_orientation_size_limits_and_recovery_after_bad_image(self):
        data = io.BytesIO()
        exif = Image.Exif()
        exif[274] = 6
        Image.new('RGB', (640, 480)).save(data, 'JPEG', exif=exif)
        decoder = DecoderProcess()
        try:
            self.assertEqual(decoder.image(data.getvalue(), 4096).shape, (640, 480, 3))
            with self.assertRaises(ImageTooLarge):
                decoder.image(data.getvalue(), 500)
            with self.assertRaises(MediaDecodeError):
                decoder.image(b'not an image', 4096)
            self.assertEqual(decoder.image(data.getvalue(), 4096).shape, (640, 480, 3))
        finally:
            decoder.close()

    def test_native_decoder_exit_and_timeout_are_contained(self):
        for script in ('import os; os._exit(23)', 'import time; time.sleep(30)'):
            with self.subTest(script=script):
                decoder = DecoderProcess(command=[sys.executable, '-c', script], timeout=0.2)
                with self.assertRaises(MediaDecodeError):
                    decoder.image(b'test', 4096)
                self.assertIsNone(decoder.process)

    def test_decoder_that_never_reads_a_large_upload_cannot_block_the_api_thread(self):
        decoder = DecoderProcess(command=[sys.executable, '-c', 'import time; time.sleep(30)'], timeout=0.2)
        with self.assertRaises(MediaDecodeError):
            decoder.image(b'x' * (8 * 1024 * 1024), 4096)
        self.assertIsNone(decoder.process)

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'Local FFmpeg/ffprobe required')
    def test_h264_missing_keyframe_does_not_poison_later_samples(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'damaged.mp4'
            subprocess.run([ffmpeg_exe(), '-hide_banner', '-loglevel', 'error',
                '-f', 'lavfi', '-i', 'testsrc2=s=160x96:r=12:d=3', '-c:v', 'libx264',
                '-g', '12', '-keyint_min', '12', '-sc_threshold', '0', '-threads', '2',
                str(path)], check=True, capture_output=True, timeout=30)
            probe = subprocess.run([shutil.which('ffprobe'), '-v', 'error', '-select_streams', 'v:0',
                '-show_entries', 'packet=pos,size,flags', '-of', 'json', str(path)],
                check=True, capture_output=True, timeout=15)
            first = json.loads(probe.stdout)['packets'][0]
            self.assertIn('K', first['flags'])
            with path.open('r+b') as damaged:
                damaged.seek(int(first['pos']))
                damaged.write(bytes(int(first['size'])))
            capture = IsolatedCapture(path)
            try:
                self.assertEqual(capture.read(), (False, None))
                capture.set(cv2.CAP_PROP_POS_FRAMES, 24)
                ok, frame = capture.read()
                self.assertTrue(ok)
                self.assertEqual(frame.shape, (96, 160, 3))
            finally:
                capture.release()

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'Local FFmpeg/ffprobe required')
    def test_video_containers_and_ffmpeg_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            for extension, codec in (('mp4', 'libx264'), ('mkv', 'libx265'), ('webm', 'libvpx-vp9')):
                with self.subTest(codec=codec):
                    path = Path(tmp) / ('sample.' + extension)
                    result = subprocess.run([ffmpeg_exe(), '-hide_banner', '-loglevel', 'error',
                        '-f', 'lavfi', '-i', 'color=c=red:s=640x480:r=2:d=3', '-c:v', codec,
                        '-threads', '2', '-pix_fmt', 'yuv420p', str(path)],
                        capture_output=True, timeout=30)
                    self.assertEqual(result.returncode, 0, result.stderr[-1000:])
                    # Production inputs deliberately have no format extension.
                    target = path.with_name('input.video')
                    shutil.copyfile(path, target)
                    capture = IsolatedCapture(target, max_side=320)
                    try:
                        self.assertAlmostEqual(capture.get(cv2.CAP_PROP_FPS), 2)
                        for fallback in (False, True):
                            if fallback:
                                capture.decoder.close()
                                capture.ffmpeg_only = True
                            capture.set(cv2.CAP_PROP_POS_FRAMES, 2)
                            ok, frame = capture.read()
                            self.assertTrue(ok, 'FFmpeg fallback' if fallback else 'OpenCV worker')
                            self.assertLessEqual(max(frame.shape[:2]), 320)
                            self.assertGreater(int(frame[50, 50, 2]), 200)
                    finally:
                        capture.release()


if __name__ == '__main__':
    unittest.main(verbosity=2)
