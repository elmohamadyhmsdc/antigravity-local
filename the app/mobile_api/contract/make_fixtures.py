"""
Regenerates the golden fixtures in ./fixtures - deterministic (fixed seed).

Every fixture is named <SchemaName>.<variant>.json so validate_contract.py can
check it against components.schemas.<SchemaName> in openapi.yaml. The Flutter
tests parse the very same files (mobile/test/contract_fixtures_test.dart).

The grouping fixtures are REAL outputs: the request is built from seeded
vectors and the response is computed by grouping_core.plan_request - the very
code POST /v1/grouping/plan serves and the Streamlit gallery (gallery_grouping)
runs on. test_grouping_core.py regenerates them in a temp folder and requires
them to be byte-identical to the committed files.

Run from the app/ folder with the app's venv:
    venv\\Scripts\\python mobile_api\\contract\\make_fixtures.py
"""

import base64
import hashlib
import json
import sys
from pathlib import Path

import cv2
import numpy as np

HERE = Path(__file__).resolve().parent
APP = HERE.parents[1]  # the app/
sys.path.insert(0, str(APP))

import face_quality  # noqa: E402
import grouping_core  # noqa: E402
import person_linking as pl  # noqa: E402

OUT = HERE / "fixtures"
DIM = 512
rng = np.random.default_rng(20261011)


# --------------------------------------------------------------------------- helpers

def unit(v):
    v = np.asarray(v, dtype=np.float32)
    return v / np.linalg.norm(v)


def noisy(proto, s=0.8):
    """A face of the person: cos(face, proto) ~ 0.78, cos(face, other face of same person) ~ 0.6."""
    return unit(proto + s * unit(rng.standard_normal(DIM)))


def b64(v):
    return base64.b64encode(np.asarray(v, dtype="<f4").tobytes()).decode("ascii")


def unb64(s):
    return np.frombuffer(base64.b64decode(s), dtype="<f4").copy()


def jpeg_b64(bgr, size=16):
    img = np.full((size, size, 3), bgr, dtype=np.uint8)
    ok, buf = cv2.imencode(".jpg", img)
    assert ok
    return base64.b64encode(buf.tobytes()).decode("ascii")


def sha(label):
    return hashlib.sha256(label.encode()).hexdigest()


def write(name, obj):
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f"{name}.json").write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("wrote", name)


def quality(face_px, emb_norm, sharp, yaw, pitch, roll=0.0, det=0.9):
    parts = face_quality.components(face_px, emb_norm, sharp, yaw, pitch)
    return {
        "quality_score": face_quality.score(parts),
        "quality_version": face_quality.QUALITY_VERSION,
        "quality_parts": {k: round(v, 3) for k, v in parts.items()},
        "det_score": det,
        "face_px": face_px,
        "sharpness": sharp,
        "embedding_norm": emb_norm,
        "pose": {"yaw": yaw, "pitch": pitch, "roll": roll},
    }


def hellinger_descriptor(torso_seed_vec=None, legs_seed_vec=None):
    """80 floats: two unit-norm non-negative 40-bin regions (the shape appearance_descriptor returns)."""
    regions = []
    for given in (torso_seed_vec, legs_seed_vec):
        v = np.abs(rng.standard_normal(pl.REGION_LEN)).astype(np.float32) if given is None else given
        regions.append(unit(v))
    return np.concatenate(regions)


def blend_to_similarity(a, target):
    """A descriptor whose appearance_similarity to `a` is ~target (bisection on the mix)."""
    other = hellinger_descriptor()
    lo, hi = 0.0, 1.0  # weight of `a`
    best = a
    for _ in range(40):
        mid = (lo + hi) / 2
        regs = []
        for r in range(2):
            sl = slice(r * pl.REGION_LEN, (r + 1) * pl.REGION_LEN)
            regs.append(unit(mid * a[sl] + (1 - mid) * other[sl]))
        cand = np.concatenate(regs)
        sim = pl.appearance_similarity(a, cand)
        best = cand
        if sim < target:
            lo = mid
        else:
            hi = mid
    return best


# --------------------------------------------------------------------------- simple fixtures

