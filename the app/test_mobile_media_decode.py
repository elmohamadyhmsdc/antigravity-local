"""Real image/video codecs, bounded output and native-process failure recovery; no GPU."""
import io
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

from mobile_api.media_decode import (DecoderProcess, ImageTooLarge, IsolatedCapture,
                                     MediaDecodeError, ffmpeg_exe)


class MediaDecodeTests(unittest.TestCase):
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
