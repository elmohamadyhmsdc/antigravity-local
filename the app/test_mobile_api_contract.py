"""
Mobile API contract tests: auth, pairing, blobs, analyze, error envelope, response shapes
against the golden fixtures in mobile_api/contract/fixtures.

Standalone script (repo convention): prints PASS/FAIL per test and exits 1 on failure.
CPU only - fake engines, temporary workspace, FastAPI's TestClient (no network, no GPU, no models).
Needs the packages in requirements_mobile_api.txt (fastapi, cryptography, qrcode; zeroconf is faked).

    venv\\Scripts\\python.exe test_mobile_api_contract.py            # everything
    venv\\Scripts\\python.exe test_mobile_api_contract.py blob       # only names containing "blob"
"""

import base64
import hashlib
import json
import os
import shutil
import sys
import tempfile
import traceback
from pathlib import Path

import cv2
import numpy as np
import yaml
from jsonschema import Draft202012Validator

try:
    from fastapi.testclient import TestClient
except ImportError as e:  # pragma: no cover
    print(f"FastAPI is not installed in this interpreter ({e}).\n"
          "Install requirements_mobile_api.txt (see the header of that file), then run this again.")
    sys.exit(1)

HERE = Path(__file__).resolve().parent
CONTRACT = HERE / "mobile_api" / "contract"
SPEC = yaml.safe_load((CONTRACT / "openapi.yaml").read_text(encoding="utf-8"))

_TESTS = []


def test(fn):
    _TESTS.append(fn)
    return fn


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


# --------------------------------------------------------------------------- helpers

def schema_errors(schema_name, instance):
    root = {"$ref": f"#/components/schemas/{schema_name}", "components": SPEC["components"]}
    return sorted(Draft202012Validator(root).iter_errors(instance), key=lambda e: list(e.path))


def check_schema(schema_name, instance, what=""):
    errs = schema_errors(schema_name, instance)
    check(not errs, f"{what or schema_name} does not match {schema_name}: "
                    + "; ".join(f"{'/'.join(map(str, e.path))}: {e.message[:100]}" for e in errs[:3]))


def fixture(name):
    return json.loads((CONTRACT / "fixtures" / f"{name}.json").read_text(encoding="utf-8"))


def shape(obj):
    """Key structure of a JSON value (lists are represented by their first element)."""
    if isinstance(obj, dict):
        return {k: shape(v) for k, v in sorted(obj.items())}
    if isinstance(obj, list):
        return [shape(obj[0])] if obj else []
    return type(obj).__name__ if obj is not None else "null"


def same_keys(a, b, path="$"):
    """Recursively: same dict keys (None/null values are skipped - they carry no structure)."""
    if isinstance(a, dict) and isinstance(b, dict):
        check(set(a) == set(b), f"{path}: keys differ: {sorted(set(a) ^ set(b))}")
        for k in a:
            same_keys(a[k], b[k], f"{path}.{k}")
    elif isinstance(a, list) and isinstance(b, list) and a and b:
        same_keys(a[0], b[0], f"{path}[0]")


def jpeg_bytes(w=640, h=480):
    img = np.random.default_rng(3).integers(0, 255, (h, w, 3), dtype=np.uint8)
    ok, buf = cv2.imencode(".jpg", img)
    assert ok
    return buf.tobytes()


class Env:
    """A fresh context + client per test, always cleaned up."""

    def __init__(self, **kw):
        from mobile_api.app import create_app
        from mobile_api.testing import make_test_context
        self.tmp = Path(tempfile.mkdtemp(prefix="mobile_api_contract_"))
        self.ctx = make_test_context(self.tmp, **kw)
        self.client = TestClient(create_app(self.ctx), raise_server_exceptions=False)
        self._token = None

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.ctx.image_decoder.close()
        self.client.close()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def pair(self, name="Test phone"):
        code = self.ctx.pairing.issue().code
        r = self.client.post("/v1/pair/complete", json={"code": code, "device_name": name})
        check(r.status_code == 200, f"pairing failed: {r.status_code} {r.text}")
        self._token = r.json()["token"]
        return self._token

    @property
    def auth(self):
        return {"Authorization": f"Bearer {self._token or self.pair()}"}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# --------------------------------------------------------------------------- health + auth + errors

@test
def test_health_needs_no_token_and_matches_the_contract():
    with Env() as e:
        r = e.client.get("/v1/health")
        check(r.status_code == 200, r.text)
        check_schema("Health", r.json())
        same_keys(r.json(), fixture("Health.ok"))
        check(r.json()["server_id"] == e.ctx.auth.server_id and r.json()["name"] == "Test PC", "identity")


@test
def test_everything_else_rejects_missing_and_wrong_tokens_with_the_envelope():
    with Env() as e:
        for method, path in [("get", "/v1/capabilities"), ("head", f"/v1/blobs/{'a' * 64}"),
                             ("put", f"/v1/blobs/{'a' * 64}"), ("post", "/v1/analyze/image")]:
            for headers in ({}, {"Authorization": "Bearer agm_nope"}, {"Authorization": "Basic abc"},
                            {"Authorization": "Bearer "}):
                r = getattr(e.client, method)(path, headers=headers)
                check(r.status_code == 401, f"{method} {path} {headers}: {r.status_code}")
                if method != "head":
                    check_schema("Error", r.json(), f"{method} {path} 401")
                    check(r.json()["error"]["code"] == "unauthorized" and not r.json()["error"]["retryable"], r.text)
                check(r.headers.get("www-authenticate", "").lower().startswith("bearer"), "WWW-Authenticate")


