"""
Grouping core - the DB-free decision step shared by the Streamlit gallery and the mobile API.

`plan()` is a pure function: it gets a snapshot of the library (people models, faces that
belong to nobody yet, bodies, "these two are different" pairs), runs person_linking over it
and returns what should happen. It never reads or writes a database, a file or the network, so
the PC's JSON store (gallery_grouping.py) and the phone's SQLite database (via POST
/v1/grouping/plan) both go through exactly the same code, and the thresholds stay in
person_linking.STRICTNESS.

    mode "apply"   what group_library() does: confident decisions only. The caller applies
                   them, then (for bodies) asks again with fresh models - bodies are linked
                   against the people the earlier stages created.
    mode "review"  what review_state() shows: everything that needs a decision, plus the
                   suggestions that apply mode leaves out.

Stages (any subset, one plan call): match -> cluster -> duplicates -> bodies. "match" claims
the faces that clearly belong to a known person; "cluster" groups the rest.

The wire format is contract/openapi.yaml (GroupingPlanRequest / GroupingPlanResponse);
`plan_request()` is the JSON-in / JSON-out wrapper the API route and the fixture generator use.
"""

import base64
from dataclasses import dataclass, field
from typing import Any, Dict, Hashable, Iterable, List, Optional, Sequence, Set, Tuple, Union

import numpy as np

import person_linking as pl

EMBEDDING_DIM = 512
MODES = ("apply", "review")
STAGES = ("match", "cluster", "duplicates", "bodies")
APPLY_STAGES = ("match", "cluster", "bodies")
DEFAULT_MAX_SUGGESTIONS_PER_PERSON = 60

# The shape of a request is bounded so a single call cannot exhaust the PC's memory.
MAX_MODELS = 5000
MAX_MEMBERS_PER_MODEL = 1000
MAX_PENDING_FACES = 100_000
MAX_BODIES = 200_000


class GroupingRequestError(ValueError):
    """The request is malformed (the API answers 400 bad_request with this message)."""


# ---------------------------------------------------------------------------
# In-memory shapes
# ---------------------------------------------------------------------------

@dataclass
class PendingFace:
    """A face that belongs to nobody yet. `embedding` is normalised by plan()."""
    id: int
    embedding: np.ndarray
    quality: float
    frame_key: Optional[Hashable] = None          # faces sharing a key were seen in one photo / frame
    rejected_person_ids: Set[int] = field(default_factory=set)


@dataclass
class BodyInput:
    id: int
    media_id: Optional[int] = None
    frame_number: Optional[int] = None
    anchor_person_id: Optional[int] = None        # person it belongs to through its face or a manual link
    appearance: Optional[Sequence[float]] = None  # 80-float outfit descriptor
    weak_face_embedding: Optional[Sequence[float]] = None
    rejected_person_ids: Set[int] = field(default_factory=set)


@dataclass
class Snapshot:
    models: Dict[int, pl.PersonModel] = field(default_factory=dict)
    pending: List[PendingFace] = field(default_factory=list)
    bodies: List[BodyInput] = field(default_factory=list)
    distinct_pairs: List[Tuple[int, int]] = field(default_factory=list)
    dismissed_face_ids: Set[int] = field(default_factory=set)


@dataclass
class FaceAssignment:
    face_id: int
    person_id: int
    score: float
    margin: float
    decision: str                                  # "auto" | "suggest"

    def as_dict(self) -> Dict[str, Any]:
        return {"face_id": self.face_id, "person_id": self.person_id, "score": self.score,
                "margin": self.margin, "decision": self.decision}


@dataclass
class FaceGroup:
    face_ids: List[int]
    cohesion: float
    quality: float
    auto_create: bool

    def as_dict(self) -> Dict[str, Any]:
        return {"face_ids": self.face_ids, "cohesion": self.cohesion, "quality": self.quality,
                "auto_create": self.auto_create}


@dataclass
class DuplicatePeople:
    person_a: int
    person_b: int
    score: float

    def as_dict(self) -> Dict[str, Any]:
        return {"person_a": self.person_a, "person_b": self.person_b, "score": self.score}


