"""
Roadmap Phase 7 (PC half): garment tags per body from the WD14 tagger. CPU only: pure helpers, fake engines,
TestClient, and (when the tagger is installed) one real CPU inference on a synthetic picture. No server is
started and no tag is a filter - this only checks the evidence the phone stores.

    venv\\Scripts\\python.exe test_mobile_garments.py
"""

import json
import sys
import traceback
from pathlib import Path

import cv2
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import garment_tags as gt  # noqa: E402

_TESTS = []


def test(fn):
    _TESTS.append(fn)
    return fn


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


def jpeg_bytes(w=640, h=480):
    img = np.random.default_rng(3).integers(0, 255, (h, w, 3), dtype=np.uint8)
    ok, buf = cv2.imencode(".jpg", img)
    assert ok
    return buf.tobytes()


def api_env():
    import test_mobile_api_contract as contract
    return contract


@test
def test_vocabulary_exists_in_the_installed_tag_file():
    if not gt.model_available():
        return
    import csv
    from lora_dataset import WD14_TAGS_PATH
    with open(WD14_TAGS_PATH, newline="", encoding="utf-8") as f:
        names = {row["name"] for row in csv.DictReader(f)}
    missing = sorted(set(gt.VOCABULARY) - names)
    check(not missing, f"vocabulary tags missing from the tagger: {missing}")


@test
def test_select_scores_keeps_vocabulary_above_the_floor_best_first():
    names = ["jeans", "1girl", "t-shirt", "hat", "dress"]
    out = gt.select_scores(names, [0.4, 0.99, 0.81234567, 0.14, 0.9999])
    check([t["tag"] for t in out] == ["dress", "t-shirt", "jeans"], out)
    check(out[1] == {"tag": "t-shirt", "category": "upper", "score": 0.8123}, out[1])
    check(gt.select_scores(names, [0.0] * 5) == [], "nothing above the floor")
    many = list(gt.VOCABULARY)
    check(len(gt.select_scores(many, [0.9] * len(many))) == gt.MAX_TAGS_PER_BODY, "capped")


@test
def test_crop_for_body_pads_clamps_and_skips_tiny_bodies():
    img = np.zeros((200, 300, 3), np.uint8)
    crop = gt.crop_for_body(img, [10, 20, 110, 170])
    check(crop.shape[:2] == (166, 110), crop.shape)           # 5 % padding each side (rounded)
    check(gt.crop_for_body(img, [-50, -50, 400, 400]).shape[:2] == (200, 300), "clamped to the image")
    check(gt.crop_for_body(img, [10, 10, 30, 30]) is None, "too small to tag")


@test
def test_tag_bodies_returns_one_list_per_body_in_order():
    class FakeTagger(gt.GarmentTagger):
        def __init__(self):
            self.available = True

        def tag_crop(self, crop):
            return [{"tag": "shirt", "category": "upper", "score": 0.5}]

    img = np.zeros((200, 300, 3), np.uint8)
    out = FakeTagger().tag_bodies(img, [{"bbox": [0, 0, 100, 100]}, {"bbox": [0, 0, 5, 5]}, {"bbox": [50, 50, 200, 190]}])
    check([len(t) for t in out] == [1, 0, 1], out)
    unavailable = gt.GarmentTagger.__new__(gt.GarmentTagger)
    unavailable.available = False
    check(unavailable.tag_crop(img) == [], "no model, no tags")


@test
def test_real_tagger_runs_on_cpu_when_installed():
    if not gt.model_available():
        return
    tagger = gt.GarmentTagger()
    check(tagger.available, "the installed tagger loads")
    img = np.random.default_rng(1).integers(0, 255, (320, 240, 3), dtype=np.uint8)
    out = tagger.tag_bodies(img, [{"bbox": [0, 0, 240, 320]}])
    check(len(out) == 1 and all(set(t) == {"tag", "category", "score"} for t in out[0]), out)


@test
def test_endpoint_returns_the_contract_shape_and_validates_bodies():
    c = api_env()
    with c.Env() as e:
        fx = c.fixture("SensitiveBodyTarget.with_kpts")
        files = {"image": ("p.jpg", jpeg_bytes(), "image/jpeg")}
        two = [fx, {"bbox": fx["bbox"]}]
        r = e.client.post("/v1/analyze/garments", files=files, data={"bodies": json.dumps(two)}, headers=e.auth)
        check(r.status_code == 200, f"{r.status_code} {r.text}")
        c.check_schema("AnalyzeGarmentsResponse", r.json())
        body = r.json()
        check(body["model_version"] == gt.GARMENT_VERSION and len(body["bodies"]) == 2, body)
        check(body["bodies"][0]["tags"][0]["tag"] == "t-shirt" and body["bodies"][1]["tags"] == [], body)
        check(e.ctx.engines.garment_calls[-1][0]["bbox"][2] == fx["bbox"]["x"] + fx["bbox"]["w"], "xyxy conversion")
        r = e.client.post("/v1/analyze/garments", files=files, headers=e.auth)
        check(r.status_code == 200 and r.json()["bodies"] == [], "no bodies is fine")
        for bad in ("not json", json.dumps({"a": 1}), json.dumps([{"bbox": {"x": 1}}]),
                    json.dumps([{"bbox": {"x": 0, "y": 0, "w": 5, "h": 5}}] * 65)):
            r = e.client.post("/v1/analyze/garments", files=files, data={"bodies": bad}, headers=e.auth)
            check(r.status_code == 400 and r.json()["error"]["code"] == "bad_request", f"{bad[:30]}: {r.status_code}")
        e.ctx.engines.garments_ready = False
        r = e.client.post("/v1/analyze/garments", files=files, headers=e.auth)
        check(r.status_code == 409 and r.json()["error"]["code"] == "model_missing", r.text)
        e.ctx.engines.garments_ready = True
        r = e.client.post("/v1/analyze/garments", files=files, headers={"Authorization": "Bearer nope"})
        check(r.status_code == 401, f"needs a token: {r.status_code}")


@test
def test_capabilities_advertise_the_tagger():
    c = api_env()
    with c.Env() as e:
        r = e.client.get("/v1/capabilities", headers=e.auth)
        check(r.status_code == 200 and r.json()["engines"]["garment_tags"] is True, r.text)
        c.check_schema("Capabilities", r.json())


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
