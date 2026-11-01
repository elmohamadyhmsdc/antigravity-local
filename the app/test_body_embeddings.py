"""
Phase 8 PC half (roadmap 7.5): DINOv2 patch embeddings + morphology of exposed regions. CPU only: a fake embedder
for the logic, the real ONNX model once on the CPU, fake engines + TestClient for the API. No server is started.

    venv\\Scripts\\python.exe test_body_embeddings.py
"""

import base64
import json
import sys
import traceback

import cv2
import numpy as np

import body_embeddings as be

_TESTS = []
SKIN = (120, 160, 215)      # BGR skin tone


def test(fn):
    _TESTS.append(fn)
    return fn


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


class FakeEmbedder:
    def __init__(self):
        self.calls = []

    def embed(self, patches):
        self.calls.append([p.shape for p in patches])
        out = np.zeros((len(patches), 384), dtype=np.float32)
        for i, p in enumerate(patches):
            out[i, int(p.mean()) % 384] = 1.0
        return out


def picture():
    img = np.full((600, 800, 3), (40, 40, 40), np.uint8)
    img[100:500, 250:550] = SKIN
    cv2.circle(img, (350, 250), 12, (60, 70, 110), -1)    # areola-ish dark disc
    cv2.circle(img, (450, 250), 12, (60, 70, 110), -1)
    cv2.circle(img, (400, 330), 4, (70, 90, 140), -1)     # a mole
    return img


def body(with_kpts=True):
    b = {"bbox": [200, 50, 600, 580], "kpts": None, "kpt_scores": None}
    if with_kpts:
        k = np.zeros((17, 2))
        k[5], k[6], k[11], k[12] = (500, 150), (300, 150), (470, 480), (330, 480)
        s = np.zeros(17)
        s[[5, 6, 11, 12]] = 0.9
        b["kpts"], b["kpt_scores"] = k, s
    return b


def region(label, box, score=0.9, index=0):
    return {"label": label, "exposed": label.endswith("_EXPOSED"), "score": score, "bbox": box, "body_index": index}


@test
def test_union_box_pads_clips_and_refuses_tiny_patches():
    check(be.union_box([[100, 100, 200, 200]], 0.1, 800, 600) == [90, 90, 210, 210], "padded")
    check(be.union_box([[0, 0, 100, 100]], 0.2, 800, 600)[0] == 0, "clipped")
    check(be.union_box([[10, 10, 20, 20]], 0.0, 800, 600) is None, "tiny")
    check(be.union_box([], 0.1, 800, 600) is None, "none")
    box = be.union_box([[100, 100, 200, 200], [300, 150, 400, 250]], 0.0, 800, 600)
    check(box == [100, 100, 400, 250], box)


@test
def test_scale_source_kpts_or_bbox():
    chest = be.scale_for(body(), shoulders=True)
    check(chest["scale_source"] == "kpts" and abs(chest["scale"] - 200) < 1e-6, chest)
    lower = be.scale_for(body(), shoulders=False)
    check(lower["scale_source"] == "kpts" and abs(lower["scale"] - 140) < 1e-6, lower)
    close_up = be.scale_for(body(with_kpts=False), shoulders=True)
    check(close_up["scale_source"] == "bbox" and close_up["scale"] == 400, close_up)
    hidden = body()
    hidden["kpt_scores"][5] = 0.1
    check(be.scale_for(hidden, shoulders=True)["scale_source"] == "bbox", "a hidden shoulder falls back to the box")


@test
def test_chest_patch_gets_an_embedding_and_morphology():
    emb = FakeEmbedder()
    regions = [region("FEMALE_BREAST_EXPOSED", [320, 220, 380, 280]), region("FEMALE_BREAST_EXPOSED", [420, 220, 480, 280])]
    result = be.analyse_body(picture(), body(), regions, emb)
    check(result["chest_embedding"] and result["buttocks_embedding"] is None, result.keys())
    raw = base64.b64decode(result["chest_embedding"])
    check(len(raw) == 384 * 4, len(raw))
    m = result["morphology"]
    check(m["scale_source"] == "kpts", m)
    check(abs(m["breast_span_ratio"] - (480 - 320) / 200) < 1e-3, m["breast_span_ratio"])
    check(m["areola_contrast"] is not None and 0 < m["areola_contrast"] < 1, m["areola_contrast"])
    lab = m["skin_tone_lab"]
    check(lab and 40 < lab[0] < 90 and lab[1] > 0, lab)
    check(isinstance(m["micro_marks"], list) and len(m["micro_marks"]) <= be.MAX_MARKS, m["micro_marks"])
    check(len(emb.calls) == 1 and len(emb.calls[0]) == 1, "one patch for the chest")


