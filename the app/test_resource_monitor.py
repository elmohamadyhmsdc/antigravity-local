"""CPU-only synthetic resource telemetry, admission and UI checks.

Run with the existing main venv: python -m unittest test_resource_monitor -v
No real models, user library, jobs, GPU probing or subprocesses are needed.
"""

import json
import os
import tempfile
import threading
import unittest
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

import resource_monitor as rm
from mobile_api.contract.resource_fixture import resource_fixture


class LimitsTests(unittest.TestCase):
    def test_defaults_are_monitoring_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            monitor = rm.ResourceMonitor(tmp)
            with patch.object(monitor, "snapshot", side_effect=AssertionError("disabled protection must not sample")):
                self.assertEqual(monitor.admission_reasons(), [])

    def test_limits_round_trip_and_invalid_values(self):
        with tempfile.TemporaryDirectory() as tmp:
            limits = rm.ResourceLimits(enabled=True, max_app_ram_mb=4096)
            rm.save_limits(limits, tmp)
            self.assertEqual(rm.load_limits(tmp), limits)
            self.assertFalse(list(Path(tmp).glob("*.tmp")))
        for values in ({"enabled": "yes"}, {"min_free_ram_mb": -1}, {"max_app_ram_mb": True},
                       {"min_free_vram_mb": float("nan")}, {"min_free_disk_mb": 1.5}):
            with self.subTest(values=values), self.assertRaises(ValueError):
                rm.ResourceLimits.parse(values)

    def test_corrupt_limits_block_admission_with_a_useful_message(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "resource_limits.json").write_text("broken", encoding="utf-8")
            self.assertIn("could not be read", rm.ResourceMonitor(tmp).admission_reasons()[0])

    def test_thresholds_use_available_ram_and_free_vram_and_disk(self):
        sample = resource_fixture()
        limits = rm.ResourceLimits(enabled=True, max_app_ram_mb=2048,
                                   min_free_ram_mb=9000, min_free_vram_mb=5000, min_free_disk_mb=600000)
        reasons = rm.admission_reasons(sample, limits)
        self.assertEqual(len(reasons), 4)
        self.assertIn("Application RAM", reasons[0])
        self.assertEqual(rm.admission_reasons(sample, replace(limits, enabled=False)), [])

    def test_missing_measurement_blocks_only_an_enabled_threshold(self):
        sample = resource_fixture()
        sample.update(ram=None, disk=None, app_ram_bytes=None, gpus=[])
        self.assertEqual(len(rm.admission_reasons(sample, rm.ResourceLimits(enabled=True, max_app_ram_mb=1))), 4)
        self.assertEqual(rm.admission_reasons(sample, rm.ResourceLimits(
            enabled=True, min_free_ram_mb=0, min_free_vram_mb=0, min_free_disk_mb=0)), [])

    def test_incomplete_process_measurements_cannot_pass_an_app_ram_limit(self):
        sample = resource_fixture()
        sample["processes_complete"] = False
        self.assertIn("incomplete", rm.admission_reasons(sample, rm.ResourceLimits(
            enabled=True, max_app_ram_mb=4096))[0])


