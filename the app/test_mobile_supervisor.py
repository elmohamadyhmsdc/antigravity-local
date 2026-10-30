"""Mobile API supervisor: restart after a crash, never after a clean stop or a launch that never came up.
CPU only, fake child processes - no server, GPU or network."""

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from mobile_api import supervisor
from mobile_api.supervisor import (BACKOFF, CHILD_ENV, CONTROL_C_EXIT, LAUNCH_ENV, RECOVERY_ENV,
                                   recovery_info, supervise, wants_supervisor)
from mobile_dashboard_controller import ControlError, MobileDashboardController

ACCESS_VIOLATION = 0xC0000005


class Clock:
    def __init__(self): self.now = 0.0
    def __call__(self): return self.now


class FakeChild:
    """Runs for `uptime` seconds of the fake clock, optionally writes control.json, then exits with `code`."""
    def __init__(self, env, control, clock, code, uptime, comes_up):
        self.env, self.control, self.clock = env, control, clock
        self.code, self.uptime, self.comes_up = code, uptime, comes_up
        self.started = clock.now
        self.killed = False

    def wait(self, timeout=None):
        if self.comes_up:
            self.control.write_text(json.dumps({'launch': self.env[LAUNCH_ENV]}), encoding='utf-8')
        self.clock.now = self.started + self.uptime
        return self.code

    def kill(self): self.killed = True


class SupervisorTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix='ag_supervisor_')
        self.addCleanup(tmp.cleanup)
        self.workspace = Path(tmp.name)
        self.control = self.workspace / 'control.json'
        self.clock = Clock()
        self.children, self.commands, self.sleeps, self.logs = [], [], [], []

    def run_with(self, script, argv=()):
        """script: list of (exit code, uptime seconds, came up?) for each launch in order."""
        script = list(script)
        def popen(command, env):
            code, uptime, comes_up = script.pop(0)
            child = FakeChild(env, self.control, self.clock, code, uptime, comes_up)
            self.children.append(child); self.commands.append(command)
            return child
        result = supervise(['--workspace', str(self.workspace), *argv], python='python', popen=popen,
                           sleep=self.sleeps.append, clock=self.clock, log=self.logs.append)
        self.assertEqual(script, [], 'every scripted launch should have run')
        return result

    def test_clean_stop_is_not_restarted(self):
        self.assertEqual(self.run_with([(0, 3600, True)]), 0)
        self.assertEqual(self.sleeps, [])
        self.assertEqual(self.children[0].env[CHILD_ENV], '1')
        self.assertNotIn(RECOVERY_ENV, self.children[0].env)

    def test_ctrl_c_exit_code_is_a_clean_stop(self):
        self.assertEqual(self.run_with([(CONTROL_C_EXIT, 50, True)]), 0)
        self.assertEqual(len(self.children), 1)

    def test_first_launch_that_never_came_up_reports_its_failure(self):
        # e.g. the ports are busy: report it, do not retry forever
        self.assertEqual(self.run_with([(1, 2, False)]), 1)
        self.assertEqual(len(self.children), 1)
        self.assertIn('not restarting', self.logs[0])

    def test_native_crash_after_start_is_restarted_with_recovery_info(self):
        self.assertEqual(self.run_with([(ACCESS_VIOLATION, 1200, True), (0, 60, True)]), 0)
        self.assertEqual(self.sleeps, [BACKOFF[0]])
        self.assertIn('0xC0000005', self.logs[0])
        info = json.loads(self.children[1].env[RECOVERY_ENV])
        self.assertEqual((info['restarts'], info['last_code']), (1, ACCESS_VIOLATION))
        self.assertNotIn('--no-browser', self.commands[0])
        self.assertIn('--no-browser', self.commands[1])
        self.assertNotEqual(self.children[0].env[LAUNCH_ENV], self.children[1].env[LAUNCH_ENV])
        self.assertEqual(self.commands[1][:4], ['python', '-u', '-m', 'mobile_api'])

    def test_crash_loop_backs_off_and_keeps_retrying_after_it_came_up_once(self):
        # A restart that dies before it comes up (port still held, ...) is retried, slower each time.
        script = [(ACCESS_VIOLATION, 600, True)] + [(1, 1, False)] * 6 + [(0, 10, True)]
        self.assertEqual(self.run_with(script), 0)
        self.assertEqual(self.sleeps, [2, 5, 10, 30, 60, 60, 60])

    def test_backoff_resets_after_a_healthy_run(self):
        script = [(ACCESS_VIOLATION, 400, True), (ACCESS_VIOLATION, 5, True),
                  (ACCESS_VIOLATION, 400, True), (0, 1, True)]
        self.run_with(script)
        self.assertEqual(self.sleeps, [BACKOFF[0], BACKOFF[1], BACKOFF[0]])

    def test_stale_control_file_from_an_earlier_run_does_not_count_as_came_up(self):
        self.control.write_text(json.dumps({'launch': 'an-older-launch'}), encoding='utf-8')
        self.assertEqual(self.run_with([(ACCESS_VIOLATION, 600, False)]), ACCESS_VIOLATION)


