"""
Grouping service - runs person_linking over the database.

group_library() is the "sort my gallery" action: match new faces to people you
already have, group what's left into new people, and tie faceless bodies to a
person when the evidence is strong. Anything less than certain is left for
review_state(), which is what the Gallery's Review tab shows.

The decisions themselves are made by grouping_core.plan() - the same DB-free
code the mobile API serves - over a snapshot of this JSON database. This module
only builds that snapshot and applies the result, so the Streamlit gallery and
the phone can never drift apart. Nothing here decides thresholds; those live in
person_linking.STRICTNESS.
"""

from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional, Sequence, Tuple

import grouping_core as gc
import person_linking as pl
from database import JsonDatabase, norm_path

DERIVED_BODY_LINKS = ("appearance", "weak_face")
VIDEO_SUFFIXES = (".mp4", ".avi", ".mkv", ".mov", ".wmv", ".flv", ".webm", ".m4v")


def frame_key(face: Dict):
    """Faces sharing a key were seen in the same photo / video frame, so they
    can't be the same person. Legacy video faces have no frame number - they get
    no constraint rather than a wrong one."""
    frame = face.get("frame_number")
    source = (face.get("source_path") or "")
    if frame is None and source.lower().endswith(VIDEO_SUFFIXES):
        return None
    base = face.get("media_id")
    if base is None:
        base = norm_path(source) if source else None
    return None if base is None else (base, frame)


def face_quality_of(face: Dict) -> float:
    return float(face.get("quality_score") or 0.0)


def person_models(db: JsonDatabase, person_ids: Optional[Sequence[int]] = None) -> Dict[int, pl.PersonModel]:
    faces = [f for f in db.faces.values()
             if f.get("person_id") is not None and (person_ids is None or f["person_id"] in person_ids)]
    if not faces:
        return {}
    e = db.get_embeddings_for([f["id"] for f in faces])
    return pl.build_person_models(e, [f["person_id"] for f in faces], [face_quality_of(f) for f in faces])


# ---------------------------------------------------------------------------
# The database as a grouping_core snapshot
# ---------------------------------------------------------------------------

def _pending_faces(db: JsonDatabase):
    """(faces that belong to nobody, their snapshot form, the ones dismissed from review)."""
    unassigned = [f for f in db.faces.values() if f.get("person_id") is None]
    vectors = db.get_embeddings_for([f["id"] for f in unassigned])
    pending = [gc.PendingFace(f["id"], vec, face_quality_of(f), frame_key(f),
                              set(f.get("rejected_person_ids") or ()))
               for f, vec in zip(unassigned, vectors)]
    return unassigned, pending, {f["id"] for f in unassigned if f.get("review_dismissed")}


def _body_inputs(db: JsonDatabase) -> List[gc.BodyInput]:
    return [gc.BodyInput(id=b["id"], media_id=b.get("media_id"), frame_number=b.get("frame_number"),
                         anchor_person_id=db.body_person_id(b), appearance=b.get("appearance"),
                         weak_face_embedding=b.get("weak_face_embedding"),
                         rejected_person_ids=set(b.get("rejected_person_ids") or ()))
            for b in db.bodies.values()]


@dataclass
class GroupingSummary:
    assigned_to_existing: int = 0
    new_people: int = 0
    faces_in_new_people: int = 0
    bodies_linked: int = 0
    pending_faces: int = 0

    def as_text(self) -> str:
        bits = []
        if self.assigned_to_existing:
            bits.append(f"{self.assigned_to_existing} faces added to people you already have")
        if self.new_people:
            bits.append(f"{self.new_people} new people ({self.faces_in_new_people} faces)")
        if self.bodies_linked:
            bits.append(f"{self.bodies_linked} bodies linked by outfit")
        if self.pending_faces:
            bits.append(f"{self.pending_faces} faces left to review")
        return ", ".join(bits) if bits else "Nothing new to group"


def group_library(db: Optional[JsonDatabase] = None, strictness: str = "balanced",
                  match_existing: bool = True, create_new: bool = True, link_bodies: bool = True,
                  log: Callable[[str], None] = print) -> GroupingSummary:
    db = db or JsonDatabase()
    params = pl.params_for(strictness)
    summary = GroupingSummary()

    with db.batch():
        unassigned, pending, dismissed = _pending_faces(db)
        stages = [s for s, wanted in (("match", match_existing), ("cluster", create_new)) if wanted]

        if stages and unassigned:
            models = person_models(db) if match_existing else {}
            plan = gc.plan(gc.Snapshot(models=models, pending=pending, dismissed_face_ids=dismissed), "apply", stages, params)

            for a in plan.assignments:  # apply mode: confident matches only
                db.assign_face_to_person(a.face_id, a.person_id)
                summary.assigned_to_existing += 1
            if match_existing and models:
                log(f"[grouping] {summary.assigned_to_existing} faces matched to existing people")

            if create_new and len(unassigned) > len(plan.assignments):
                for group in plan.groups:
                    if not group.auto_create:
                        continue
                    pid = db.create_person()
                    db.update_person(pid, {"name": f"Person {pid}", "auto_created": True})
                    db.batch_assign_faces(group.face_ids, pid)
                    best = max((db.get_face(fid) for fid in group.face_ids), key=face_quality_of)
                    db.set_person_avatar(pid, best["id"])
                    summary.new_people += 1
                    summary.faces_in_new_people += len(group.face_ids)
                log(f"[grouping] {summary.new_people} new people created")

        if link_bodies and db.bodies:
            summary.bodies_linked = relink_bodies(db, params)

        summary.pending_faces = sum(1 for f in db.faces.values() if f.get("person_id") is None)
    return summary


