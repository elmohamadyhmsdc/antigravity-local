"""
Roadmap section 8 (PC half): NudeNet regions, region -> body assignment, the analyze flag, the backfill
endpoint, the worker IPC shape. CPU only: fake engines, TestClient, a synthetic YOLOv8 tensor, and (when the
model file is installed) one real CPU inference on a synthetic picture. No server is started.

    venv\\Scripts\\python.exe test_mobile_sensitive.py
"""

import json
import sys
import traceback
from pathlib import Path

import cv2
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import sensitive_detection as sd  # noqa: E402

_TESTS = []


def test(fn):
    _TESTS.append(fn)
    return fn


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


def tensor(rows):
    """(1, 22, 8400) YOLOv8 output with the given (class, cx, cy, w, h, score) rows in 640 space."""
    out = np.zeros((1, 4 + len(sd.LABELS), 8400), dtype=np.float32)
    for i, (cls, cx, cy, w, h, score) in enumerate(rows):
        out[0, 0:4, i] = (cx, cy, w, h)
        out[0, 4 + cls, i] = score
    return out


@test
def test_labels_match_the_installed_model_metadata():
    check(len(sd.LABELS) == 18, "18 labels")
    check(sd.LABELS[3] == "FEMALE_BREAST_EXPOSED" and sd.LABELS[13] == "BELLY_EXPOSED", "order")
    for names in sd.SHORT_NAMES.values():
        check(all(n in sd.LABELS for n in names), names)
    check(sd.SENSITIVE_LABELS <= set(sd.LABELS), "sensitive labels are real labels")
    if sd.model_available():
        import onnxruntime as ort
        meta = ort.InferenceSession(str(sd.MODEL_PATH), providers=["CPUExecutionProvider"]).get_modelmeta()
        names = eval(meta.custom_metadata_map["names"])  # noqa: S307 - our own model's metadata
        check([names[i] for i in range(18)] == list(sd.LABELS), "label order == model metadata")


@test
def test_decode_scales_boxes_skips_faces_and_applies_nms():
    # image 1000 x 500 padded to 1000 x 1000: factor 1000 / 640
    rows = [(3, 320, 160, 64, 64, 0.9),      # exposed breast
            (3, 322, 160, 64, 64, 0.8),      # duplicate of the first -> NMS
            (1, 100, 100, 40, 40, 0.95),     # FACE_FEMALE: never returned
            (13, 500, 200, 80, 40, 0.1)]     # below the decode floor
    regions = sd.decode_output(tensor(rows), 1000 / 640, 1000, 500)
    check([r["label"] for r in regions] == ["FEMALE_BREAST_EXPOSED"], regions)
    r = regions[0]
    check(r["exposed"] is True and abs(r["score"] - 0.9) < 1e-5, r)
    x1, y1, x2, y2 = r["bbox"]
    check(abs(x1 - (320 - 32) * 1000 / 640) < 1 and abs(x2 - (320 + 32) * 1000 / 640) < 1, r["bbox"])
    check(y2 <= 500, "clipped to the picture height (the padding is not picture)")
    check(sd.decode_output(tensor([]), 1.0, 640, 640) == [], "empty tensor")


def region(label, cx, cy, size=40):
    return {"label": label, "exposed": label.endswith("_EXPOSED"), "score": 0.9,
            "bbox": [cx - size / 2, cy - size / 2, cx + size / 2, cy + size / 2]}


def body(box, with_kpts=True):
    b = {"bbox": box, "kpts": None, "kpt_scores": None}
    if with_kpts:
        kpts = np.zeros((17, 2))
        kpts[5], kpts[6] = (140, 100), (260, 100)      # shoulders, mid y 100
        kpts[11], kpts[12] = (150, 300), (250, 300)    # hips, mid y 300
        scores = np.zeros(17)
        scores[[5, 6, 11, 12]] = 0.9
        b["kpts"], b["kpt_scores"] = kpts, scores
    return b