@test
def test_error_envelope_covers_unknown_routes_wrong_methods_and_bad_bodies():
    with Env() as e:
        r = e.client.get("/v1/nope")
        check(r.status_code == 404 and r.json()["error"]["code"] == "not_found", r.text)
        check_schema("Error", r.json())
        r = e.client.delete("/v1/health")
        check(r.status_code == 405, r.status_code)
        check_schema("Error", r.json(), "405")
        r = e.client.post("/v1/pair/complete", json={"device_name": "x"})  # no code
        check(r.status_code == 400 and r.json()["error"]["code"] == "bad_request", r.text)
        check_schema("Error", r.json(), "validation error")
        r = e.client.post("/v1/pair/complete", content=b"not json", headers={"content-type": "application/json"})
        check(r.status_code == 400, r.status_code)


@test
def test_unexpected_exceptions_become_a_500_envelope_without_leaking_details():
    with Env() as e:
        e.ctx.engines.fail_with = RuntimeError("secret path C:\\Users\\x\\boom")
        r = e.client.post("/v1/analyze/image", files={"image": ("a.jpg", jpeg_bytes(), "image/jpeg")}, headers=e.auth)
        check(r.status_code == 500, r.status_code)
        check_schema("Error", r.json(), "500")
        check("secret" not in r.text and "boom" not in r.text, f"the envelope must not leak internals: {r.text}")


# --------------------------------------------------------------------------- pairing

@test
def test_pairing_exchanges_a_one_time_code_for_a_token_stored_only_hashed():
    with Env() as e:
        code = e.ctx.pairing.issue().code
        check(len(code) == 9 and code[4] == "-", f"code format: {code}")
        bad = e.client.post("/v1/pair/complete", json={"code": "AAAA-AAAA", "device_name": "Pixel"})
        check(bad.status_code == 401 and bad.json()["error"]["code"] == "invalid_code", bad.text)
        check_schema("Error", bad.json(), "wrong code")
        same_keys(bad.json(), fixture("Error.invalid_code"))

        body = fixture("PairRequest.ok")
        check_schema("PairRequest", body)
        r = e.client.post("/v1/pair/complete", json={"code": code.lower().replace("-", " "), "device_name": "Pixel 8"})
        check(r.status_code == 200, r.text)
        check_schema("PairResponse", r.json())
        same_keys(r.json(), fixture("PairResponse.ok"))
        token = r.json()["token"]
        check(token.startswith("agm_") and len(token) == 44, f"token format: {token}")

        again = e.client.post("/v1/pair/complete", json={"code": code, "device_name": "Pixel 8"})
        check(again.status_code == 401, "a code is single use")

        raw = e.ctx.workspace.devices_path.read_text(encoding="utf-8")
        check(token not in raw, "the plain token must never be written to devices.json")
        check(hashlib.sha256(token.encode()).hexdigest() in raw, "its SHA-256 is what is stored")
        ok = e.client.get("/v1/capabilities", headers={"Authorization": f"Bearer {token}"})
        check(ok.status_code == 200, ok.text)
        check([d["name"] for d in e.ctx.auth.devices()] == ["Pixel 8"], "device registered")


@test
def test_pairing_code_expires_locks_after_wrong_guesses_and_new_codes_replace_old_ones():
    from mobile_api.testing import Clock
    clock = Clock()
    with Env(clock=clock) as e:
        old = e.ctx.pairing.issue().code
        new = e.ctx.pairing.issue().code
        r = e.client.post("/v1/pair/complete", json={"code": old, "device_name": "x"})
        check(r.status_code == 401, "issuing a new code invalidates the old one")

        for _ in range(e.ctx.pairing.max_attempts):
            e.client.post("/v1/pair/complete", json={"code": "ZZZZ-ZZZZ", "device_name": "x"})
        r = e.client.post("/v1/pair/complete", json={"code": new, "device_name": "x"})
        check(r.status_code == 429 and r.json()["error"]["code"] == "pairing_locked", f"lockout: {r.status_code} {r.text}")
        check(e.ctx.pairing.current() is None, "a burned code is not shown on the PC any more")

        fresh = e.ctx.pairing.issue().code
        clock.advance(e.ctx.pairing.ttl + 1)
        r = e.client.post("/v1/pair/complete", json={"code": fresh, "device_name": "x"})
        check(r.status_code == 401, "an expired code is refused")
        check(e.ctx.auth.devices() == [], "nothing was paired")


@test
def test_revoked_devices_lose_access():
    with Env() as e:
        e.pair("A")
        check(e.client.get("/v1/capabilities", headers=e.auth).status_code == 200, "paired")
        for d in e.ctx.auth.devices():
            check(e.ctx.auth.revoke(d["id"]), "revoke")
        check(e.client.get("/v1/capabilities", headers=e.auth).status_code == 401, "revoked token must stop working")


# --------------------------------------------------------------------------- capabilities + gpu guard