@dataclass
class GroupingPlan:
    mode: str
    assignments: List[FaceAssignment] = field(default_factory=list)
    groups: List[FaceGroup] = field(default_factory=list)
    duplicates: List[DuplicatePeople] = field(default_factory=list)
    body_links: List[pl.BodyLink] = field(default_factory=list)
    unsorted_face_ids: List[int] = field(default_factory=list)

    def as_dict(self) -> Dict[str, Any]:
        """GroupingPlanResponse."""
        return {
            "mode": self.mode,
            "assignments": [a.as_dict() for a in self.assignments],
            "groups": [g.as_dict() for g in self.groups],
            "duplicates": [d.as_dict() for d in self.duplicates],
            "body_links": [{"body_id": l.body_id, "person_id": l.person_id, "method": l.method,
                            "confidence": l.confidence, "decision": l.decision} for l in self.body_links],
            "unsorted_face_ids": self.unsorted_face_ids,
        }


# ---------------------------------------------------------------------------
# The decision step
# ---------------------------------------------------------------------------

def plan(snapshot: Snapshot, mode: str = "apply", stages: Iterable[str] = APPLY_STAGES,
         strictness: Union[str, pl.GroupingParams] = "balanced",
         max_suggestions_per_person: int = DEFAULT_MAX_SUGGESTIONS_PER_PERSON) -> GroupingPlan:
    """Decide how the snapshot's faces and bodies should be grouped. See the module docstring."""
    if mode not in MODES:
        raise GroupingRequestError(f"mode must be one of {', '.join(MODES)}")
    wanted = set(stages)
    unknown = wanted - set(STAGES)
    if unknown:
        raise GroupingRequestError(f"unknown stage(s): {', '.join(sorted(unknown))}")
    review = mode == "review"
    if not review and "duplicates" in wanted:
        raise GroupingRequestError("the duplicates stage is only available in review mode")
    params = strictness if isinstance(strictness, pl.GroupingParams) else pl.params_for(strictness)

    models = snapshot.models
    pending = snapshot.pending
    n = len(pending)
    result = GroupingPlan(mode=mode)

    if n:
        e = pl.normalize_rows(np.stack([np.asarray(f.embedding, dtype=np.float32) for f in pending]))
        q = np.array([float(f.quality or 0.0) for f in pending], dtype=np.float32)
        keys = [f.frame_key for f in pending]
        rejected = [set(f.rejected_person_ids or ()) for f in pending]
    else:
        e = np.zeros((0, EMBEDDING_DIM), dtype=np.float32)
        q = np.zeros(0, dtype=np.float32)
        keys, rejected = [], []

    claimed: Set[int] = set()   # positions in `pending` that are spoken for

    if "match" in wanted and models and n:
        per_person: Dict[int, List[FaceAssignment]] = {}
        accepted = ("auto", "suggest") if review else ("auto",)
        for m in pl.match_faces(e, models, params, keys, rejected):
            if m.decision in accepted:
                per_person.setdefault(m.person_id, []).append(
                    FaceAssignment(pending[m.index].id, m.person_id, round(m.score, 3), round(m.margin, 3),
                                   m.decision))
                claimed.add(m.index)
        for items in per_person.values():
            items.sort(key=lambda a: -a.score)
            result.assignments.extend(items[:max_suggestions_per_person] if review else items)

    if "cluster" in wanted:
        if review:
            rest = [i for i in range(n)
                    if i not in claimed and pending[i].id not in snapshot.dismissed_face_ids]
        else:
            rest = [i for i in range(n) if i not in claimed]
        if rest:
            sub = np.asarray(rest)
            for c in pl.cluster_faces(e[sub], q[sub], params, [keys[i] for i in rest]):
                idx = [rest[i] for i in c.indices]
                result.groups.append(FaceGroup([pending[i].id for i in idx], round(c.cohesion, 3),
                                               round(c.quality, 3), bool(pl.should_auto_create(c, params))))
                if review:
                    claimed.update(idx)

    if "duplicates" in wanted and len(models) > 1:
        result.duplicates = [DuplicatePeople(a, b, s) for a, b, s in
                             pl.suggest_merges(models, params, [tuple(p) for p in snapshot.distinct_pairs])]

    if "bodies" in wanted and snapshot.bodies and models:
        records = [{"id": b.id, "media_id": b.media_id, "frame_number": b.frame_number,
                    "appearance": b.appearance, "weak_face_embedding": b.weak_face_embedding,
                    "rejected_person_ids": b.rejected_person_ids, "anchor_person_id": b.anchor_person_id}
                   for b in snapshot.bodies]
        for link in pl.link_faceless_bodies(records, lambda b: b["anchor_person_id"], models, params):
            # apply mode returns the suggestions too (the caller applies only "auto"); review shows only those
            if review and link.decision != "suggest":
                continue
            result.body_links.append(link)

    if review:
        result.unsorted_face_ids = [pending[i].id for i in range(n) if i not in claimed]
    return result