@test
def test_assignment_uses_torso_plausibility_and_containment():
    b = body([100, 50, 300, 450])
    chest, pelvis = region("FEMALE_BREAST_EXPOSED", 200, 150), region("BUTTOCKS_EXPOSED", 200, 320)
    feet_over_head = region("FEMALE_BREAST_EXPOSED", 200, 380)          # chest label at the knees: implausible
    outside = region("BELLY_EXPOSED", 600, 200)
    got = sd.assign_regions_to_bodies([chest, pelvis, feet_over_head, outside], [b])
    check(got == [0, 0, None, None], got)


@test
def test_assignment_without_torso_keypoints_is_containment_and_largest_overlap():
    big, small = body([0, 0, 400, 400], False), body([150, 150, 250, 250], False)
    r = region("FEMALE_BREAST_EXPOSED", 200, 200, size=60)
    # contained in both; the region lies entirely in the small body -> larger overlap with it
    check(sd.assign_regions_to_bodies([r], [big, small]) == [1], "largest overlap")
    check(sd.assign_regions_to_bodies([region("BELLY_EXPOSED", 500, 500)], [big, small]) == [None], "outside")
    check(sd.assign_regions_to_bodies([r], []) == [None], "no bodies")


@test
def test_assignment_lying_body_projects_on_the_torso_axis():
    kpts = np.zeros((17, 2))
    kpts[5], kpts[6] = (100, 180), (100, 220)       # shoulders on the left
    kpts[11], kpts[12] = (300, 180), (300, 220)     # hips on the right: a lying body
    scores = np.zeros(17)
    scores[[5, 6, 11, 12]] = 0.9
    b = {"bbox": [50, 120, 380, 280], "kpts": kpts, "kpt_scores": scores}
    chest = region("FEMALE_BREAST_EXPOSED", 140, 200)
    pelvis = region("BUTTOCKS_EXPOSED", 290, 200)
    wrong = region("BUTTOCKS_EXPOSED", 120, 200)    # pelvic label next to the shoulders
    check(sd.assign_regions_to_bodies([chest, pelvis, wrong], [b]) == [0, 0, None], "axis based")


@test
def test_real_model_runs_on_cpu_and_returns_regions_for_a_synthetic_picture():
    if not sd.model_available():
        print("  (model not installed - skipped)")
        return
    detector = sd.SensitiveDetector(providers=["CPUExecutionProvider"])
    img = np.random.default_rng(1).integers(0, 255, (360, 480, 3), dtype=np.uint8)
    regions = detector.detect(img)
    check(isinstance(regions, list), "list")
    for r in regions:
        check(r["label"] in sd.LABELS and 0 <= r["score"] <= 1 and len(r["bbox"]) == 4, r)
        check(0 <= r["bbox"][0] < r["bbox"][2] <= 480 and 0 <= r["bbox"][1] < r["bbox"][3] <= 360, r["bbox"])


# --- the API ---------------------------------------------------------------------

def jpeg_bytes(w=640, h=480):
    img = np.random.default_rng(3).integers(0, 255, (h, w, 3), dtype=np.uint8)
    ok, buf = cv2.imencode(".jpg", img)
    assert ok
    return buf.tobytes()


def api_env():
    import test_mobile_api_contract as contract   # reuse Env, schema helpers and fixtures
    return contract


@test
def test_analyze_without_the_flag_is_unchanged_and_with_it_adds_regions():
    c = api_env()
    with c.Env() as e:
        plain = c._analyze(e, options={}).json()
        check("sensitive_regions" not in plain, "no key without the flag")
        r = c._analyze(e, options={"return_sensitive": True})
        check(r.status_code == 200, r.text)
        body_ = r.json()
        c.check_schema("AnalyzeImageResponse", body_)
        check([x["label"] for x in body_["sensitive_regions"]] == ["FEMALE_BREAST_EXPOSED", "BELLY_COVERED"], body_)
        check(body_["sensitive_regions"][0]["body_index"] == 0 and body_["sensitive_regions"][1]["body_index"] is None, "index")
        stripped = {k: v for k, v in body_.items() if k not in ("sensitive_regions", "timings_ms")}
        check(stripped == {k: v for k, v in plain.items() if k != "timings_ms"}, "everything else identical")
        check(e.ctx.engines.calls[-1].sensitive is True and e.ctx.engines.calls[0].sensitive is False, "option reaches engine")
        check(c._analyze(e, options={"return_sensitive": "yes"}).status_code == 400, "flag must be a boolean")
        e.ctx.engines.sensitive_ready = False
        r = c._analyze(e, options={"return_sensitive": True})
        check(r.status_code == 409 and r.json()["error"]["code"] == "model_missing", r.text)
        check(c._analyze(e, options={}).status_code == 200, "model missing only matters when asked")