@test
def test_capabilities_match_the_contract_idle_and_busy():
    with Env() as e:
        r = e.client.get("/v1/capabilities", headers=e.auth)
        check(r.status_code == 200, r.text)
        check_schema("Capabilities", r.json())
        same_keys(r.json(), fixture("Capabilities.idle"))
        check(r.json()["busy"] is None, "idle")
        check(r.json()["embedding_model"] == {"id": "buffalo_l@1", "dim": 512}, "embedding model")

        _start_job(e.ctx.workspace.jobs_dir, "train_lora", "abc12345")  # a mobile-queue job holds the GPU
        r = e.client.get("/v1/capabilities", headers=e.auth)
        check_schema("Capabilities", r.json(), "busy capabilities")
        same_keys(r.json(), fixture("Capabilities.busy_with_dashboard_job"))
        check(r.json()["busy"] == {"job_id": "abc12345", "job_type": "train_lora", "source": "mobile"}, r.json()["busy"])


def _start_job(jobs_dir, job_type, job_id):
    """A running job + a live worker pid in `jobs_dir` (what job_manager looks at)."""
    from job_manager import Job, JobManager, JobStatus
    mgr = JobManager(str(jobs_dir))
    job = Job(id=job_id, job_type=job_type, status=JobStatus.RUNNING, progress=0.1, message="x",
              created_at="2026-10-11T12:00:00", params={})
    mgr.save_job(job)
    mgr.set_worker_pid(os.getpid())
    return mgr


@test
def test_gpu_guard_checks_both_job_queues_and_only_heavy_dashboard_jobs():
    with Env() as e:
        guard = e.ctx.gpu
        check(guard.busy() is None, "nothing running")

        dash = guard.dashboard_jobs_dir
        _start_job(dash, "reface_video_v3", "dash0001")
        check(guard.busy() is None, "a plain reface job in the dashboard queue is not GPU-heavy (job_manager's rule)")
        shutil.rmtree(dash)
        _start_job(dash, "undress_image", "dash0002")
        b = guard.busy()
        check(b and b.source == "dashboard" and b.job_type == "undress_image", f"dashboard heavy job: {b}")

        _start_job(e.ctx.workspace.jobs_dir, "reface_video_v3", "mob00001")
        b = guard.busy()
        check(b and b.source == "mobile" and b.job_id == "mob00001", f"any mobile-queue job counts: {b}")

        (e.ctx.workspace.jobs_dir / ".worker.pid").unlink()
        shutil.rmtree(dash)
        check(guard.busy() is None, "no live worker -> not busy (stale job files do not block the GPU forever)")


@test
def test_analyze_answers_503_gpu_busy_with_retry_after_while_a_heavy_job_runs():
    with Env() as e:
        _start_job(e.ctx.gpu.dashboard_jobs_dir, "train_lora", "dash0003")
        r = e.client.post("/v1/analyze/image", files={"image": ("a.jpg", jpeg_bytes(), "image/jpeg")}, headers=e.auth)
        check(r.status_code == 503, r.status_code)
        check(int(r.headers["retry-after"]) > 0, "Retry-After")
        check_schema("Error", r.json())
        check(r.json()["error"]["code"] == "gpu_busy" and r.json()["error"]["retryable"] is True, r.text)
        same_keys(r.json(), fixture("Error.gpu_busy"))
        check(not e.ctx.engines.calls, "the engines must not run while the GPU is busy")


# --------------------------------------------------------------------------- blobs

@test
def test_blob_upload_is_hash_verified_and_idempotent():
    with Env() as e:
        data = os.urandom(5000)
        digest = sha(data)
        path = f"/v1/blobs/{digest}"
        r = e.client.head(path, headers=e.auth)
        check(r.status_code == 404 and r.headers["upload-offset"] == "0", f"{r.status_code} {dict(r.headers)}")

        r = e.client.put(path, content=data, headers=e.auth)
        check(r.status_code == 201, f"{r.status_code} {r.text}")
        r = e.client.head(path, headers=e.auth)
        check(r.status_code == 200 and r.headers["content-length"] == str(len(data)), dict(r.headers))
        check(e.ctx.workspace.blob_path(digest).read_bytes() == data, "stored bytes")
        r = e.client.put(path, content=data, headers=e.auth)
        check(r.status_code == 204, "uploading a cached blob again is a no-op")


@test
def test_blob_with_the_wrong_hash_is_rejected_and_not_cached():
    with Env() as e:
        claimed = sha(b"what the phone says")
        r = e.client.put(f"/v1/blobs/{claimed}", content=b"what was actually sent", headers=e.auth)
        check(r.status_code == 422 and r.json()["error"]["code"] == "hash_mismatch", f"{r.status_code} {r.text}")
        check_schema("Error", r.json())
        check(not e.ctx.workspace.has_blob(claimed), "a corrupt upload must not enter the cache")
        check(e.ctx.workspace.partial_size(claimed) == 0, "and must not leave a partial behind")
        check(e.client.head(f"/v1/blobs/{claimed}", headers=e.auth).status_code == 404, "still missing")