def system_fixtures():
    write("Health.ok", {"status": "ok", "server_id": "srv_7f3a91c2", "name": "RTX-PC", "api_version": "1.0.0"})
    caps = {
        "api_version": "1.0.0",
        "server_id": "srv_7f3a91c2",
        "name": "RTX-PC",
        "embedding_model": {"id": "buffalo_l@1", "dim": 512},
        "gpu": {"name": "NVIDIA GeForce RTX 3060 Laptop GPU", "vram_total_mb": 6144, "vram_free_mb": 5320},
        "engines": {
            "reface_v3": True, "reface_v2": True, "dfm_models": ["RTM_WF_224"],
            "undress": True, "lora_train": True, "lora_generate": True, "body_detection": True,
        },
        "restorers": ["codeformer"],
        "lora_base_checkpoints": ["sd15_realistic_base"],
        "limits": {"max_image_px": 4096, "max_upload_mb": 2048, "blob_cache_mb": 20480},
        "busy": None,
    }
    write("Capabilities.idle", caps)
    busy = dict(caps, busy={"job_id": "9c1d2e84-aaaa-4bbb-8ccc-0123456789ab", "job_type": "reface_video_v3", "source": "dashboard"})
    write("Capabilities.busy_with_dashboard_job", busy)
    write("PairResponse.ok", {"token": "agm_" + sha("device-token")[:40], "server_id": "srv_7f3a91c2", "server_name": "RTX-PC"})
    write("Error.gpu_busy", {"error": {"code": "gpu_busy", "message": "A reface_video_v3 job is running on the GPU.", "retryable": True}})
    write("Error.invalid_code", {"error": {"code": "invalid_code", "message": "Wrong pairing code (4 attempts left).", "retryable": False}})
    write("PairRequest.ok", {"code": "K7QM-3XRD", "device_name": "Pixel 8"})
    write("AnalyzeImageOptions.default", {"detect_bodies": True, "min_quality": 0.4, "return_crops": True,
                                          "body_score": 0.5, "model_id": "buffalo_l@1"})
    write("MissingBlobsError.reface", {
        "error": {"code": "missing_blobs", "message": "1 input blob is not cached on the server.", "retryable": True},
        "missing": [sha("target-photo")],
    })


# --------------------------------------------------------------------------- analyze

def analyze_fixture():
    face_a = {
        "bbox": {"x": 412.5, "y": 188.0, "w": 176.0, "h": 214.5},
        "kps": [[455.1, 262.3], [540.2, 258.9], [498.7, 304.4], [462.0, 345.8], [534.6, 342.1]],
        "det_score": 0.9312,
        "embedding": b64(unit(rng.standard_normal(DIM))),
        "quality": quality(176.0, 22.4, 310.5, 6.2, -3.1, 1.4, det=0.9312),
        "crop_jpeg": jpeg_b64((120, 150, 190)),
    }
    face_a["passes_gate"] = True
    face_b = {
        "bbox": {"x": 905.0, "y": 240.0, "w": 28.0, "h": 34.0},
        "kps": [[913.0, 252.0], [926.0, 252.5], [919.5, 259.0], [914.0, 265.0], [925.0, 265.5]],
        "det_score": 0.58,
        "embedding": b64(unit(rng.standard_normal(DIM))),
        "quality": quality(28.0, 17.8, 22.0, 38.0, 12.0, 0.0, det=0.58),
        "crop_jpeg": None,
        "passes_gate": False,
    }
    appearance = hellinger_descriptor()
    kpts = [[500.0 + 3 * i, 230.0 + 24 * i, 0.9 if i < 13 else 0.12] for i in range(17)]
    body = {
        "bbox": {"x": 330.0, "y": 150.0, "w": 340.0, "h": 780.0},
        "score": 0.9121,
        "kpts": kpts,
        "appearance": [round(float(x), 4) for x in appearance],
        "extent": pl.body_extent([k[2] for k in kpts]),
        "crop_jpeg": jpeg_b64((90, 60, 40)),
    }
    write("AnalyzeImageResponse.two_faces_one_body", {
        "model_id": "buffalo_l@1",
        "image_w": 1280,
        "image_h": 960,
        "faces": [face_a, face_b],
        "bodies": [body],
        "pairs": [{"face_index": 0, "body_index": 0, "score": 0.82}],
        "timings_ms": {"detect": 41.2, "embed": 18.7, "body": 63.9},
    })
    write("AnalyzeImageResponse.no_faces", {
        "model_id": "buffalo_l@1", "image_w": 640, "image_h": 480,
        "faces": [], "bodies": [], "pairs": [],
    })


# --------------------------------------------------------------------------- grouping

def plan(req):
    """The GroupingPlanResponse for a request: exactly what POST /v1/grouping/plan answers."""
    return grouping_core.plan_request(req)