class EntryPointTests(unittest.TestCase):
    def test_who_is_supervised(self):
        with mock.patch.dict(os.environ, {CHILD_ENV: ''}):
            self.assertTrue(wants_supervisor(['--port', '8443']))
            self.assertFalse(wants_supervisor(['--check-models']))
            self.assertFalse(wants_supervisor(['--help']))
        with mock.patch.dict(os.environ, {CHILD_ENV: '1'}):
            self.assertFalse(wants_supervisor(['--port', '8443']))

    def test_recovery_info(self):
        with mock.patch.dict(os.environ, {RECOVERY_ENV: ''}):
            self.assertIsNone(recovery_info())
        with mock.patch.dict(os.environ, {RECOVERY_ENV: 'not json'}):
            self.assertIsNone(recovery_info())
        with mock.patch.dict(os.environ, {RECOVERY_ENV: json.dumps({'restarts': 2, 'last_code': 5, 'at': 'x'})}):
            self.assertEqual(recovery_info()['restarts'], 2)

    def test_supervisor_stays_free_of_heavy_imports(self):
        import ast
        tree = ast.parse(Path(supervisor.__file__).read_text(encoding='utf-8'))
        imported = {alias.name for node in ast.walk(tree) if isinstance(node, ast.Import) for alias in node.names}
        imported |= {node.module or '' for node in ast.walk(tree) if isinstance(node, ast.ImportFrom)}
        self.assertEqual(imported - {'argparse', 'json', 'os', 'secrets', 'subprocess', 'sys', 'time',
                                     'datetime', 'pathlib', ''}, set())

    def test_server_marks_its_control_file_with_the_launch_token(self):
        from mobile_api import server
        with tempfile.TemporaryDirectory(prefix='ag_supervisor_ctl_') as tmp:
            ctx = mock.Mock(admin_token='t' * 40, pair_port=1, api_port=2)
            ctx.workspace.root = Path(tmp); ctx.auth.server_id = 'srv_x'
            with mock.patch.dict(os.environ, {LAUNCH_ENV: 'launch-123'}):
                server.write_control(ctx)
            self.assertEqual(json.loads((Path(tmp) / 'control.json').read_text(encoding='utf-8'))['launch'], 'launch-123')


class ControllerStopTests(unittest.TestCase):
    """Stop must work while the supervisor is between a crash and the restart (no server to ask)."""
    def test_stop_terminates_own_supervisor_when_no_server_answers(self):
        with tempfile.TemporaryDirectory(prefix='ag_supervisor_stop_') as tmp:
            root = Path(tmp)
            controller = MobileDashboardController(root, workspace=root / 'ws', log_dir=root / 'logs')
            (root / 'ws').mkdir(); (root / 'ws' / 'control.json').write_text('{}', encoding='utf-8')
            process = mock.Mock(); process.poll.return_value = None
            controller._process = process
            controller.stop()
            process.terminate.assert_called_once()
            self.assertFalse((root / 'ws' / 'control.json').exists())
            process.poll.return_value = 1; process.returncode = 1
            with mock.patch.object(MobileDashboardController, '_port_busy', return_value=False):
                self.assertEqual(controller.status()['state'], 'stopped')

    def test_stop_without_a_server_or_own_process_still_reports_it(self):
        with tempfile.TemporaryDirectory(prefix='ag_supervisor_stop_') as tmp:
            root = Path(tmp)
            controller = MobileDashboardController(root, workspace=root / 'ws', log_dir=root / 'logs')
            with self.assertRaises(ControlError):
                controller.stop()


if __name__ == '__main__':
    unittest.main(verbosity=2)