# ---------------------------------------------------------------------------
# Wire format (GroupingPlanRequest in, GroupingPlanResponse out)
# ---------------------------------------------------------------------------

def decode_embedding(text: Any, what: str = "embedding") -> np.ndarray:
    """512 x float32 little-endian, base64 -> float32 vector."""
    if not isinstance(text, str):
        raise GroupingRequestError(f"{what} must be a base64 string")
    try:
        raw = base64.b64decode(text, validate=True)
    except ValueError:
        raise GroupingRequestError(f"{what} is not valid base64")
    if len(raw) != EMBEDDING_DIM * 4:
        raise GroupingRequestError(f"{what} must be {EMBEDDING_DIM} float32 values")
    vec = np.frombuffer(raw, dtype="<f4").astype(np.float32)
    if not np.isfinite(vec).all():
        raise GroupingRequestError(f"{what} contains NaN or infinity")
    return vec


def _expect(cond: bool, message: str):
    if not cond:
        raise GroupingRequestError(message)


def _int(value: Any, what: str) -> int:
    _expect(isinstance(value, int) and not isinstance(value, bool), f"{what} must be an integer")
    return value


def _opt_int(value: Any, what: str) -> Optional[int]:
    return None if value is None else _int(value, what)


def _int_list(value: Any, what: str) -> List[int]:
    _expect(isinstance(value, list), f"{what} must be a list")
    return [_int(v, f"{what}[]") for v in value]


def _list(req: Dict, key: str, required: bool = True) -> List:
    value = req.get(key)
    if value is None and not required:
        return []
    _expect(isinstance(value, list), f"{key} must be a list")
    return value


def _appearance(value: Any, what: str) -> Optional[List[float]]:
    if value is None:
        return None
    _expect(isinstance(value, list) and len(value) == 2 * pl.REGION_LEN
            and all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in value),
            f"{what} must be {2 * pl.REGION_LEN} numbers")
    return [float(v) for v in value]


