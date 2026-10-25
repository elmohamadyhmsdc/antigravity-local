"""Temporary upload lifetime and safe last-consumer cleanup; no real user data."""
import hashlib
import os
import shutil
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from mobile_api.app import create_app
from mobile_api.cleanup import ScratchJanitor
from mobile_api.testing import make_test_context
from mobile_api.workspace import Workspace


class RetentionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.ws = Workspace(Path(self.tmp.name) / "scratch")
        self.ws.prepare()

    def tearDown(self):
        self.tmp.cleanup()

    def upload(self, data):
        sha = hashlib.sha256(data).hexdigest()
        self.ws.partial_path(sha).write_bytes(data)
        self.ws.commit_partial(sha)
        return sha

    def pin(self, name, sha):
        directory = self.ws.job_dir(name, create=True)
        shutil.copyfile(self.ws.blob_path(sha), directory / "input.target")
        self.ws.pin_job_inputs(name, [sha])
        return directory

    def test_shared_blob_survives_until_the_last_registered_job_is_acknowledged(self):
        data = b"shared image owned by two queued/running jobs"
        sha = self.upload(data)
        first, second = self.pin("first", sha), self.pin("second", sha)
        (first / "result.png").write_bytes(b"first result")
        self.ws.purge_job("first")
        self.assertFalse(first.exists())
        self.assertTrue(self.ws.has_blob(sha))
        self.assertEqual((second / "input.target").read_bytes(), data)
        self.ws.purge_job("second")
        self.assertFalse(second.exists())
        self.assertFalse(self.ws.has_blob(sha))
        self.assertEqual(self.ws._job_inputs, {})
        self.assertFalse(self.ws.purge_job("second"))

    def test_job_removal_failure_is_not_reported_as_success(self):
        sha = self.upload(b"input")
        directory = self.pin("retry", sha)
        with patch("mobile_api.workspace.shutil.rmtree", side_effect=PermissionError("locked")):
            with self.assertRaises(PermissionError):
                self.ws.purge_job("retry")
        self.assertTrue(directory.exists())
        self.assertTrue(self.ws.has_blob(sha))
        self.ws.purge_job("retry")
        self.assertFalse(directory.exists())
        self.assertFalse(self.ws.has_blob(sha))

    def test_cache_removal_failure_can_retry_after_the_job_directory_is_gone(self):
        sha = self.upload(b"input")
        directory = self.pin("retry", sha)
        actual = Path.unlink
        def locked(path, *args, **kwargs):
            if path == self.ws.blob_path(sha):
                raise PermissionError("cache file locked")
            return actual(path, *args, **kwargs)
        with patch.object(Path, "unlink", locked):
            with self.assertRaises(PermissionError):
                self.ws.purge_job("retry")
        self.assertFalse(directory.exists())
        self.assertTrue(self.ws.has_blob(sha))
        self.assertIn("retry", self.ws._job_inputs)
        self.ws.purge_job("retry")
        self.assertFalse(self.ws.has_blob(sha))
        self.assertNotIn("retry", self.ws._job_inputs)

    def test_orphans_expire_while_registered_inputs_and_jobs_are_protected(self):
        live = self.upload(b"active input")
        orphan = self.upload(b"abandoned upload")
        directory = self.pin("active", live)
        abandoned = self.ws.job_dir("abandoned", create=True)
        partial = self.ws.partial_path(hashlib.sha256(b"partial").hexdigest())
        partial.write_bytes(b"p")
        old = time.time() - 3 * 86400
        for path in [self.ws.blob_path(live), self.ws.blob_path(orphan), directory, abandoned, partial]:
            os.utime(path, (old, old))
        self.assertEqual(self.ws.purge_stale_blobs(), 1)
        self.assertTrue(self.ws.has_blob(live))
        self.assertFalse(self.ws.has_blob(orphan))
        self.assertEqual(self.ws.purge_stale_partials(), 1)
        self.assertEqual(self.ws.purge_expired_jobs(), ["abandoned"])
        self.assertTrue(directory.exists())

    def test_background_cleanup_expires_completed_jobs_without_any_poll_request(self):
        ctx = make_test_context(Path(self.tmp.name) / "server")
        create_app(ctx)
        self.ws = ctx.workspace
        sha = self.upload(b"expired job input")
        directory = self.pin("studio_expired", sha)
        ctx.studio_jobs.jobs["studio_expired"] = dict(status="completed", touched=time.time()-90000)
        janitor = ScratchJanitor(ctx, interval=.01)
        try:
            janitor.start()
            deadline = time.monotonic() + 2
            while (directory.exists() or self.ws.has_blob(sha) or "studio_expired" in ctx.studio_jobs.jobs) and time.monotonic() < deadline:
                time.sleep(.01)
            self.assertFalse(directory.exists())
            self.assertFalse(self.ws.has_blob(sha))
            self.assertNotIn("studio_expired", ctx.studio_jobs.jobs)
        finally:
            janitor.close()
            ctx.studio_jobs.close()
            ctx.video_jobs.close()
        self.assertFalse(janitor.thread.is_alive())

    def test_restart_wipes_ephemeral_inputs_and_keeps_connection_identity_only(self):
        sha = self.upload(b"private input")
        self.pin("queued", sha)
        self.ws.devices_path.write_text("connection identity", encoding="utf-8")
        (self.ws.tls_dir / "certificate").write_text("TLS", encoding="utf-8")
        self.ws.prepare(wipe=True)
        self.assertEqual(self.ws._job_inputs, {})
        self.assertFalse(list(self.ws.blobs_dir.rglob(sha)))
        self.assertFalse(list(self.ws.jobs_dir.iterdir()))
        self.assertEqual(self.ws.devices_path.read_text(encoding="utf-8"), "connection identity")


if __name__ == "__main__":
    unittest.main(verbosity=2)