@test
def test_blob_upload_resumes_with_content_range():
    with Env() as e:
        data = os.urandom(10_000)
        digest = sha(data)
        path = f"/v1/blobs/{digest}"
        total = len(data)

        r = e.client.put(path, content=data[:4000], headers={**e.auth, "Content-Range": f"bytes 0-3999/{total}"})
        check(r.status_code == 202 and r.headers["upload-offset"] == "4000", f"{r.status_code} {dict(r.headers)}")
        r = e.client.head(path, headers=e.auth)
        check(r.status_code == 404 and r.headers["upload-offset"] == "4000", "HEAD tells a resuming client where to continue")

        r = e.client.put(path, content=data[2000:6000], headers={**e.auth, "Content-Range": f"bytes 2000-5999/{total}"})
        check(r.status_code == 409 and r.json()["error"]["code"] == "offset_mismatch", f"{r.status_code} {r.text}")
        check(r.headers["upload-offset"] == "4000" and r.json()["error"]["retryable"], "409 carries the real offset")
        check_schema("Error", r.json())

        r = e.client.put(path, content=data[4000:7000], headers={**e.auth, "Content-Range": f"bytes 4000-6999/{total}"})
        check(r.status_code == 202 and r.headers["upload-offset"] == "7000", r.headers)
        r = e.client.put(path, content=data[7000:], headers={**e.auth, "Content-Range": f"bytes 7000-9999/{total}"})
        check(r.status_code == 201, f"{r.status_code} {r.text}")
        check(e.ctx.workspace.blob_path(digest).read_bytes() == data, "reassembled bytes")
        check(e.ctx.workspace.partial_size(digest) == 0, "no partial left")


@test
def test_blob_resume_survives_a_lost_hash_state_and_a_corrupt_chunk_is_caught_at_the_end():
    with Env() as e:
        data = os.urandom(6000)
        digest = sha(data)
        path = f"/v1/blobs/{digest}"
        e.client.put(path, content=data[:3000], headers={**e.auth, "Content-Range": "bytes 0-2999/6000"})
        # simulate a server restart between chunks (in-memory hash state gone, partial file stays)
        from mobile_api.app import create_app
        e.client = TestClient(create_app(e.ctx), raise_server_exceptions=False)
        r = e.client.put(path, content=data[3000:], headers={**e.auth, "Content-Range": "bytes 3000-5999/6000"})
        check(r.status_code == 201, f"resume after losing the in-memory hash: {r.status_code} {r.text}")

        bad = os.urandom(6000)
        bd = sha(bad)
        e.client.put(f"/v1/blobs/{bd}", content=b"X" * 3000, headers={**e.auth, "Content-Range": "bytes 0-2999/6000"})
        r = e.client.put(f"/v1/blobs/{bd}", content=bad[3000:], headers={**e.auth, "Content-Range": "bytes 3000-5999/6000"})
        check(r.status_code == 422 and not e.ctx.workspace.has_blob(bd), "a corrupt first chunk fails the final hash check")


@test
def test_blob_limits_and_bad_requests():
    with Env(max_upload_bytes=10_000, blob_cache_bytes=20_000) as e:
        digest = "b" * 64
        r = e.client.put(f"/v1/blobs/{digest}", content=b"x", headers={**e.auth, "Content-Range": "bytes 0-0/50000"})
        check(r.status_code == 413 and r.json()["error"]["code"] == "too_large", f"{r.status_code} {r.text}")
        r = e.client.put(f"/v1/blobs/{digest}", content=b"x", headers={**e.auth, "Content-Range": "garbage"})
        check(r.status_code == 400, f"bad Content-Range: {r.status_code}")
        r = e.client.put(f"/v1/blobs/{digest}", content=b"x", headers={**e.auth, "Content-Range": "bytes 0-9/10"})
        check(r.status_code == 400, f"short chunk vs its Content-Range: {r.status_code}")
        for bad in ("short", "G" * 64, "../" * 10, "A" * 64):
            r = e.client.head(f"/v1/blobs/{bad}", headers=e.auth)
            check(r.status_code in (400, 404), f"{bad!r}: {r.status_code}")
        r = e.client.put(f"/v1/blobs/{'G' * 64}", content=b"x", headers=e.auth)
        check(r.status_code == 400 and r.json()["error"]["code"] == "bad_request", r.text)
        check_schema("Error", r.json())


@test
def test_blob_cache_evicts_least_recently_used_and_never_the_new_blob():
    with Env(blob_cache_bytes=2500, max_upload_bytes=2500) as e:
        blobs = {n: bytes([i]) * 1000 for i, n in enumerate("abc")}
        ids = {n: sha(b) for n, b in blobs.items()}
        for n in "ab":
            check(e.client.put(f"/v1/blobs/{ids[n]}", content=blobs[n], headers=e.auth).status_code == 201, n)
            os.utime(e.ctx.workspace.blob_path(ids[n]), (1000 + "ab".index(n),) * 2)  # make the order unambiguous
        check(e.client.head(f"/v1/blobs/{ids['a']}", headers=e.auth).status_code == 200, "touching a makes it recent")
        check(e.client.put(f"/v1/blobs/{ids['c']}", content=blobs["c"], headers=e.auth).status_code == 201, "c")
        check(e.ctx.workspace.has_blob(ids["a"]), "a was used recently and stays")
        check(not e.ctx.workspace.has_blob(ids["b"]), "b was least recently used and is evicted")
        check(e.ctx.workspace.has_blob(ids["c"]), "the blob that was just uploaded stays")
        check(e.ctx.workspace.cache_bytes() <= 2500, "cache within its cap")
        # the phone just uploads b again
        check(e.client.put(f"/v1/blobs/{ids['b']}", content=blobs["b"], headers=e.auth).status_code == 201, "re-upload")