def snapshot_from_request(req: Dict) -> Tuple[Snapshot, str, List[str], str, int]:
    """Validate a GroupingPlanRequest and decode it. -> (snapshot, mode, stages, strictness, max_suggestions)."""
    _expect(isinstance(req, dict), "the request must be a JSON object")
    mode = req.get("mode")
    _expect(mode in MODES, f"mode must be one of {', '.join(MODES)}")
    stages = _list(req, "stages")
    _expect(all(s in STAGES for s in stages), f"stages may only contain {', '.join(STAGES)}")
    _expect(len(set(stages)) == len(stages), "stages must not repeat")
    strictness = req.get("strictness")
    _expect(isinstance(strictness, str) and strictness in pl.STRICTNESS,
            f"strictness must be one of {', '.join(pl.STRICTNESS)}")
    cap = req.get("max_suggestions_per_person", DEFAULT_MAX_SUGGESTIONS_PER_PERSON)
    _expect(isinstance(cap, int) and not isinstance(cap, bool) and cap >= 1,
            "max_suggestions_per_person must be a positive integer")

    models_json = _list(req, "models")
    _expect(len(models_json) <= MAX_MODELS, f"at most {MAX_MODELS} models")
    models: Dict[int, pl.PersonModel] = {}
    for i, m in enumerate(models_json):
        _expect(isinstance(m, dict), f"models[{i}] must be an object")
        pid = _int(m.get("pid"), f"models[{i}].pid")
        _expect(pid not in models, f"models[{i}]: person {pid} appears twice")
        members_json = m.get("members")
        _expect(isinstance(members_json, list) and 1 <= len(members_json) <= MAX_MEMBERS_PER_MODEL,
                f"models[{i}].members must hold 1..{MAX_MEMBERS_PER_MODEL} embeddings")
        count = _int(m.get("count"), f"models[{i}].count")
        _expect(count >= 1, f"models[{i}].count must be at least 1")
        models[pid] = pl.PersonModel(
            pid, decode_embedding(m.get("proto"), f"models[{i}].proto"),
            np.stack([decode_embedding(x, f"models[{i}].members[{j}]") for j, x in enumerate(members_json)]),
            count)

    pending_json = _list(req, "pending")
    _expect(len(pending_json) <= MAX_PENDING_FACES, f"at most {MAX_PENDING_FACES} pending faces")
    pending: List[PendingFace] = []
    seen_ids: Set[int] = set()
    for i, f in enumerate(pending_json):
        _expect(isinstance(f, dict), f"pending[{i}] must be an object")
        fid = _int(f.get("id"), f"pending[{i}].id")
        _expect(fid not in seen_ids, f"pending[{i}]: face {fid} appears twice")
        seen_ids.add(fid)
        quality = f.get("quality")
        _expect(isinstance(quality, (int, float)) and not isinstance(quality, bool),
                f"pending[{i}].quality must be a number")
        key = f.get("frame_key")
        _expect(key is None or isinstance(key, str), f"pending[{i}].frame_key must be a string or null")
        pending.append(PendingFace(fid, decode_embedding(f.get("embedding"), f"pending[{i}].embedding"),
                                   float(quality), key,
                                   set(_int_list(f.get("rejected_person_ids", []), f"pending[{i}].rejected_person_ids"))))

    bodies_json = _list(req, "bodies")
    _expect(len(bodies_json) <= MAX_BODIES, f"at most {MAX_BODIES} bodies")
    bodies: List[BodyInput] = []
    for i, b in enumerate(bodies_json):
        _expect(isinstance(b, dict), f"bodies[{i}] must be an object")
        weak = b.get("weak_face_embedding")
        bodies.append(BodyInput(
            id=_int(b.get("id"), f"bodies[{i}].id"),
            media_id=_opt_int(b.get("media_id"), f"bodies[{i}].media_id"),
            frame_number=_opt_int(b.get("frame_number"), f"bodies[{i}].frame_number"),
            anchor_person_id=_opt_int(b.get("anchor_person_id"), f"bodies[{i}].anchor_person_id"),
            appearance=_appearance(b.get("appearance"), f"bodies[{i}].appearance"),
            weak_face_embedding=None if weak is None else decode_embedding(weak, f"bodies[{i}].weak_face_embedding"),
            rejected_person_ids=set(_int_list(b.get("rejected_person_ids", []), f"bodies[{i}].rejected_person_ids"))))

    distinct = []
    for i, p in enumerate(_list(req, "distinct_pairs")):
        _expect(isinstance(p, list) and len(p) == 2, f"distinct_pairs[{i}] must be a pair of person ids")
        distinct.append((_int(p[0], f"distinct_pairs[{i}][0]"), _int(p[1], f"distinct_pairs[{i}][1]")))

    dismissed = set(_int_list(req.get("dismissed_face_ids", []), "dismissed_face_ids"))
    return Snapshot(models, pending, bodies, distinct, dismissed), mode, list(stages), strictness, cap


def plan_request(req: Dict) -> Dict[str, Any]:
    """GroupingPlanRequest (decoded JSON) -> GroupingPlanResponse (JSON-able dict)."""
    snapshot, mode, stages, strictness, cap = snapshot_from_request(req)
    return plan(snapshot, mode, stages, strictness, cap).as_dict()