@test
def test_backfill_endpoint_validates_bodies_and_returns_the_contract_shape():
    c = api_env()
    with c.Env() as e:
        fx = c.fixture("SensitiveBodyTarget.with_kpts")
        files = {"image": ("p.jpg", jpeg_bytes(), "image/jpeg")}
        r = e.client.post("/v1/analyze/sensitive", files=files, data={"bodies": json.dumps([fx])}, headers=e.auth)
        check(r.status_code == 200, f"{r.status_code} {r.text}")
        c.check_schema("AnalyzeSensitiveResponse", r.json())
        sent = e.ctx.engines.sensitive_calls[-1][0]
        check(sent["bbox"][2] == fx["bbox"]["x"] + fx["bbox"]["w"] and len(sent["kpts"]) == 17 and len(sent["kpt_scores"]) == 17,
              "bodies are converted to xyxy + separate scores")
        r = e.client.post("/v1/analyze/sensitive", files=files, headers=e.auth)
        check(r.status_code == 200, "no bodies is fine")
        for bad in ("not json", json.dumps({"a": 1}), json.dumps([{"bbox": {"x": 1}}]),
                    json.dumps([{"bbox": {"x": 0, "y": 0, "w": 5, "h": 5}, "kpts": [[1, 2, 3]]}]),
                    json.dumps([{"bbox": {"x": 0, "y": 0, "w": 5, "h": 5}}] * 65)):
            r = e.client.post("/v1/analyze/sensitive", files=files, data={"bodies": bad}, headers=e.auth)
            check(r.status_code == 400 and r.json()["error"]["code"] == "bad_request", f"{bad[:30]}: {r.status_code} {r.text}")
        e.ctx.engines.sensitive_ready = False
        r = e.client.post("/v1/analyze/sensitive", files=files, headers=e.auth)
        check(r.status_code == 409 and r.json()["error"]["code"] == "model_missing", r.text)
        e.ctx.engines.sensitive_ready = True
        r = e.client.post("/v1/analyze/sensitive", files=files, headers={"Authorization": "Bearer nope"})
        check(r.status_code == 401, f"needs a token: {r.status_code}")


@test
def test_worker_ipc_carries_sensitive_only_when_present():
    from analysis import FrameAnalysis
    from mobile_api.scan_worker import decode_result, encode_result
    base = FrameAnalysis(faces=[], quality=[], passes_gate=[], bodies=[], appearances=[], pairs=[], image_w=4, image_h=4)
    encoded = encode_result(base)
    check("sensitive" not in encoded, "an older parent process must not see an unknown key")
    check(decode_result(json.loads(json.dumps(encoded))).sensitive is None, "round trip, not requested")
    base.sensitive = [{"label": "BELLY_EXPOSED", "exposed": True, "score": 0.7, "bbox": [1, 2, 3, 4], "body_index": None}]
    again = decode_result(json.loads(json.dumps(encode_result(base))))
    check(again.sensitive == base.sensitive, again.sensitive)


def main(argv):
    wanted = argv[1] if len(argv) > 1 else ""
    failed = 0
    for fn in _TESTS:
        if wanted and wanted not in fn.__name__:
            continue
        try:
            fn()
            print(f"PASS  {fn.__name__}")
        except Exception:  # noqa: BLE001
            failed += 1
            print(f"FAIL  {fn.__name__}")
            traceback.print_exc()
    print(f"\n{len(_TESTS) - failed if not wanted else 'selected'} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