@test
def test_lower_body_and_both_halves_in_one_photo_share_one_call():
    emb = FakeEmbedder()
    regions = [region("FEMALE_BREAST_EXPOSED", [320, 200, 480, 280]), region("BUTTOCKS_EXPOSED", [330, 420, 470, 520])]
    result = be.analyse_body(picture(), body(), regions, emb)
    check(result["chest_embedding"] and result["buttocks_embedding"], "both embeddings (a bridge photo)")
    check(len(emb.calls) == 1 and len(emb.calls[0]) == 2, emb.calls)
    check(abs(result["morphology"]["buttocks_span_ratio"] - 140 / 140) < 1e-3, result["morphology"])


@test
def test_close_up_uses_the_box_scale_and_weak_regions_are_ignored():
    emb = FakeEmbedder()
    r = be.analyse_body(picture(), body(with_kpts=False), [region("BUTTOCKS_EXPOSED", [300, 300, 500, 450])], emb)
    check(r["morphology"]["scale_source"] == "bbox", r["morphology"])
    weak = be.analyse_body(picture(), body(), [region("BUTTOCKS_EXPOSED", [300, 300, 500, 450], score=0.3)], emb)
    check(weak == {"chest_embedding": None, "buttocks_embedding": None, "morphology": None}, weak)
    belly = be.analyse_body(picture(), body(), [region("BELLY_EXPOSED", [330, 300, 470, 400])], emb)
    check(belly["chest_embedding"] is not None, "belly exposed is a chest-half trigger")
    covered = be.analyse_body(picture(), body(), [region("BELLY_COVERED", [330, 300, 470, 400])], emb)
    check(covered["chest_embedding"] is None, "covered regions never make a patch")


@test
def test_analyse_bodies_pairs_regions_with_their_body_only():
    emb = FakeEmbedder()
    out = be.analyse_bodies(picture(), [body(), body()], [region("FEMALE_BREAST_EXPOSED", [320, 220, 480, 280], index=1)], emb)
    check(out[0]["chest_embedding"] is None and out[1]["chest_embedding"] is not None, out)


@test
def test_skin_tone_and_marks_on_synthetic_skin():
    img = picture()
    patch = img[150:450, 280:520]
    check(be.skin_tone_lab(np.full((50, 50, 3), (30, 30, 30), np.uint8)) is None, "no skin, no tone")
    marks = be.micro_marks(patch, [280, 150, 520, 450], np.array([400.0, 150.0]), 200.0)
    check(marks and abs(marks[0][0]) < 0.05 and abs(marks[0][1] - 0.9) < 0.05, marks)
    masked = be.micro_marks(patch, [280, 150, 520, 450], np.array([400.0, 150.0]), 200.0, exclude=[[330, 225, 470, 275]])
    check(all(abs(m[1] - 0.5) > 0.12 for m in masked), "marks inside an excluded (areola) box are dropped")
    flat = be.micro_marks(np.full((200, 200, 3), SKIN, np.uint8), [0, 0, 200, 200], np.array([0.0, 0.0]), 100.0)
    check(flat == [], "a flat patch has no marks")


@test
def test_real_dinov2_runs_on_cpu_and_is_unit_length():
    if not be.model_available():
        print("  (model not installed - skipped)")
        return
    embedder = be.DinoEmbedder(providers=["CPUExecutionProvider"])
    rng = np.random.default_rng(0)
    patches = [rng.integers(0, 255, (120, 90, 3), dtype=np.uint8), np.full((64, 64, 3), SKIN, np.uint8)]
    vecs = embedder.embed(patches)
    check(vecs.shape == (2, 384) and np.allclose(np.linalg.norm(vecs, axis=1), 1, atol=1e-4), vecs.shape)
    again = embedder.embed(patches[:1])
    check(float(vecs[0] @ again[0]) > 0.999, "deterministic and batch independent")
    check(float(vecs[0] @ vecs[1]) < 0.99, "different pictures differ")
    check(embedder.embed([]).shape == (0, 384), "empty")