def grouping_fixtures():
    # Three identities. 1 and 2 are known people; 3 is a new person seen three times.
    protos = {pid: unit(rng.standard_normal(DIM)) for pid in (1, 2, 3)}
    # Person 4 is a near-duplicate of person 1 (an alias the user may want to merge).
    protos[4] = unit(protos[1] + 0.55 * unit(rng.standard_normal(DIM)))

    faces, pids, quals = [], [], []
    for pid, n in ((1, 6), (2, 5), (4, 4)):
        for _ in range(n):
            faces.append(noisy(protos[pid]))
            pids.append(pid)
            quals.append(round(float(rng.uniform(0.55, 0.9)), 3))
    models = pl.build_person_models(np.stack(faces), pids, quals)
    models_json = [
        {"pid": pid, "proto": b64(m.proto), "members": [b64(x) for x in m.members], "count": int(m.count)}
        for pid, m in sorted(models.items())
    ]

    def pending(fid, proto, key, q=None, rejected=()):
        return {"id": fid, "embedding": b64(noisy(proto)), "quality": q or round(float(rng.uniform(0.6, 0.9)), 3),
                "frame_key": key, "rejected_person_ids": list(rejected)}

    pend = [
        pending(101, protos[1], "10:"),                    # clearly person 1 -> auto
        pending(102, protos[2], "11:"),                    # clearly person 2 -> auto
        pending(103, protos[3], "12:"),                    # three faces of a new person
        pending(104, protos[3], "13:"),
        pending(105, protos[3], "14:"),
        pending(106, protos[1], "15:", rejected=(1, 4)),   # looks like person 1 but the user said "not them"
        {"id": 107, "embedding": b64(unit(rng.standard_normal(DIM))), "quality": 0.5,
         "frame_key": None, "rejected_person_ids": []},    # a stranger seen once
    ]

    # Bodies in one video (media 20): body 1 is known (person 1), 2 and 3 have no usable face.
    outfit = hellinger_descriptor()
    bodies = [
        {"id": 1, "media_id": 20, "frame_number": 30, "anchor_person_id": 1,
         "appearance": [round(float(x), 4) for x in outfit], "rejected_person_ids": []},
        {"id": 2, "media_id": 20, "frame_number": 90, "anchor_person_id": None,
         "appearance": [round(float(x), 4) for x in blend_to_similarity(outfit, 0.94)], "rejected_person_ids": []},
        {"id": 3, "media_id": 20, "frame_number": 150, "anchor_person_id": None,
         "appearance": [round(float(x), 4) for x in blend_to_similarity(outfit, 0.82)], "rejected_person_ids": []},
    ]

    base = {"strictness": "balanced", "models": models_json, "pending": pend, "dismissed_face_ids": [],
            "distinct_pairs": [], "bodies": bodies, "max_suggestions_per_person": 60}

    apply_req = dict(base, mode="apply", stages=["match", "cluster", "bodies"])
    review_req = dict(base, mode="review", stages=["match", "cluster", "duplicates", "bodies"])
    for name, req in (("apply_basic", apply_req), ("review_all", review_req)):
        write(f"GroupingPlanRequest.{name}", req)
        write(f"GroupingPlanResponse.{name}", plan(req))

    # Same request but the user already said persons 1 and 4 are different people.
    distinct = dict(review_req, distinct_pairs=[[1, 4]])
    write("GroupingPlanRequest.review_distinct_pair", distinct)
    write("GroupingPlanResponse.review_distinct_pair", plan(distinct))


# --------------------------------------------------------------------------- jobs