class SamplingTests(unittest.TestCase):
    def runner(self, apps):
        return Mock(side_effect=[SimpleNamespace(returncode=0, stdout="0, GPU-test, Test GPU, 6144, 2000, 4144, 30, 50\n"),
                                 SimpleNamespace(returncode=0, stdout=apps)])

    def test_gpu_wide_usage_is_separate_from_attributed_compute_usage(self):
        runner = self.runner("GPU-test, 11, 250\nGPU-test, 12, 350\nGPU-test, 99, 900\n")
        with patch.object(rm.shutil, "which", return_value="fixture-smi"):
            gpus, warning = rm.sample_gpus({11, 12}, runner)
        self.assertIsNone(warning)
        self.assertEqual(gpus[0]["used_bytes"], 2000 * rm.MIB)
        self.assertEqual(gpus[0]["app_used_bytes"], 600 * rm.MIB)
        self.assertEqual(runner.call_args.kwargs["timeout"], 2)

    def test_unsupported_or_absent_per_process_vram_remains_unknown(self):
        for apps in ("GPU-test, 11, [N/A]\n", "GPU-test, 11, 20\nGPU-test, 12, N/A\n", "", "GPU-test, 99, 100\n"):
            with self.subTest(apps=apps), patch.object(rm.shutil, "which", return_value="fixture-smi"):
                gpus, _ = rm.sample_gpus({11, 12}, self.runner(apps))
                self.assertIsNone(gpus[0]["app_used_bytes"])

    def test_missing_or_failed_gpu_tools_do_not_break_monitoring(self):
        with patch.object(rm.shutil, "which", return_value=None), patch.object(rm.Path, "is_file", return_value=False):
            self.assertEqual(rm.sample_gpus(set())[0], [])
        with patch.object(rm.shutil, "which", return_value="fixture-smi"):
            self.assertEqual(rm.sample_gpus(set(), Mock(side_effect=OSError()))[0], [])

    def test_folder_sizes_deduplicate_hard_links(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a").write_bytes(b"x" * 100)
            (root / "nested").mkdir()
            (root / "nested" / "b").write_bytes(b"y" * 200)
            os.link(root / "a", root / "alias")
            self.assertEqual(rm.folder_usage([root], budget_seconds=5), (300, True))
            self.assertFalse(rm.folder_usage([root], budget_seconds=0)[1])

    def test_memory_tracks_app_roots_and_children_once(self):
        class Gone(Exception):
            pass

        class Denied(Exception):
            pass

        with tempfile.TemporaryDirectory() as tmp:
            current = Mock(pid=os.getpid())
            worker = Mock(pid=22)
            unrelated = Mock(pid=33)
            child = Mock(pid=44)
            for proc in (current, worker, unrelated, child):
                proc.name.return_value = "python.exe"
                proc.memory_info.return_value = SimpleNamespace(rss=100)
                proc.children.return_value = []
                proc.cwd.return_value = tmp
            current.children.return_value = [worker, child]
            worker.children.return_value = [child]
            worker.info = dict(pid=22, name="python.exe", cmdline=["python", "job_manager.py"])
            unrelated.info = dict(pid=33, name="python.exe", cmdline=["python", "other_app.py"])
            lookup = {os.getpid(): current, 22: worker, 44: child}
            ps = SimpleNamespace(Error=Exception, NoSuchProcess=Gone,
                                 virtual_memory=lambda: SimpleNamespace(total=1000, available=500, percent=50),
                                 process_iter=lambda attrs: [worker, unrelated], Process=lambda pid: lookup[pid])
            ram, total, processes, complete, _ = rm.sample_memory(tmp, ps)
            self.assertEqual(total, 300)
            self.assertEqual({p["pid"] for p in processes}, set(lookup))
            self.assertTrue(complete)
            child.memory_info.side_effect = Denied()
            self.assertFalse(rm.sample_memory(tmp, ps)[3])

    def test_orphan_queue_worker_requires_matching_creation_time(self):
        class Gone(Exception):
            pass

        with tempfile.TemporaryDirectory() as tmp:
            current, worker = Mock(pid=os.getpid()), Mock(pid=22)
            for proc in (current, worker):
                proc.name.return_value = "python.exe"
                proc.children.return_value = []
                proc.memory_info.return_value = SimpleNamespace(rss=100)
            worker.create_time.return_value = 7
            lookup = {os.getpid(): current, 22: worker}
            ps = SimpleNamespace(Error=Exception, NoSuchProcess=Gone,
                                 virtual_memory=lambda: SimpleNamespace(total=1000, available=500, percent=50),
                                 process_iter=lambda attrs: [], Process=lambda pid: lookup[pid])
            jobs = Path(tmp) / "jobs"
            jobs.mkdir()
            for recorded, expected in ((7, 200), (8, 100)):
                (jobs / ".worker.pid").write_text(json.dumps({"pid": 22, "create_time": recorded}), encoding="utf-8")
                self.assertEqual(rm.sample_memory(tmp, ps)[1], expected)

    def test_cache_and_histories_are_bounded_and_alerts_only_repeat_after_recovery(self):
        with tempfile.TemporaryDirectory() as tmp:
            monitor = rm.ResourceMonitor(tmp, interval=0)
            ram = dict(total_bytes=1000, available_bytes=50, used_percent=95)
            with patch.object(rm, "sample_memory", return_value=(ram, 100, [], True, None)), patch.object(
                    rm, "sample_gpus", return_value=([], "GPU unavailable")):
                for _ in range(130):
                    monitor.snapshot()
                self.assertEqual(len(monitor.history), 120)
                self.assertEqual(len(monitor.events), 1)
                ram["used_percent"] = 50
                monitor.snapshot()
                ram["used_percent"] = 95
                monitor.snapshot()
                self.assertEqual(len(monitor.events), 2)
                monitor.interval = 5
                with patch.object(rm, "sample_memory", side_effect=AssertionError("cache miss")):
                    self.assertIs(monitor.snapshot(), monitor._snapshot)
            monitor.close()


class FakeMonitor:
    def __init__(self):
        self.reasons = []
        self._lock = threading.RLock()
        self.history = []
        self.events = []
        self.value = resource_fixture()

    def start(self):
        return self

    def close(self):
        pass

    def snapshot(self):
        return self.value

    def admission_reasons(self):
        return self.reasons


class IntegrationTests(unittest.TestCase):
    def test_authenticated_api_readings_and_retryable_compute_pressure(self):
        from fastapi.testclient import TestClient
        from mobile_api.app import create_app
        from mobile_api.testing import make_test_context
        with tempfile.TemporaryDirectory() as tmp:
            ctx = make_test_context(Path(tmp))
            monitor = ctx.resources = FakeMonitor()
            with TestClient(create_app(ctx)) as client:
                device = ctx.auth.add_device("Fixture phone")
                auth = {"Authorization": "Bearer " + device["token"]}
                self.assertEqual(client.get("/v1/resources").status_code, 401)
                response = client.get("/v1/resources", headers=auth)
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.headers["cache-control"], "no-store")
                self.assertEqual(response.json(), resource_fixture())
                self.assertNotIn(str(Path(tmp)), response.text)
                monitor.reasons = ["Free system RAM is below 1024 MiB."]
                self.assertTrue(client.get("/v1/resources", headers=auth).json()["admission_blocked"])
                response = client.post("/v1/analyze/image", headers=auth, files={"image": ("a.jpg", b"not decoded")})
                self.assertEqual(response.status_code, 503)
                self.assertEqual(response.json()["error"]["code"], "resource_pressure")
                self.assertTrue(response.json()["error"]["retryable"])
                self.assertIn("Retry-After", response.headers)
                self.assertFalse(ctx.engines.calls)

    def test_desktop_preflight_pauses_without_losing_checkpoints(self):
        from job_manager import Job, JobManager, JobStatus, run_single_job
        with tempfile.TemporaryDirectory() as tmp:
            manager = JobManager(tmp)
            job = Job(id="fixture", job_type="reface_video", status=JobStatus.QUEUED, progress=.5,
                      message="queued", created_at="fixture", frames_done=120, last_frame=120,
                      part_files=["part.mp4"], params={"quality_profile": "balanced"})
            manager.save_job(job)
            monitor = FakeMonitor()
            monitor.reasons = ["RAM threshold reached."]
            with patch.object(rm, "get_resource_monitor", return_value=monitor):
                self.assertFalse(run_single_job(job.id, tmp))
            paused = manager.load_job(job.id)
            self.assertEqual(paused.status, JobStatus.PAUSED)
            self.assertEqual((paused.frames_done, paused.last_frame, paused.part_files), (120, 120, ["part.mp4"]))
            self.assertIn("Resume", paused.message)

    def test_resource_ui_handles_missing_telemetry(self):
        from streamlit.testing.v1 import AppTest
        monitor = FakeMonitor()
        monitor.value.update(ram=None, app_ram_bytes=None, disk=None, gpus=[], storage_complete=False)
        with patch("resource_ui.get_resource_monitor", return_value=monitor):
            app = AppTest.from_string("from resource_ui import render_resource_details\nrender_resource_details()").run(timeout=15)
        self.assertFalse(app.exception)
        self.assertTrue(any(m.value == "Unavailable" for m in app.metric))

    def test_studio_waits_for_resources_then_runs_the_same_job(self):
        from mobile_api.studio_jobs import StudioJobs
        checked, entered = threading.Event(), threading.Event()
        monitor = FakeMonitor()
        monitor.reasons = ["RAM threshold reached."]

        def check_resources():
            checked.set()
            return monitor.reasons

        def runner(*args):
            entered.set()
            return None

        with tempfile.TemporaryDirectory() as tmp:
            ctx = SimpleNamespace(jobs_lock=threading.RLock(), compute_lock=threading.RLock(),
                                  video_jobs=SimpleNamespace(busy=lambda: None),
                                  gpu=SimpleNamespace(dashboard_busy=lambda: None, resource_check=check_resources),
                                  workspace=SimpleNamespace(job_dir=lambda job_id: Path(tmp)))
            studio = StudioJobs(ctx, runner=runner)
            job = dict(job_id="fixture", type="reface_image", status="queued", started_at=None,
                       message="Waiting", _stop=threading.Event(), frames_done=120)
            studio.jobs["fixture"] = job
            studio.worker = threading.Thread(target=studio._work, daemon=True)
            studio.worker.start()
            try:
                studio.wake.set()
                self.assertTrue(checked.wait(2))
                with studio.lock:
                    self.assertEqual(job["status"], "queued")
                    self.assertIn("resources", job["message"])
                self.assertFalse(entered.is_set())
                monitor.reasons = []
                studio.wake.set()
                self.assertTrue(entered.wait(2))
                self.assertEqual(job["frames_done"], 120)
            finally:
                studio.close()

    def test_contract_fixture_matches_schema_and_generator(self):
        import jsonschema
        import yaml
        contract = Path(__file__).parent / "mobile_api" / "contract"
        schema = yaml.safe_load((contract / "openapi.yaml").read_text(encoding="utf-8"))
        fixture = json.loads((contract / "fixtures" / "ResourceSnapshot.idle.json").read_text(encoding="utf-8"))
        self.assertEqual(fixture, resource_fixture())
        jsonschema.Draft202012Validator(schema["components"]["schemas"]["ResourceSnapshot"]).validate(fixture)

    def test_studio_resource_recheck_preserves_a_concurrent_user_pause(self):
        from mobile_api.studio_jobs import StudioJobs
        with tempfile.TemporaryDirectory() as tmp:
            checks = 0
            job = dict(job_id="fixture", type="reface_image", status="queued", started_at=None,
                       message="Waiting", _stop=threading.Event())

            def check_resources():
                nonlocal checks
                checks += 1
                if checks == 1:
                    return []
                job["_stop"].set()  # pause received while waiting for compute access
                studio.closing.set()
                return ["RAM threshold reached."]

            ctx = SimpleNamespace(jobs_lock=threading.RLock(), compute_lock=threading.RLock(),
                                  video_jobs=SimpleNamespace(busy=lambda: None),
                                  gpu=SimpleNamespace(dashboard_busy=lambda: None, resource_check=check_resources),
                                  workspace=SimpleNamespace(job_dir=lambda job_id: Path(tmp)))
            runner = Mock()
            studio = StudioJobs(ctx, runner=runner)
            studio.jobs["fixture"] = job
            studio.worker = threading.Thread(target=studio._work, daemon=True)
            studio.wake.set()
            studio.worker.start()
            studio.worker.join(timeout=2)
            try:
                self.assertFalse(studio.worker.is_alive())
                self.assertEqual(job["status"], "paused")
                runner.assert_not_called()
            finally:
                studio.close()


if __name__ == "__main__":
    unittest.main()