def relink_bodies(db: JsonDatabase, params: pl.GroupingParams) -> int:
    """Re-derive outfit / weak-face body links (manual links are left alone)."""
    linked = 0
    with db.batch():
        for body in db.bodies.values():
            if body.get("link_method") in DERIVED_BODY_LINKS:
                body["person_id"] = None
                body["link_method"] = None
                body["link_confidence"] = None
        db.save_db()
        models = person_models(db)
        if not models:
            return 0
        plan = gc.plan(gc.Snapshot(models=models, bodies=_body_inputs(db)), "apply", ["bodies"], params)
        for link in plan.body_links:
            if link.decision == "auto":
                db.link_body_to_person(link.body_id, link.person_id, link.method, link.confidence)
                linked += 1
    return linked


# ---------------------------------------------------------------------------
# What the Review tab shows
# ---------------------------------------------------------------------------

@dataclass
class FaceSuggestion:
    face_id: int
    person_id: int
    score: float


@dataclass
class GroupSuggestion:
    face_ids: List[int]
    cohesion: float
    quality: float


@dataclass
class ReviewState:
    suggestions: Dict[int, List[FaceSuggestion]] = field(default_factory=dict)  # person -> faces to confirm
    groups: List[GroupSuggestion] = field(default_factory=list)
    duplicates: List[Tuple[int, int, float]] = field(default_factory=list)
    body_links: List[pl.BodyLink] = field(default_factory=list)
    unsorted_face_ids: List[int] = field(default_factory=list)

    @property
    def suggested_face_count(self) -> int:
        return sum(len(v) for v in self.suggestions.values())

    @property
    def total(self) -> int:
        return (self.suggested_face_count + len(self.groups) + len(self.duplicates)
                + len(self.body_links))


def review_state(db: Optional[JsonDatabase] = None, strictness: str = "balanced",
                 max_suggestions_per_person: int = 60) -> ReviewState:
    """Everything the gallery wants a decision on. Pure read - nothing is changed."""
    db = db or JsonDatabase()
    params = pl.params_for(strictness)
    _, pending, dismissed = _pending_faces(db)
    snapshot = gc.Snapshot(models=person_models(db), pending=pending, bodies=_body_inputs(db),
                           distinct_pairs=db.distinct_pairs(), dismissed_face_ids=dismissed)
    plan = gc.plan(snapshot, "review", gc.STAGES, params, max_suggestions_per_person)

    state = ReviewState()
    for a in plan.assignments:  # already best-first per person and capped
        state.suggestions.setdefault(a.person_id, []).append(FaceSuggestion(a.face_id, a.person_id, a.score))
    state.groups = [GroupSuggestion(g.face_ids, g.cohesion, g.quality) for g in plan.groups]
    state.duplicates = [(d.person_a, d.person_b, d.score) for d in plan.duplicates]
    state.body_links = list(plan.body_links)
    state.unsorted_face_ids = list(plan.unsorted_face_ids)
    return state


# ---------------------------------------------------------------------------
# Actions the Review tab takes
# ---------------------------------------------------------------------------

def accept_faces(db: JsonDatabase, face_ids: Sequence[int], person_id: int):
    db.batch_assign_faces(list(face_ids), person_id)


def reject_faces(db: JsonDatabase, face_ids: Sequence[int], person_id: int):
    with db.batch():
        for fid in face_ids:
            db.reject_face_from_person(fid, person_id)


def create_person_from_faces(db: JsonDatabase, face_ids: Sequence[int], name: Optional[str] = None) -> int:
    with db.batch():
        pid = db.create_person(name)
        if not name:
            db.update_person(pid, {"name": f"Person {pid}", "auto_created": True})
        db.batch_assign_faces(list(face_ids), pid)
        faces = [db.get_face(fid) for fid in face_ids]
        best = max((f for f in faces if f), key=face_quality_of, default=None)
        if best:
            db.set_person_avatar(pid, best["id"])
    return pid