@test
def test_missing_blobs_error_matches_the_contract_shape():
    from mobile_api.errors import ApiError
    with Env() as e:
        missing = e.ctx.workspace.missing([sha(b"one"), sha(b"two"), sha(b"one")])
        check(len(missing) == 2, "duplicates collapse")
        body = ApiError(409, "missing_blobs", "2 input blobs are not cached on the server.", retryable=True,
                        extra={"missing": missing}).body()
        check_schema("MissingBlobsError", body)
        same_keys(body, fixture("MissingBlobsError.reface"))


# --------------------------------------------------------------------------- analyze

def _analyze(e, data=None, options=None, headers=None):
    files = {"image": ("photo.jpg", data if data is not None else jpeg_bytes(), "image/jpeg")}
    form = {} if options is None else {"options": options if isinstance(options, str) else json.dumps(options)}
    return e.client.post("/v1/analyze/image", files=files, data=form, headers=headers or e.auth)


@test
def test_analyze_image_response_matches_the_contract_and_the_golden_fixture():
    with Env() as e:
        r = _analyze(e)
        check(r.status_code == 200, f"{r.status_code} {r.text[:300]}")
        body = r.json()
        check_schema("AnalyzeImageResponse", body)
        golden = fixture("AnalyzeImageResponse.two_faces_one_body")
        same_keys({k: v for k, v in body.items() if k != "timings_ms"},
                  {k: v for k, v in golden.items() if k != "timings_ms"})  # timing stage names are engine-specific
        check(all(isinstance(v, (int, float)) for v in body["timings_ms"].values()), "timings are numbers")
        same_keys(body["faces"][0], golden["faces"][0], "$.faces[0]")
        same_keys(body["faces"][0]["quality"], golden["faces"][0]["quality"], "$.faces[0].quality")
        same_keys(body["bodies"][0], golden["bodies"][0], "$.bodies[0]")
        check((body["image_w"], body["image_h"]) == (640, 480) and body["model_id"] == "buffalo_l@1", "size + model")
        check(len(body["faces"]) == 2 and len(body["bodies"]) == 1 and len(body["pairs"]) == 1, "counts")
        check([f["passes_gate"] for f in body["faces"]] == [True, False], "gate flags")
        check(body["faces"][0]["crop_jpeg"] and body["faces"][1]["crop_jpeg"] is None,
              "crops only for faces the phone will store")
        crop = cv2.imdecode(np.frombuffer(base64.b64decode(body["faces"][0]["crop_jpeg"]), np.uint8), cv2.IMREAD_COLOR)
        check(crop is not None and max(crop.shape[:2]) <= 256, f"face crop must be a JPEG of at most 256px: {None if crop is None else crop.shape}")
        check(body["bodies"][0]["crop_jpeg"] and len(body["bodies"][0]["appearance"]) == 80, "body crop + descriptor")
        check(body["pairs"][0] == {"face_index": 0, "body_index": 0, "score": body["pairs"][0]["score"]}, "pair")
        for f in body["faces"]:
            raw = np.frombuffer(base64.b64decode(f["embedding"]), dtype="<f4")
            check(raw.shape == (512,) and abs(float(np.linalg.norm(raw)) - 1.0) < 1e-3, "embedding is 512 unit float32")
            check(f["bbox"]["w"] > 0 and f["bbox"]["h"] > 0, "bbox")


@test
def test_analyze_options_are_honoured():
    with Env() as e:
        golden_opts = fixture("AnalyzeImageOptions.default")
        check_schema("AnalyzeImageOptions", golden_opts)
        r = _analyze(e, options=golden_opts)
        check(r.status_code == 200, r.text)

        r = _analyze(e, options={"return_crops": False, "detect_bodies": False, "min_quality": 0.9, "body_score": 0.8})
        body = r.json()
        check(r.status_code == 200, r.text)
        check(all(f["crop_jpeg"] is None for f in body["faces"]), "return_crops=false")
        check(body["bodies"] == [] and body["pairs"] == [], "detect_bodies=false")
        check(all(not f["passes_gate"] for f in body["faces"]), "min_quality=0.9 gates every fake face out")
        last = e.ctx.engines.calls[-1]
        check((last.detect_bodies, last.min_face_quality, last.body_score) == (False, 0.9, 0.8), last)

        for bad in ("{not json", "[1]", json.dumps({"min_quality": 7}), json.dumps({"detect_bodies": "yes"}),
                    json.dumps({"min_quality": "high"})):
            r = _analyze(e, options=bad)
            check(r.status_code == 400 and r.json()["error"]["code"] == "bad_request", f"{bad}: {r.status_code} {r.text}")


@test
def test_analyze_rejects_a_different_embedding_model_and_unreadable_or_oversized_images():
    with Env() as e:
        r = _analyze(e, options={"model_id": "arcface@9"})
        check(r.status_code == 409 and r.json()["error"]["code"] == "model_mismatch", f"{r.status_code} {r.text}")
        check_schema("Error", r.json())
        check(_analyze(e, options={"model_id": "buffalo_l@1"}).status_code == 200, "matching model is fine")

        r = _analyze(e, data=b"this is not an image")
        check(r.status_code == 400 and r.json()["error"]["code"] == "bad_image", f"{r.status_code} {r.text}")

        e.ctx.max_image_px = 500
        r = _analyze(e, data=jpeg_bytes(640, 480))
        check(r.status_code == 413 and r.json()["error"]["code"] == "too_large", f"{r.status_code} {r.text}")
        check_schema("Error", r.json())

        e.ctx.max_image_px = 4096
        e.ctx.max_image_upload_bytes = 1000
        r = _analyze(e)
        check(r.status_code == 413, f"upload size cap: {r.status_code}")

        r = e.client.post("/v1/analyze/image", data={"options": "{}"}, headers=e.auth)  # no file part
        check(r.status_code == 400 and r.json()["error"]["code"] == "bad_request", f"{r.status_code} {r.text}")


