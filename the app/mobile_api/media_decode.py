"""Disposable media decoder. Native codec failures must never take down the API.

OpenCV handles the fast video path; Pillow and local FFmpeg provide additional codecs.
Only bounded BGR pixels cross the pipe. No decoded originals are retained on disk.
"""
import base64
import io
import json
import math
import os
import queue
import shutil
import subprocess
import sys
import threading
from pathlib import Path

import cv2
import numpy as np

from . import APP_DIR

PREFIX = 'AG_MEDIA_RESULT '
MAX_MESSAGE = 96 * 1024 * 1024


class MediaDecodeError(ValueError):
    pass


class ImageTooLarge(MediaDecodeError):
    pass


class DecoderProcess:
    def __init__(self, *, timeout=60, command=None):
        self.timeout = timeout
        self.command = command or [sys.executable, '-u', '-X', 'faulthandler', '-m', 'mobile_api.media_decode']
        self.process = None
        self.lock = threading.RLock()

    def request(self, request):
        with self.lock:
            if self.process is None:
                responses = queue.Queue(maxsize=2)
                process = subprocess.Popen(self.command, cwd=APP_DIR, stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE, stderr=None,
                    env=dict(os.environ, PYTHONIOENCODING='utf-8', OPENCV_FFMPEG_THREADS='2'),
                    creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
                self.process = process
                self.responses = responses

                def read():
                    try:
                        for line in iter(lambda: process.stdout.readline(MAX_MESSAGE + 1), b''):
                            if len(line) > MAX_MESSAGE:
                                break
                            if line.startswith(PREFIX.encode()):
                                responses.put(line[len(PREFIX):])
                    finally:
                        responses.put(None)
                threading.Thread(target=read, name='media-decoder-output', daemon=True).start()
            try:
                message = json.dumps(request, separators=(',', ':')).encode() + b'\n'
                process = self.process
                sent = queue.Queue(maxsize=1)
                def write():
                    try:
                        process.stdin.write(message)
                        process.stdin.flush()
                        sent.put(None)
                    except (OSError, ValueError) as error:
                        sent.put(error)
                # A crashed/hung decoder may not drain a large image request.
                # Bound pipe writes as well as reads so it cannot wedge an API thread.
                threading.Thread(target=write, name='media-decoder-input', daemon=True).start()
                error = sent.get(timeout=self.timeout)
                if error is not None:
                    raise error
                raw = self.responses.get(timeout=self.timeout)
                if raw is None:
                    raise MediaDecodeError('The media decoder stopped while reading this file.')
                response = json.loads(raw)
                if response.get('error'):
                    error = ImageTooLarge if response.get('too_large') else MediaDecodeError
                    raise error(response['error'])
                return response
            except (OSError, ValueError, queue.Empty) as error:
                self.close()
                if isinstance(error, MediaDecodeError):
                    raise
                raise MediaDecodeError('The media decoder could not read this file in time.') from error

    def image(self, data, max_side):
        result = self.request({'op': 'image', 'encoded_image': base64.b64encode(data).decode(), 'max_side': max_side})
        return unpack_image(result)

    def close(self):
        with self.lock:
            process, self.process = self.process, None
            if process is None:
                return
            # Terminate before closing stdin: a codec may have stopped reading the pipe.
            if process.poll() is None:
                process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
            process.stdin.close()
            process.stdout.close()


def unpack_image(result):
    shape = result['shape']
    if len(shape) != 3 or shape[2] != 3 or not 0 < min(shape) <= max(shape) <= 4096:
        raise MediaDecodeError('Invalid decoded image dimensions.')
    return np.frombuffer(base64.b64decode(result['pixels'], validate=True), np.uint8).reshape(shape).copy()


class IsolatedCapture:
    """The small VideoCapture interface used by VideoJobs, backed by a child process."""
    def __init__(self, path, max_side=4096):
        self.path, self.max_side, self.position = str(path), max_side, 0
        self.decoder = DecoderProcess()
        self.ffmpeg_only = False
        try:
            self.info = self._open()
        except MediaDecodeError:
            self.ffmpeg_only = True
            self.info = self._open()

    def _open(self):
        return self.decoder.request({'op': 'open', 'path': self.path,
            'max_side': self.max_side, 'ffmpeg_only': self.ffmpeg_only})

    def isOpened(self):
        return True

    def get(self, prop):
        return self.info['fps'] if prop == cv2.CAP_PROP_FPS else self.info['total']

    def set(self, prop, value):
        self.position = int(value)

    def read(self):
        try:
            if self.decoder.process is None:
                self._open()
            result = self.decoder.request({'op': 'frame', 'frame': self.position})
            return (False, None) if 'pixels' not in result else (True, unpack_image(result))
        except MediaDecodeError:
            if not self.ffmpeg_only:
                self.ffmpeg_only = True
                return self.read()
            return False, None

    def release(self):
        self.decoder.close()


def ffmpeg_exe():
    # Prefer the installed build with current codecs over the older DeepFaceLab bundle.
    from ffmpeg_utils import _ffmpeg_exe
    return _ffmpeg_exe() if os.environ.get('ANTIGRAVITY_FFMPEG') else shutil.which('ffmpeg') or _ffmpeg_exe()


def ffmpeg_frame(path, seconds, max_side, *, data=None):
    args = [ffmpeg_exe(), '-hide_banner', '-loglevel', 'error', '-nostdin', '-threads', '2',
            '-protocol_whitelist', 'file,pipe', '-err_detect', 'ignore_err']
    if data is None:
        args += ['-ss', str(seconds)]
    args += ['-i', str(path), '-map', '0:v:0', '-frames:v', '1', '-an', '-sn',
             '-vf', f'scale=w=min({max_side}\\,iw):h=min({max_side}\\,ih):force_original_aspect_ratio=decrease',
             '-threads', '1', '-f', 'image2pipe', '-c:v', 'png', 'pipe:1']
    try:
        result = subprocess.run(args, input=data, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                timeout=30, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        if result.stdout:
            return cv2.imdecode(np.frombuffer(result.stdout, np.uint8), cv2.IMREAD_COLOR)
    except (OSError, subprocess.SubprocessError):
        pass
    return None


def decode_image(data, max_side):
    from PIL import Image, ImageOps, UnidentifiedImageError
    try:
        import pillow_heif
        pillow_heif.register_heif_opener()
    except ImportError:
        pass
    try:
        with Image.open(io.BytesIO(data)) as image:
            if max(image.size) > max_side:
                raise ImageTooLarge(f'The image is {image.width}x{image.height}; the longest side may be {max_side}px.')
            # First frame/page for animated GIF/WebP, TIFF and AVIF; honour phone EXIF rotation.
            rgb = ImageOps.exif_transpose(image).convert('RGB')
            return np.asarray(rgb)[:, :, ::-1].copy()
    except (UnidentifiedImageError, OSError, ValueError) as error:
        if isinstance(error, ImageTooLarge):
            raise
    image = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR) if data else None
    if image is None:
        image = ffmpeg_frame('pipe:0', 0, max_side, data=data)
    if image is None:
        raise MediaDecodeError('This image is corrupt or its codec is unavailable on the PC.')
    if max(image.shape[:2]) > max_side:
        raise ImageTooLarge(f'The longest image side may be {max_side}px.')
    return image


def probe_video(path):
    probe = Path(ffmpeg_exe()).with_name('ffprobe.exe' if os.name == 'nt' else 'ffprobe')
    executable = str(probe) if probe.is_file() else shutil.which('ffprobe')
    if not executable:
        return None
    try:
        result = subprocess.run([executable, '-v', 'error', '-protocol_whitelist', 'file,pipe',
            '-select_streams', 'v:0', '-show_entries',
            'stream=avg_frame_rate,r_frame_rate,nb_frames,duration:format=duration', '-of', 'json', str(path)],
            capture_output=True, timeout=15, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        info = json.loads(result.stdout)
        stream = info['streams'][0]
        for rate in (stream.get('avg_frame_rate'), stream.get('r_frame_rate')):
            try:
                numerator, denominator = rate.split('/')
                fps = float(numerator) / float(denominator)
                if math.isfinite(fps) and 0 < fps <= 1000:
                    break
            except (AttributeError, ValueError, ZeroDivisionError):
                continue
        else:
            return None
        try:
            total = int(stream['nb_frames'])
        except (KeyError, ValueError, TypeError):
            total = math.ceil(float(stream.get('duration') or info.get('format', {}).get('duration')) * fps)
        return (fps, total) if total > 0 else None
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, IndexError, TypeError, OverflowError):
        return None


def main():
    import faulthandler
    faulthandler.enable(all_threads=True)
    cv2.setNumThreads(1)
    cap, path, fps, max_side = None, None, None, 4096
    try:
        for raw in sys.stdin.buffer:
            try:
                if len(raw) > MAX_MESSAGE:
                    raise MediaDecodeError('The media request is too large.')
                request = json.loads(raw)
                op = request['op']
                if op == 'open':
                    if cap is not None:
                        cap.release()
                    path, max_side = request['path'], request['max_side']
                    cap = None if request.get('ffmpeg_only') else cv2.VideoCapture(
                        path, cv2.CAP_FFMPEG, [cv2.CAP_PROP_N_THREADS, 2])
                    fps = float(cap.get(cv2.CAP_PROP_FPS)) if cap is not None else 0
                    count = float(cap.get(cv2.CAP_PROP_FRAME_COUNT)) if cap is not None else 0
                    if cap is None or not cap.isOpened() or not math.isfinite(fps) or not 0 < fps <= 1000 or not math.isfinite(count) or count <= 0:
                        metadata = probe_video(path)
                        if metadata is None:
                            raise MediaDecodeError('The video could not be opened. Its codec may be unavailable or the file may be damaged.')
                        fps, count = metadata
                    response = {'fps': fps, 'total': int(count)}
                else:
                    if op == 'image':
                        image = decode_image(base64.b64decode(request['encoded_image'], validate=True), request['max_side'])
                    elif op == 'frame':
                        frame = request['frame']
                        image = None
                        if cap is not None and cap.isOpened():
                            if cap.set(cv2.CAP_PROP_POS_FRAMES, frame):
                                ok, image = cap.read()
                                if not ok:
                                    image = None
                        if image is None:
                            image = ffmpeg_frame(path, frame / fps, max_side)
                        if image is not None and max(image.shape[:2]) > max_side:
                            scale = max_side / max(image.shape[:2])
                            image = cv2.resize(image, (max(1, round(image.shape[1] * scale)), max(1, round(image.shape[0] * scale))))
                    else:
                        raise MediaDecodeError('Unknown media operation.')
                    response = {} if image is None else {'shape': list(image.shape),
                        'pixels': base64.b64encode(np.ascontiguousarray(image)).decode()}
            except Exception as error:
                response = {'error': str(error), 'too_large': isinstance(error, ImageTooLarge)}
            sys.stdout.write(PREFIX + json.dumps(response, separators=(',', ':')) + '\n')
            sys.stdout.flush()
    finally:
        if cap is not None:
            cap.release()


if __name__ == '__main__':
    main()