@test
def test_api_flag_adds_embeddings_only_when_asked_and_checks_the_model():
    import test_mobile_api_contract as c
    with c.Env() as e:
        plain = c._analyze(e, options={}).json()
        check(all("chest_embedding" not in b for b in plain["bodies"]), "unchanged without the flag")
        sensitive_only = c._analyze(e, options={"return_sensitive": True}).json()
        check(all("chest_embedding" not in b for b in sensitive_only["bodies"]), "regions alone add no embeddings")
        r = c._analyze(e, options={"return_body_embeddings": True})
        check(r.status_code == 200, r.text)
        body_ = r.json()
        c.check_schema("AnalyzeImageResponse", body_)
        check("sensitive_regions" not in body_, "regions are computed but only returned when asked")
        check(body_["bodies"][0]["chest_embedding"] and body_["bodies"][0]["morphology"]["scale_source"] == "kpts", body_["bodies"][0])
        check(e.ctx.engines.calls[-1].body_embeddings is True, "option reaches the engine")
        c.check_schema("BodyMorphology", body_["bodies"][0]["morphology"])
        e.ctx.engines.embeddings_ready = False
        r = c._analyze(e, options={"return_body_embeddings": True})
        check(r.status_code == 409 and r.json()["error"]["code"] == "model_missing", r.text)
        check(c._analyze(e, options={}).status_code == 200, "only needed when asked")
        check(c._analyze(e, options={"return_body_embeddings": 1}).status_code == 400, "a boolean")


@test
def test_backfill_endpoint_returns_embeddings_only_when_asked():
    import test_mobile_api_contract as c
    with c.Env() as e:
        fx = c.fixture("SensitiveBodyTarget.with_kpts")
        files = {"image": ("p.jpg", c.jpeg_bytes(), "image/jpeg")}
        plain = e.client.post("/v1/analyze/sensitive", files=files, data={"bodies": json.dumps([fx])}, headers=e.auth)
        check(plain.status_code == 200 and "bodies" not in plain.json(), plain.text)
        r = e.client.post("/v1/analyze/sensitive", files=files, data={"bodies": json.dumps([fx]), "embeddings": "true"}, headers=e.auth)
        check(r.status_code == 200, r.text)
        body = r.json()
        c.check_schema("AnalyzeSensitiveResponse", body)
        check(len(body["bodies"]) == 1 and body["bodies"][0]["chest_embedding"], body)
        c.check_schema("AnalyzeSensitiveResponse", c.fixture("AnalyzeSensitiveResponse.with_embeddings"))
        bad = e.client.post("/v1/analyze/sensitive", files=files, data={"embeddings": "maybe"}, headers=e.auth)
        check(bad.status_code == 400 and bad.json()["error"]["code"] == "bad_request", bad.text)
        e.ctx.engines.embeddings_ready = False
        r = e.client.post("/v1/analyze/sensitive", files=files, data={"embeddings": "true"}, headers=e.auth)
        check(r.status_code == 409 and r.json()["error"]["code"] == "model_missing", r.text)
        check(e.client.post("/v1/analyze/sensitive", files=files, headers=e.auth).status_code == 200, "regions alone still work")


@test
def test_worker_ipc_carries_embeddings_only_when_present():
    from analysis import FrameAnalysis
    from mobile_api.scan_worker import decode_result, encode_result
    base = FrameAnalysis(faces=[], quality=[], passes_gate=[], bodies=[], appearances=[], pairs=[], image_w=4, image_h=4)
    check("body_embeddings" not in encode_result(base), "an older parent never sees the key")
    base.body_embeddings = [{"chest_embedding": None, "buttocks_embedding": None, "morphology": None}]
    again = decode_result(json.loads(json.dumps(encode_result(base))))
    check(again.body_embeddings == base.body_embeddings, again.body_embeddings)


def main(argv):
    failed = 0
    for fn in _TESTS:
        try:
            fn()
            print(f"PASS  {fn.__name__}")
        except Exception:  # noqa: BLE001
            failed += 1
            print(f"FAIL  {fn.__name__}")
            traceback.print_exc()
    print(f"\n{len(_TESTS) - failed}/{len(_TESTS)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