def job_fixtures():
    def src(q, yaw):
        return {"embedding": b64(unit(rng.standard_normal(DIM))), "quality": q,
                "pose": {"yaw": yaw, "pitch": 0.0, "roll": 0.0}}

    write("JobCreate.reface_image_v3", {
        "client_job_id": "c0a8e6f2-1111-4a1b-9c1d-5a5a5a5a5a5a",
        "type": "reface_image_v3",
        "params": {
            "source_faces": [src(0.82, -4.0), src(0.77, 22.0)],
            "target_faces": [{"x": 412.5, "y": 188.0, "w": 176.0, "h": 214.5}],
            "restorer": "codeformer", "restorer_weight": 0.5,
            "use_parser": True, "use_occluder": True, "realism_preset": "natural",
        },
        "inputs": {"target": sha("target-photo")},
    })
    write("JobCreate.reface_video_dfm", {
        "client_job_id": "fixture-reface-video",
        "type": "reface_video_dfm",
        "params": {"source_faces": [], "dfm_model": "RTM_WF_224", "start_time": 2.5, "end_time": 14.0},
        "inputs": {"target": sha("target-video")},
    })
    write("JobCreate.analyze_video", {
        "type": "analyze_video",
        "params": {"frame_interval": 1.0, "min_quality": 0.4, "detect_bodies": True},
        "inputs": {"video": sha("holiday-video")},
    })
    write("JobCreate.undress_image", {
        "client_job_id": "fixture-restyle",
        "type": "undress_image",
        "params": {
            "face_bbox": {"x": 412.5, "y": 188.0, "w": 176.0, "h": 214.5},
            "prompt": "elegant white strapless cotton summer dress, photorealistic",
            "negative_prompt": "watermark, text, deformed hands",
            "seed": -1, "steps": 26, "guidance_scale": 6.0, "strength": 0.6,
            "refine": True, "refine_strength": 0.4, "refine_steps": 35,
        },
        "inputs": {"image": sha("photo-to-restyle"), "refs": [sha("ref-1")]},
    })
    write("JobCreate.build_lora_dataset", {
        "client_job_id": "fixture-dataset",
        "type": "build_lora_dataset",
        "params": {"trigger_word": "sks_sara", "repeats": 10, "anchor_embedding": b64(unit(np.arange(DIM,dtype=np.float32)))},
        "inputs": {"images": [sha("img-a"), sha("img-b"), sha("img-c")]},
    })
    write("JobCreate.train_lora", {
        "client_job_id": "fixture-training",
        "type": "train_lora",
        "params": {"output_name": "sara_v1", "trigger_word": "sks_sara", "base_checkpoint": "sd15_realistic_base",
                   "epochs": 10, "network_dim": 32, "network_alpha": 16,
                   "learning_rate": 0.0001, "batch_size": 1, "max_resolution": 512},
        "inputs": {"dataset": sha("dataset-zip")},
    })
    write("JobCreate.generate_lora_images", {
        "client_job_id": "fixture-generation",
        "type": "generate_lora_images",
        "params": {"trigger_word": "sks_sara", "base_checkpoint": "sd15_realistic_base", "num_images": 4, "seed": 1234, "steps": 30,
                   "reference_mode": "composition", "reference_strength": 0.6, "multi_angle": False},
        "inputs": {"lora": sha("sara-lora"), "reference": sha("pose-ref")},
    })

    base_status = {
        "job_id": "9c1d2e84-aaaa-4bbb-8ccc-0123456789ab", "client_job_id": "c0a8e6f2-1111-4a1b-9c1d-5a5a5a5a5a5a",
        "type": "reface_video_v3", "status": "running", "progress": 0.63,
        "message": "Processing frame 410/650 (63%)", "queue_position": 0,
        "created_at": "2026-10-11T12:30:05.120000", "started_at": "2026-10-11T12:30:09.004000",
        "completed_at": None, "error": None, "last_frame": 410, "frames_done": 410, "details": {}, "has_result": False,
    }
    write("JobStatus.running", base_status)
    write("JobStatus.queued", dict(base_status, status="queued", progress=0.0, message="Waiting in queue",
                                   queue_position=2, started_at=None, last_frame=0, frames_done=0))
    write("JobStatus.train_running", dict(
        base_status, type="train_lora", progress=0.42, message="epoch 5/10 - step 120/280", last_frame=0, frames_done=0,
        details={"stage": "Training", "epoch": 5, "total_epochs": 10, "step": 120, "total_steps": 280,
                 "loss": 0.0931, "seconds_per_step": 1.7}))
    write("JobStatus.failed", dict(
        base_status, status="failed", progress=0.0, message="Error: No faces found in source media!",
        completed_at="2026-10-11T12:31:00.000000", error="Traceback (most recent call last): ...", has_result=False))
    write("ResultManifest.reface_image", {
        "job_id": "9c1d2e84-aaaa-4bbb-8ccc-0123456789ab",
        "files": [{"name": "result.png", "size": 2481733, "sha256": sha("result-png"), "mime": "image/png"}],
        "meta": {"faces_swapped": 1},
    })

    write("JobCreate.reface_video_selected_preview", {
        "client_job_id": "fixture-video-selected-preview", "type": "reface_video_v3",
        "params": {"source_faces": [src(.85,0)], "target_embeddings": [src(.9,0)["embedding"]],
                   "target_indices": [0], "preview": True, "start_time": 2,
                   "identity_boost": .5, "swapper": "auto", "restorer": "none"},
        "inputs": {"target": sha("target-video")},
    })


if __name__ == "__main__":
    system_fixtures()
    analyze_fixture()
    grouping_fixtures()
    job_fixtures()
    print("done ->", OUT)
