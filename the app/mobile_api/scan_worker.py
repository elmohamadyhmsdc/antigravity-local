"""Persistent, disposable inference process. Local JSON IPC; no executable serialization.

A native ONNX/CUDA access violation must not terminate the API, pairing, or device controls.
Pixels cross an anonymous pipe and are never written to a file by this worker.
"""
import base64
import json
import os
import queue
import subprocess
import sys
import threading
from dataclasses import asdict
from types import SimpleNamespace

import numpy as np

from analysis import FrameAnalysis
from . import APP_DIR
from .errors import ApiError

PREFIX = 'AG_SCAN_RESULT '
MAX_MESSAGE = 96 * 1024 * 1024


def encode_result(result):
    from .schemas import py
    return py(dict(faces=[dict(bbox=f.bbox, kps=f.kps, det_score=f.det_score,
                               normed_embedding=f.normed_embedding) for f in result.faces],
        quality=result.quality, passes_gate=result.passes_gate,
        bodies=[dict(bbox=b.bbox, score=b.score, kpts=b.kpts, kpt_scores=b.kpt_scores) for b in result.bodies],
        appearances=result.appearances, pairs=result.pairs, image_w=result.image_w,
        image_h=result.image_h, timings_ms=result.timings_ms,
        characters=[dict(bbox=c.bbox, score=c.score, descriptor=c.descriptor, model_id=c.model_id)
                    for c in result.characters]))


def decode_result(value):
    for face in value['faces']:
        for key in ('bbox', 'kps', 'normed_embedding'):
            face[key] = np.asarray(face[key], dtype=np.float32)
    for body in value['bodies']:
        for key in ('bbox', 'kpts', 'kpt_scores'):
            if body[key] is not None: body[key] = np.asarray(body[key], dtype=np.float32)
    value['faces'] = [SimpleNamespace(**f) for f in value['faces']]
    value['bodies'] = [SimpleNamespace(**b) for b in value['bodies']]
    from character_detection import Character
    value['characters'] = [Character(np.asarray(c['bbox'], np.float32), c['score'],
                                     np.asarray(c['descriptor'], np.float32), c['model_id'])
                           for c in value.get('characters', [])]
    return FrameAnalysis(**value)


class ScanWorker:
    def __init__(self, log=print, *, command=None, timeout=180):
        self.log, self.timeout = log, timeout
        self.command = command or [sys.executable, '-u', '-X', 'faulthandler', '-m', 'mobile_api.scan_worker']
        self.process = None
        self._lock = threading.RLock()

    @property
    def loaded(self):
        return self.process is not None and self.process.poll() is None

    def _start(self):
        if self.loaded: return
        self.close()
        responses = queue.Queue()
        process = subprocess.Popen(self.command, cwd=APP_DIR, stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=None,
            env=dict(os.environ, PYTHONIOENCODING='utf-8', PYTHONFAULTHANDLER='1',
                     HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1'),
            creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        self.process, self.responses = process, responses
        def read():
            try:
                while line := process.stdout.readline(MAX_MESSAGE + 1):
                    if len(line) > MAX_MESSAGE: break
                    text = line.decode('utf-8', errors='replace').rstrip()
                    if text.startswith(PREFIX): responses.put(text[len(PREFIX):])
                    elif text: self.log('[scan worker] '+text)
            finally:
                responses.put(None)
        threading.Thread(target=read, name='scan-worker-output', daemon=True).start()
        self.log(f'[scan worker] started pid={process.pid}')

    def analyze(self, img, options):
        with self._lock:
            self._start()
            message = json.dumps({'shape': list(img.shape),
                'pixels': base64.b64encode(np.ascontiguousarray(img, dtype=np.uint8)).decode('ascii'),
                'options': asdict(options)}, separators=(',', ':')).encode('utf-8') + b'\n'
            try:
                self.process.stdin.write(message)
                self.process.stdin.flush()
                raw = self.responses.get(timeout=self.timeout)
                if raw is None:
                    self.process.wait(timeout=5)
                    raise RuntimeError(f'inference process exited with code {self.process.returncode} '
                                       f'(0x{self.process.returncode & 0xffffffff:08X})')
                response = json.loads(raw)
                if response.get('error'): raise RuntimeError(response['error'])
                return decode_result(response['result'])
            except (OSError, ValueError, RuntimeError, queue.Empty, subprocess.TimeoutExpired) as error:
                self.log(f'[scan worker] analysis failed: {error}')
                self.close()
                raise ApiError(503, 'engine_unavailable',
                    'The image analysis worker stopped. The server is online; retry this image.',
                    retryable=True, headers={'Retry-After': '2'}) from error

    def close(self):
        with self._lock:
            process, self.process = self.process, None
            if process is None: return
            if process.stdin:
                try: process.stdin.close()
                except OSError: pass
            try: process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
            if process.stdout: process.stdout.close()


def main():
    import faulthandler
    import traceback
    faulthandler.enable(all_threads=True)
    # Third party model loaders print diagnostics; keep the protocol separate.
    output = sys.stdout
    sys.stdout = sys.stderr
    from analysis import AnalyzeOptions
    from .engines import InsightEngines
    engines = InsightEngines(isolate_scans=False)
    for line in sys.stdin.buffer:
        try:
            if len(line) > MAX_MESSAGE: raise ValueError('Image IPC message is too large')
            request = json.loads(line)
            shape = request['shape']
            if len(shape) != 3 or shape[2] != 3 or min(shape) < 1 or max(shape) > 4096:
                raise ValueError('Invalid image shape')
            image = np.frombuffer(base64.b64decode(request['pixels'], validate=True), np.uint8).reshape(shape)
            result = engines.analyze(image, AnalyzeOptions(**request['options']))
            response = {'result': encode_result(result)}
        except Exception as error:
            traceback.print_exc()
            response = {'error': str(error)}
        output.write(PREFIX + json.dumps(response, separators=(',', ':')) + '\n')
        output.flush()
    engines.unload()


if __name__ == '__main__': main()
