"""
Keeps the Mobile API up: the server runs in a child process and is started again after a crash.

A native crash (an access violation inside a GPU/DLL library) cannot be caught by Python, so the
only defence is a parent that notices the exit and starts a new server. The new server keeps the
same identity (devices.json + tls/), so paired phones reconnect on their own. Video scans restore
their expiring checkpoints; the phone resubmits work whose temporary state is unavailable.

Supervision ends on a clean exit (the dashboard's Stop, Ctrl+C), and when the very first launch
fails before the server ever came up - a port clash or a broken environment is reported instead of
retried forever. "Came up" means the child wrote control.json carrying this launch's token.
Stdlib only: this process must never load the GPU libraries itself.
"""

import argparse
import json
import os
import secrets
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from . import APP_DIR

CHILD_ENV = 'AG_MOBILE_API_CHILD'
LAUNCH_ENV = 'AG_MOBILE_API_LAUNCH'
RECOVERY_ENV = 'AG_MOBILE_API_RECOVERY'
CONTROL_FILE = 'control.json'  # same name as admin.CONTROL_FILE; admin imports fastapi, this must not
CONTROL_C_EXIT = 0xC000013A
CLEAN_EXITS = (0, CONTROL_C_EXIT)
HEALTHY_AFTER = 300.0      # s of uptime after which the restart delay starts again from the first step
BACKOFF = (2, 5, 10, 30, 60)
DIRECT_FLAGS = ('-h', '--help', '--check-models')


def is_child():
    return os.environ.get(CHILD_ENV) == '1'


def wants_supervisor(argv):
    return not is_child() and not any(flag in argv for flag in DIRECT_FLAGS)


def launch_token():
    return os.environ.get(LAUNCH_ENV, '')


def describe(code):
    return f'{code} (0x{code & 0xffffffff:08X})'


def recovery_info():
    """What the supervisor told this server about earlier crashes, or None on a first start."""
    try:
        info = json.loads(os.environ.get(RECOVERY_ENV, ''))
    except ValueError:
        return None
    return info if isinstance(info, dict) and isinstance(info.get('restarts'), int) else None


def _control_path(argv):
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--workspace', default=str(APP_DIR / 'mobile_workspace'))
    return Path(parser.parse_known_args(argv)[0].workspace) / CONTROL_FILE


def _came_up(control, launch):
    try:
        return json.loads(control.read_text(encoding='utf-8')).get('launch') == launch
    except (OSError, ValueError, AttributeError):
        return False


def supervise(argv, *, python=sys.executable, popen=subprocess.Popen, sleep=time.sleep,
              clock=time.monotonic, log=print):
    argv = list(argv)
    control = _control_path(argv)
    established = False
    restarts, step, last = 0, 0, None
    while True:
        launch = secrets.token_urlsafe(16)
        env = dict(os.environ, **{CHILD_ENV: '1', LAUNCH_ENV: launch})
        if last is not None:
            env[RECOVERY_ENV] = json.dumps({'restarts': restarts, **last})
        child = popen([python, '-u', '-m', 'mobile_api', *argv], env=env)
        started = clock()
        try:
            while True:
                try:
                    code = child.wait(timeout=1)
                    break
                except subprocess.TimeoutExpired:
                    established = established or _came_up(control, launch)
        except KeyboardInterrupt:
            # Ctrl+C reaches the child too, and it shuts down cleanly on its own.
            try:
                child.wait(timeout=20)
            except (subprocess.TimeoutExpired, KeyboardInterrupt):
                child.kill()
            return 0
        uptime = clock() - started
        if code in CLEAN_EXITS:
            return 0
        established = established or _came_up(control, launch)
        if not established:
            log(f'[supervisor] mobile server exited with code {describe(code)} before it came up; not restarting.')
            return code
        step = 0 if uptime >= HEALTHY_AFTER or last is None else min(step + 1, len(BACKOFF) - 1)
        delay = BACKOFF[step]
        restarts += 1
        last = {'last_code': code, 'at': datetime.now(timezone.utc).isoformat()}
        log(f'[supervisor] mobile server exited unexpectedly with code {describe(code)} after {uptime:.0f}s; '
            f'restarting in {delay}s (restart #{restarts}).')
        sys.stdout.flush()
        if '--no-browser' not in argv:
            argv.append('--no-browser')  # the first launch already opened the pairing page
        try:
            sleep(delay)
        except KeyboardInterrupt:
            return 0
