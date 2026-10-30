"""
Checks the mobile API contract. Follows the repo's test convention: prints
results and exit(1) on failure; needs only PyYAML + jsonschema + numpy.

  1. openapi.yaml parses, every component schema is a valid JSON Schema and
     every $ref resolves.
  2. Every fixtures/<Schema>.<variant>.json validates against components.schemas.<Schema>.
  3. Every embedding in every fixture decodes to 512 finite float32 values with unit norm.
  4. Deliberately broken payloads are rejected (so the checks above can really fail).

    venv\\Scripts\\python mobile_api\\contract\\validate_contract.py
"""

import base64
import copy
import json
import sys
from pathlib import Path

import numpy as np
import yaml
from jsonschema import Draft202012Validator

HERE = Path(__file__).resolve().parent
SPEC = yaml.safe_load((HERE / "openapi.yaml").read_text(encoding="utf-8"))
SCHEMAS = SPEC["components"]["schemas"]

failures = []


def check(ok, label, detail=""):
    print(("PASS  " if ok else "FAIL  ") + label + (f"  - {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


def validator_for(schema_name):
    root = {"$ref": f"#/components/schemas/{schema_name}", "components": SPEC["components"]}
    return Draft202012Validator(root)


def errors_for(schema_name, instance):
    return sorted(validator_for(schema_name).iter_errors(instance), key=lambda e: list(e.path))


# --------------------------------------------------------------------------- 1. the spec itself

def resolve_pointer(ref):
    node = SPEC
    for part in ref.lstrip("#/").split("/"):
        node = node[part.replace("~1", "/").replace("~0", "~")]
    return node


def walk_refs(node, found):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "$ref" and isinstance(v, str):
                found.append(v)
            else:
                walk_refs(v, found)
    elif isinstance(node, list):
        for v in node:
            walk_refs(v, found)


refs = []
walk_refs(SPEC, refs)
bad_refs = []
for r in sorted(set(refs)):
    try:
        resolve_pointer(r)
    except (KeyError, TypeError):
        bad_refs.append(r)
check(not bad_refs, f"all {len(set(refs))} distinct $refs resolve", ", ".join(bad_refs))

bad_schemas = []
for name, schema in SCHEMAS.items():
    try:
        Draft202012Validator.check_schema(schema)
    except Exception as e:  # noqa: BLE001
        bad_schemas.append(f"{name}: {e}")
check(not bad_schemas, f"all {len(SCHEMAS)} component schemas are valid JSON Schema", "; ".join(bad_schemas))

paths = SPEC["paths"]
for needed in ("/v1/health", "/v1/capabilities", "/v1/pair/complete", "/v1/blobs/{sha256}", "/v1/analyze/image",
               "/v1/grouping/plan", "/v1/jobs", "/v1/jobs/{job_id}", "/v1/jobs/{job_id}/events",
               "/v1/jobs/{job_id}/stop", "/v1/jobs/{job_id}/resume", "/v1/jobs/{job_id}/result",
               "/v1/jobs/{job_id}/result/{name}"):
    check(needed in paths, f"path {needed} is defined")

# --------------------------------------------------------------------------- 2 + 3. fixtures

EMBEDDING_KEYS = {"embedding", "proto", "weak_face_embedding", "target_embeddings"}


def embeddings_in(node, key=None):
    if isinstance(node, dict):
        for k, v in node.items():
            yield from embeddings_in(v, k)
    elif isinstance(node, list):
        for v in node:
            yield from embeddings_in(v, key)
    elif isinstance(node, str) and (key in EMBEDDING_KEYS or key == "members"):
        yield node


fixtures = sorted((HERE / "fixtures").glob("*.json"))
check(len(fixtures) > 0, f"{len(fixtures)} fixtures found")
by_schema = {}
for path in fixtures:
    schema_name = path.name.split(".")[0]
    data = json.loads(path.read_text(encoding="utf-8"))
    by_schema.setdefault(schema_name, []).append(data)
    if schema_name not in SCHEMAS:
        check(False, f"{path.name}: schema {schema_name} exists")
        continue
    errs = errors_for(schema_name, data)
    check(not errs, f"{path.name} matches {schema_name}",
          "; ".join(f"{'/'.join(map(str, e.path))}: {e.message[:120]}" for e in errs[:3]))

    bad = []
    n = 0
    for s in embeddings_in(data):
        n += 1
        raw = base64.b64decode(s)
        v = np.frombuffer(raw, dtype="<f4")
        if len(raw) != 2048 or not np.isfinite(v).all() or abs(float(np.linalg.norm(v)) - 1.0) > 1e-3:
            bad.append(s[:12])
    if n:
        check(not bad, f"{path.name}: {n} embeddings are 512 finite unit float32", f"bad: {bad[:3]}")

# --------------------------------------------------------------------------- 4. negatives


def must_fail(schema_name, fixture_variant, mutate, label):
    base = next(d for p, d in ((p, json.loads(p.read_text(encoding="utf-8"))) for p in fixtures)
                if p.name == f"{schema_name}.{fixture_variant}.json")
    broken = copy.deepcopy(base)
    mutate(broken)
    check(len(errors_for(schema_name, broken)) > 0, f"rejects: {label}")


must_fail("AnalyzeImageResponse", "two_faces_one_body", lambda d: d["faces"][0].pop("embedding"),
          "a face without an embedding")
must_fail("AnalyzeImageResponse", "two_faces_one_body", lambda d: d["faces"][0].__setitem__("embedding", "AAAA"),
          "a truncated embedding")
must_fail("AnalyzeImageResponse", "two_faces_one_body", lambda d: d["bodies"][0].__setitem__("appearance", [0.1] * 79),
          "an 79-float outfit descriptor")
must_fail("AnalyzeImageResponse", "character_no_face", lambda d: d["characters"][0].__setitem__("descriptor", [0.1] * 159),
          "a truncated character descriptor")
must_fail("AnalyzeImageResponse", "character_no_face", lambda d: d["characters"][0].__setitem__("model_id", "buffalo_l@1"),
          "a human embedding model in a character detection")
must_fail("JobCreate", "train_lora", lambda d: d["inputs"].pop("dataset"),
          "train_lora without the dataset blob")
must_fail("JobCreate", "train_lora", lambda d: d["params"].__setitem__("output_name", "../evil"),
          "a train_lora output_name that is a path")
must_fail("JobCreate", "reface_image_v3", lambda d: d["params"].pop("source_faces"),
          "reface_image_v3 without source_faces")
must_fail("JobCreate", "reface_image_v3", lambda d: d.__setitem__("type", "format_c_drive"),
          "an unknown job type")
must_fail("JobCreate", "reface_video_selected_preview", lambda d: d["params"].__setitem__("target_indices", []),
          "a video reference selection without an index")
must_fail("JobCreate", "reface_video_selected_preview", lambda d: d["params"].__setitem__("preview", "yes"),
          "a nonboolean preview flag")
must_fail("JobStatus", "running", lambda d: d.__setitem__("status", "exploded"), "an unknown job status")
must_fail("GroupingPlanRequest", "apply_basic", lambda d: d["stages"].append("telepathy"), "an unknown grouping stage")
must_fail("GroupingPlanResponse", "apply_basic",
          lambda d: d["assignments"].append({"face_id": 1, "person_id": 1, "score": 0.5, "margin": 0.1, "decision": "maybe"}),
          "an unknown assignment decision")

print()
if failures:
    print(f"{len(failures)} check(s) FAILED")
    sys.exit(1)
print("all contract checks passed")