# --------------------------------------------------------------------------- pairing page, tls, discovery, workspace

@test
def test_pairing_page_is_localhost_only_and_its_qr_carries_the_pinned_fingerprint():
    from mobile_api.pair_ui import create_pair_app
    from mobile_api.pairing import parse_payload
    from mobile_api.tls import ensure_cert
    with Env() as e:
        cert = ensure_cert(e.ctx.workspace.tls_dir, hosts=["192.168.1.20"])
        e.ctx.cert = cert
        pair_app = create_pair_app(e.ctx, addresses_fn=lambda: ["192.168.1.20", "10.1.1.5"])

        remote = TestClient(pair_app, client=("192.168.1.77", 5000))
        check(remote.get("/pair").status_code == 404, "a LAN client must not see the pairing page")
        check(TestClient(pair_app).get("/pair", headers={"host": "evil.example"}).status_code == 403, "DNS rebinding guard")
        check(TestClient(pair_app).post("/pair/new", headers={"origin": "http://evil.example"}).status_code == 403,
              "cross-site form post guard")

        local = TestClient(pair_app)
        r = local.get("/pair")
        check(r.status_code == 200 and "text/html" in r.headers["content-type"], r.status_code)
        check(r.headers["cache-control"] == "no-store", "never cache a page holding a code")
        code = e.ctx.pairing.current()
        check(code is not None and code.code in r.text, "the page shows the current one-time code")

        png_b64 = r.text.split("data:image/png;base64,")[1].split('"')[0]
        qr = cv2.imdecode(np.frombuffer(base64.b64decode(png_b64), np.uint8), cv2.IMREAD_GRAYSCALE)
        text, _, _ = cv2.QRCodeDetector().detectAndDecode(cv2.copyMakeBorder(qr, 40, 40, 40, 40, cv2.BORDER_CONSTANT, value=255))
        check(text.startswith("agmobile://pair?"), f"QR payload: {text!r}")
        fields = parse_payload(text)
        check(fields == {"h": "192.168.1.20", "p": "8443", "fp": cert.fingerprint, "c": code.code}, fields)

        r = local.get("/pair?h=10.0.2.2")
        check("10.0.2.2" in r.text, "the page can target another address (emulator)")
        before = e.ctx.pairing.current().code
        local.post("/pair/new", follow_redirects=False)
        check(e.ctx.pairing.current().code != before, "New code issues a fresh code")

        # the API app never serves the page, the pair app never serves the API
        check(e.client.get("/pair").status_code == 404, "the HTTPS API must not serve /pair")
        check(local.get("/v1/health").status_code == 404, "the pairing app must not serve the API")


@test
def test_tls_certificate_is_generated_once_persisted_and_fingerprinted():
    from cryptography import x509
    from cryptography.hazmat.primitives import serialization
    from mobile_api.tls import ensure_cert, fingerprint_of_pem_file
    tmp = Path(tempfile.mkdtemp(prefix="mobile_api_tls_"))
    try:
        a = ensure_cert(tmp / "tls", hosts=["192.168.1.20"])
        check(a.cert_path.is_file() and a.key_path.is_file(), "files written")
        check(len(a.fingerprint) == 64 and a.fingerprint == a.fingerprint.lower(), a.fingerprint)
        cert = x509.load_pem_x509_certificate(a.cert_path.read_bytes())
        check(hashlib.sha256(cert.public_bytes(serialization.Encoding.DER)).hexdigest() == a.fingerprint,
              "fingerprint is the SHA-256 of the DER certificate")
        sans = cert.extensions.get_extension_for_class(x509.SubjectAlternativeName).value
        ips = {str(i) for i in sans.get_values_for_type(x509.IPAddress)}
        check({"127.0.0.1", "10.0.2.2", "192.168.1.20"} <= ips, f"SANs: {ips}")

        b = ensure_cert(tmp / "tls", hosts=["192.168.1.99"])  # IP changed: must NOT regenerate (would unpair phones)
        check(b.fingerprint == a.fingerprint, "an existing certificate is reused")
        a.key_path.write_text("garbage")
        c = ensure_cert(tmp / "tls")
        check(c.fingerprint != a.fingerprint and fingerprint_of_pem_file(c.cert_path) == c.fingerprint,
              "an unusable key triggers regeneration")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@test
