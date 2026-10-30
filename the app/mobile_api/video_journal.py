"""Bounded, device-owned scan checkpoints in the expiring job workspace."""
import bisect
import hashlib
import json
import logging
import math
import os
import threading
import time

from .errors import bad_request, not_found

log = logging.getLogger('mobile_api')
MAX_LINE = 16 * 1024 * 1024
MAX_BATCH = 4 * 1024 * 1024
TTL = 86400


def save(ctx, job):
    """Caller holds the job lock; pixels/previews and process state are never journaled."""
    state = {key: value for key, value in job.items()
             if not key.startswith('_') and key not in ('preview_jpeg', 'preview_timestamp_ms')}
    state.update(next_frame=job.get('_committed_next_frame', job['_next_frame']),
                 result_bytes=job.get('_result_bytes', 0), version=1)
    directory = ctx.workspace.job_dir(job['job_id'])
    target = directory / 'scan-state.json'
    temporary = directory / 'scan-state.tmp'
    with open(temporary, 'w', encoding='utf-8') as output:
        json.dump(state, output, separators=(',', ':'), allow_nan=False)
        output.flush()
        os.fsync(output.fileno())
    os.replace(temporary, target)
    job['_saved_at'] = time.monotonic()


def recover(ctx):
    jobs = {}
    for directory in sorted(ctx.workspace.jobs_dir.glob('vid_*')):
        if len(jobs) >= 32:
            break
        if directory.is_symlink() or (hasattr(directory, 'is_junction') and directory.is_junction()):
            continue
        try:
            state_path = directory / 'scan-state.json'
            if not state_path.is_file() or state_path.stat().st_size > 2 * 1024 * 1024:
                continue
            state = json.loads(state_path.read_text(encoding='utf-8'))
            job_id = state['job_id']
            if (state.get('version') != 1 or job_id != directory.name
                    or ctx.workspace.job_dir(job_id) != directory or state['type'] != 'analyze_video'
                    or not ctx.auth.has_device(state['owner'])
                    or not ctx.workspace.valid_sha(state['input_sha'])
                    or not math.isfinite(state['touched']) or time.time() - state['touched'] > TTL):
                continue
            if state['status'] not in ('completed', 'failed', 'paused', 'queued', 'running'):
                continue
            if state['status'] != 'completed' and not (directory / 'input.video').is_file():
                continue
            path = directory / 'detections.ndjson'
            offsets, last_frame = [0], -1
            if path.is_file():
                with open(path, 'r+b') as source:
                    while True:
                        raw = source.readline(MAX_LINE + 1)
                        if not raw:
                            break
                        try:
                            if len(raw) > MAX_LINE or not raw.endswith(b'\n'):
                                raise ValueError('incomplete frame')
                            frame = json.loads(raw)
                            number = frame['frame_number']
                            if type(number) is not int or number <= last_frame or number < 0:
                                raise ValueError('invalid frame order')
                        except (ValueError, KeyError, TypeError):
                            source.seek(offsets[-1])
                            source.truncate()
                            break
                        offsets.append(source.tell())
                        last_frame = number
            fps = state.get('details', {}).get('fps', 0)
            interval = state['params'].get('frame_interval', 1.0)
            step = state.get('details', {}).get('sample_step', max(1, round(fps * interval)))
            next_frame = max(state['params'].get('start_frame', 0), last_frame + step if last_frame >= 0 else 0)
            if offsets[-1] >= state.get('result_bytes', 0):
                next_frame = max(next_frame, state['next_frame'])
            completed = (state['status'] == 'completed' and offsets[-1] == state.get('result_bytes', 0)
                         and (directory / 'manifest.json').is_file())
            if not completed and state['status'] != 'failed':
                state.update(status='paused', message='PC restarted. Ready to resume.', error=None)
            state.update(has_result=completed, frames_done=len(offsets) - 1, last_frame=last_frame,
                         incremental_results=True, preview_jpeg=None, preview_timestamp_ms=None,
                         _next_frame=next_frame, _result_bytes=offsets[-1], _offsets=offsets,
                         _committed_next_frame=next_frame,
                         _saved_at=time.monotonic(), _stop=threading.Event())
            for key in ('next_frame', 'result_bytes', 'version'):
                state.pop(key, None)
            ctx.workspace.pin_job_inputs(job_id, [state['input_sha']])
            jobs[job_id] = state
        except (OSError, ValueError, KeyError, TypeError, OverflowError):
            log.warning('Could not recover video checkpoint %s', directory.name, exc_info=True)
    return jobs


def batch(ctx, job, cursor, limit):
    """Caller holds the lock; only complete, fsynced records are visible to the phone."""
    if type(cursor) is not int or cursor < 0 or type(limit) is not int or not 1 <= limit <= 8:
        raise bad_request('Invalid video frame cursor or batch size.')
    offsets = job['_offsets']
    index = bisect.bisect_left(offsets, cursor)
    available = job['_result_bytes']
    if index >= len(offsets) or offsets[index] != cursor or cursor > available:
        raise bad_request('This cursor is not a committed video frame boundary.')
    end_index = min(index + limit, bisect.bisect_right(offsets, available) - 1)
    while end_index > index + 1 and offsets[end_index] - cursor > MAX_BATCH:
        end_index -= 1
    end = offsets[end_index]
    try:
        if end == cursor:
            raw = b''
        else:
            with open(ctx.workspace.job_dir(job['job_id']) / 'detections.ndjson', 'rb') as source:
                source.seek(cursor)
                raw = source.read(end - cursor)
            if len(raw) != end - cursor:
                raise not_found('The saved video batch is unavailable. Resume this scan.')
    except FileNotFoundError:
        raise not_found('The saved video batch is unavailable. Resume this scan.')
    return dict(ndjson=raw.decode('utf-8'), sha256=hashlib.sha256(raw).hexdigest(), next_cursor=end,
                has_more=end < available, completed=job['status'] == 'completed' and end == available)
