"""Automatic expiry of ephemeral input/output files, even when no client polls."""
import logging
import threading

log = logging.getLogger("mobile_api")


class ScratchJanitor:
    def __init__(self, ctx, interval=60):
        self.ctx = ctx
        self.interval = interval
        self.stopped = threading.Event()
        self.thread = None

    def sweep(self):
        with self.ctx.jobs_lock:
            for manager in (self.ctx.video_jobs, self.ctx.studio_jobs):
                with manager.lock:
                    manager._expire()
            self.ctx.workspace.purge_stale_blobs()
            self.ctx.workspace.purge_stale_partials()
            self.ctx.workspace.purge_expired_jobs()

    def start(self):
        self.thread = threading.Thread(target=self._run, name="scratch-cleanup", daemon=True)
        self.thread.start()

    def _run(self):
        while not self.stopped.is_set():
            try:
                self.sweep()
            except Exception:
                log.exception("Temporary workspace cleanup failed; it will be retried")
            self.stopped.wait(self.interval)

    def close(self):
        self.stopped.set()
        if self.thread is not None:
            self.thread.join(timeout=10)