def test_mdns_advertises_the_service_without_a_fingerprint():
    import types
    calls = {}

    class Info:
        def __init__(self, type_, name, addresses, port, properties, server):
            calls["info"] = dict(type_=type_, name=name, addresses=addresses, port=port, properties=properties, server=server)

    class Zc:
        def register_service(self, info):
            calls["registered"] = info

        def unregister_service(self, info):
            calls["unregistered"] = info

        def close(self):
            calls["closed"] = True

    fake = types.SimpleNamespace(ServiceInfo=Info, Zeroconf=Zc)
    saved = sys.modules.get("zeroconf")
    sys.modules["zeroconf"] = fake
    try:
        from mobile_api.discovery import SERVICE_TYPE, Discovery
        d = Discovery(log=lambda *_: None)
        ok = d.start(name="Studio PC!", server_id="srv_12345678", api_version="1.0.0", port=8443,
                     addresses=["192.168.1.20"])
        check(ok and calls["info"]["type_"] == "_antigravity._tcp.local." == SERVICE_TYPE, calls)
        check(calls["info"]["name"] == "Studio PC._antigravity._tcp.local.", calls["info"]["name"])
        props = calls["info"]["properties"]
        check(props["server_id"] == "srv_12345678" and "fp" not in props and not any("fingerprint" in k for k in props),
              f"mDNS is unauthenticated - it must not carry the certificate fingerprint: {props}")
        check(calls["info"]["port"] == 8443, "port")
        d.stop()
        check(calls.get("unregistered") and calls.get("closed"), "stop() unregisters and closes")
    finally:
        if saved is None:
            sys.modules.pop("zeroconf", None)
        else:
            sys.modules["zeroconf"] = saved


@test
def test_workspace_wipes_on_start_but_keeps_devices_and_certificate_and_refuses_foreign_folders():
    from mobile_api.workspace import Workspace, WorkspaceError
    tmp = Path(tempfile.mkdtemp(prefix="mobile_api_ws_"))
    try:
        foreign = tmp / "foreign"
        foreign.mkdir()
        (foreign / "precious.txt").write_text("keep me")
        try:
            Workspace(foreign).prepare()
            raise AssertionError("must refuse a non-empty folder it did not create")
        except WorkspaceError:
            pass
        check((foreign / "precious.txt").exists(), "nothing was deleted")

        ws = Workspace(tmp / "ws")
        ws.prepare()
        ws.devices_path.write_text('{"server_id": "srv_x"}')
        (ws.tls_dir / "server.crt").write_text("cert")
        digest = sha(b"abc")
        ws.blob_path(digest).parent.mkdir(parents=True, exist_ok=True)
        ws.blob_path(digest).write_bytes(b"abc")
        (ws.uploads_dir / f"{'c' * 64}.part").write_bytes(b"half")
        ws.job_dir("job1", create=True)
        (tmp / "ws" / "stray.txt").write_text("x")

        again = Workspace(tmp / "ws")
        again.prepare()
        check(again.devices_path.read_text() == '{"server_id": "srv_x"}' and (again.tls_dir / "server.crt").exists(),
              "devices.json and the certificate persist")
        check(not again.has_blob(digest) and not list(again.uploads_dir.iterdir()) and not list(again.jobs_dir.iterdir())
              and not (tmp / "ws" / "stray.txt").exists(), "blobs, partials, jobs and strays are wiped")
        check(again.blobs_dir.is_dir() and again.jobs_dir.is_dir(), "folders recreated")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@test
def test_job_dirs_are_purged_on_ack_and_after_the_ttl():
    from mobile_api.workspace import Workspace
    tmp = Path(tempfile.mkdtemp(prefix="mobile_api_ws_"))
    try:
        ws = Workspace(tmp / "ws")
        ws.prepare()
        a, b = ws.job_dir("acked", create=True), ws.job_dir("forgotten", create=True)
        (a / "result.png").write_bytes(b"x")
        (b / "result.png").write_bytes(b"x")
        check(ws.purge_job("acked") and not a.exists(), "ACK purges the job dir")
        check(not ws.purge_job("acked"), "purging twice is harmless")
        import time
        check(ws.purge_expired_jobs(ttl_seconds=3600) == [], "fresh jobs stay")
        check(ws.purge_expired_jobs(ttl_seconds=3600, now=time.time() + 7200) == ["forgotten"] and not b.exists(),
              "an un-ACKed job is removed after the TTL")
        try:
            ws.job_dir("../escape")
            raise AssertionError("job ids must not allow path traversal")
        except Exception as err:
            check("bad job id" in str(err), str(err))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# --------------------------------------------------------------------------- grouping plan

GROUPING_GOLDEN = ["apply_basic", "review_all", "review_distinct_pair"]


def _big_grouping_request(n_pending=160):
    """One known person and many loose faces that clearly belong to them: a response of ~15 KB."""
    rng = np.random.default_rng(11)

    def unit(v):
        return v / np.linalg.norm(v)

    def enc(v):
        return base64.b64encode(np.asarray(v, dtype="<f4").tobytes()).decode("ascii")

    proto = unit(rng.standard_normal(512))
    members = [unit(proto + 0.5 * unit(rng.standard_normal(512))) for _ in range(10)]
    return {
        "mode": "review", "stages": ["match", "cluster"], "strictness": "loose",
        "models": [{"pid": 7, "proto": enc(proto), "members": [enc(m) for m in members], "count": 10}],
        "pending": [{"id": 1000 + i, "embedding": enc(unit(proto + 0.5 * unit(rng.standard_normal(512)))),
                     "quality": 0.8, "frame_key": f"{i}:", "rejected_person_ids": []} for i in range(n_pending)],
        "distinct_pairs": [], "bodies": [], "max_suggestions_per_person": 200,
    }


@test
def test_grouping_plan_needs_a_token_never_needs_the_gpu_and_matches_the_golden_fixtures():
    with Env() as e:
        r = e.client.post("/v1/grouping/plan", json=fixture("GroupingPlanRequest.apply_basic"))
        check(r.status_code == 401, f"no token: {r.status_code}")
        # CPU only: a heavy job holding the GPU must not matter
        _start_job(e.ctx.gpu.dashboard_jobs_dir, "train_lora", "dash0004")
        check(e.ctx.gpu.busy() is not None, "the GPU is busy for this test")
        for name in GROUPING_GOLDEN:
            r = e.client.post("/v1/grouping/plan", json=fixture(f"GroupingPlanRequest.{name}"), headers=e.auth)
            check(r.status_code == 200, f"{name}: {r.status_code} {r.text[:200]}")
            check_schema("GroupingPlanResponse", r.json(), name)
            check(r.json() == fixture(f"GroupingPlanResponse.{name}"), f"{name}: differs from the golden response")


@test
def test_grouping_plan_accepts_gzip_bodies_and_gzips_big_answers():
    import gzip
    with Env() as e:
        req = _big_grouping_request()
        body = json.dumps(req).encode()
        plain = e.client.post("/v1/grouping/plan", content=body, headers={**e.auth, "Content-Type": "application/json"})
        check(plain.status_code == 200, f"{plain.status_code} {plain.text[:200]}")
        check_schema("GroupingPlanResponse", plain.json())
        check(len(plain.json()["assignments"]) > 100, "most loose faces should be matched to the known person")

        zipped = gzip.compress(body)
        check(len(zipped) < len(body), "gzip should shrink the request")
        r = e.client.post("/v1/grouping/plan", content=zipped, headers={
            **e.auth, "Content-Type": "application/json", "Content-Encoding": "gzip", "Accept-Encoding": "gzip"})
        check(r.status_code == 200, f"{r.status_code} {r.text[:200]}")
        check(r.headers.get("content-encoding") == "gzip", f"a big answer is gzipped: {dict(r.headers)}")
        check(r.json() == plain.json(), "gzip in/out must not change the answer")

        small = e.client.post("/v1/grouping/plan", json=fixture("GroupingPlanRequest.apply_basic"),
                              headers={**e.auth, "Accept-Encoding": "identity"})
        check(small.headers.get("content-encoding") in (None, "identity"), "no gzip unless the client accepts it")


@test
def test_grouping_plan_rejects_bad_bodies_with_the_error_envelope():
    import gzip
    with Env() as e:
        good = fixture("GroupingPlanRequest.apply_basic")

        def post(content=None, json_body=None, **headers):
            h = {**e.auth, **headers}
            if json_body is not None:
                return e.client.post("/v1/grouping/plan", json=json_body, headers=h)
            return e.client.post("/v1/grouping/plan", content=content, headers={"Content-Type": "application/json", **h})

        r = post(b"{not json")
        check(r.status_code == 400 and r.json()["error"]["code"] == "bad_request", r.text)
        check_schema("Error", r.json())
        r = post(b"\x1f\x8b garbage", **{"Content-Encoding": "gzip"})
        check(r.status_code == 400 and "gzip" in r.json()["error"]["message"], r.text)
        r = post(b"{}", **{"Content-Encoding": "br"})
        check(r.status_code == 400, f"unsupported encoding: {r.status_code}")
        for mutate, part in ((lambda d: d.__setitem__("stages", ["match", "telepathy"]), "stages"),
                             (lambda d: d.__setitem__("strictness", "reckless"), "strictness"),
                             (lambda d: d["models"][0].__setitem__("proto", "AAAA"), "proto"),
                             (lambda d: d.__setitem__("stages", ["duplicates"]), "duplicates")):
            bad = json.loads(json.dumps(good))
            mutate(bad)
            r = post(json_body=bad)
            check(r.status_code == 400 and part in r.json()["error"]["message"], f"{part}: {r.status_code} {r.text[:200]}")
        r = post(b"[1, 2]")
        check(r.status_code == 400, f"a JSON array: {r.status_code}")

        # size limits: the compressed size, and the inflated size (a gzip bomb)
        e.ctx.max_plan_wire_bytes = 2000
        r = post(json.dumps(good).encode())
        check(r.status_code == 413 and r.json()["error"]["code"] == "too_large", f"{r.status_code} {r.text[:200]}")
        e.ctx.max_plan_wire_bytes = 10 * 1024 * 1024
        e.ctx.max_plan_json_bytes = 50_000
        bomb = gzip.compress(b" " * 5_000_000)
        check(len(bomb) < 10_000, "the bomb is tiny on the wire")
        r = post(bomb, **{"Content-Encoding": "gzip"})
        check(r.status_code == 413, f"inflated size must be capped: {r.status_code} {r.text[:200]}")


def main(argv):
    pattern = argv[0] if argv else ""
    selected = [t for t in _TESTS if pattern in t.__name__]
    if not selected:
        print(f"No test matches '{pattern}'.\nKnown: " + ", ".join(t.__name__ for t in _TESTS))
        return 1
    failed = 0
    for t in selected:
        try:
            t()
            print(f"[PASS] {t.__name__}")
        except Exception as e:  # noqa: BLE001
            failed += 1
            print(f"[FAIL] {t.__name__}: {e}")
            traceback.print_exc()
    print(f"\n{len(selected) - failed}/{len(selected)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
