"""
Grouping service - runs person_linking over the database.

group_library() is the "sort my gallery" action: match new faces to people you
already have, group what's left into new people, and tie faceless bodies to a
person when the evidence is strong. Anything less than certain is left for
review_state(), which is what the Gallery's Review tab shows.

The decisions themselves are made by grouping_core.plan() - the same DB-free
code the mobile API serves - over a snapshot of this JSON database. This module
only builds that snapshot and applies the result, so the Streamlit gallery and
the phone reuse the same matching, clustering and body-linking decisions.
"""

from collections import defaultdict
from dataclasses import dataclass, field
from itertools import combinations
from typing import Callable, Dict, List, Optional, Sequence, Tuple

import grouping_core as gc
import person_linking as pl
from database import JsonDatabase, norm_path

DERIVED_BODY_LINKS = ("appearance", "weak_face", "event_outfit")
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
             if f.get("person_id") is not None and _eligible(f)
             and not db.persons.get(f["person_id"], {}).get("grouping_locked")
             and (person_ids is None or f["person_id"] in person_ids)]
    if not faces:
        return {}
    e = db.get_embeddings_for([f["id"] for f in faces])
    return pl.build_person_models(e, [f["person_id"] for f in faces], [face_quality_of(f) for f in faces])


# ---------------------------------------------------------------------------
# The database as a grouping_core snapshot
# ---------------------------------------------------------------------------

def _eligible(face):
    return (not face.get("hidden") and face.get("ownership") != "none"
            and (face.get("face_px") is None or face["face_px"] >= 40))


def _face_occurrences(db):
    """Index every observed frame of a compacted face, including its stored representative."""
    frames = defaultdict(set)
    for face in db.faces.values():
        if not face.get("hidden") and (key := frame_key(face)) is not None:
            frames[face["id"]].add(key)
    for mid, media in db.media.items():
        for hit in media.get("detections") or ():
            if len(hit) < 4:
                continue
            frame, _, kind, fid = hit[:4]
            if kind == "f" and fid in db.faces and not db.faces[fid].get("hidden"):
                if frame is not None or media.get("type") != "video":
                    frames[fid].add((mid, frame))
    return frames


def _people_in_frames(db, occurrences):
    people = defaultdict(set)
    for fid, keys in occurrences.items():
        person = db.faces[fid].get("person_id")
        if person is not None:
            for key in keys:
                people[key].add(person)
    return people


def _pending_faces(db: JsonDatabase, occurrences, occupied):
    unassigned = [f for f in db.faces.values() if f.get("person_id") is None and _eligible(f)
                  and f.get("ownership") != "manual"]
    vectors = db.get_embeddings_for([f["id"] for f in unassigned])
    pending = []
    for face, vec in zip(unassigned, vectors):
        fid = face["id"]
        rejected = set(face.get("rejected_person_ids") or ())
        rejected.update(pid for key in occurrences[fid] for pid in occupied.get(key, ()))
        pending.append(gc.PendingFace(fid, vec, face_quality_of(face), frame_key(face), rejected))
    return unassigned, pending, {f["id"] for f in unassigned if f.get("review_dismissed")}


def _body_inputs(db: JsonDatabase, occupied, refresh_derived=False):
    inputs = []
    for body in db.bodies.values():
        if body.get("hidden") or body.get("ownership") == "none":
            continue
        key = frame_key(body)
        anchor = db.body_person_id(body)
        if refresh_derived and _can_rederive_body(db, body):
            anchor = db.faces.get(body.get("face_id"), {}).get("person_id")
        if anchor is None and body.get("ownership") == "manual":
            continue
        rejected = set(body.get("rejected_person_ids") or ())
        if anchor is None:
            if body.get("face_id") in db.faces:
                continue  # Wait for the body's own confirmed face.
            if key is not None:
                rejected.update(occupied.get(key, ()))
        mid = body.get("media_id")
        if mid is None and body.get("source_path"):
            mid = norm_path(body["source_path"])
        inputs.append(gc.BodyInput(id=body["id"], media_id=mid, frame_number=body.get("frame_number"),
                                   anchor_person_id=anchor, appearance=body.get("appearance"),
                                   weak_face_embedding=body.get("weak_face_embedding"),
                                   rejected_person_ids=rejected))
    return inputs


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
            bits.append(f"{self.bodies_linked} bodies linked to people")
        if self.pending_faces:
            bits.append(f"{self.pending_faces} faces left to review")
        return ", ".join(bits) if bits else "Nothing new to group"


def _group_frames(face_ids, occurrences):
    frames = set()
    for fid in face_ids:
        keys = occurrences[fid]
        if frames & keys:
            return None
        frames.update(keys)
    return frames


def _can_create_person(db, group, occurrences):
    if not group.auto_create:
        return False
    frames = _group_frames(group.face_ids, occurrences)
    if frames is None:
        return False
    media_ids = {mid for mid, _ in frames}
    if len(media_ids) != 1:
        return True
    media = db.media.get(next(iter(media_ids)), {})
    if media.get("type") != "video":
        return True
    positions = [frame for _, frame in frames if frame is not None]
    views = {tuple(db.faces[fid].get("embedding") or ()) for fid in group.face_ids}
    return (len(positions) >= 5 and len(views) >= 3 and group.quality >= .55
            and group.cohesion >= .70
            and max(positions) - min(positions) >= 4 * (media.get("fps") or 30))


def group_library(db: Optional[JsonDatabase] = None, strictness: str = "balanced",
                  match_existing: bool = True, create_new: bool = True, link_bodies: bool = True,
                  log: Callable[[str], None] = print) -> GroupingSummary:
    db = db or JsonDatabase()
    params = pl.params_for(strictness)
    summary = GroupingSummary()

    with db.batch():
        occurrences = _face_occurrences(db)
        occupied = _people_in_frames(db, occurrences)
        unassigned, pending, dismissed = _pending_faces(db, occurrences, occupied)
        stages = [s for s, wanted in (("match", match_existing), ("cluster", create_new)) if wanted]

        if stages and unassigned:
            models = person_models(db) if match_existing else {}
            plan = gc.plan(gc.Snapshot(models=models, pending=pending, dismissed_face_ids=dismissed), "apply", stages, params)

            by_person = defaultdict(list)
            for a in sorted(plan.assignments, key=lambda a: -a.score):
                keys = occurrences[a.face_id]
                if any(a.person_id in occupied[key] for key in keys):
                    continue
                by_person[a.person_id].append(a.face_id)
                for key in keys:
                    occupied[key].add(a.person_id)
                summary.assigned_to_existing += 1
            for pid, face_ids in by_person.items():
                db.batch_assign_faces(face_ids, pid)
            if match_existing and models:
                log(f"[grouping] {summary.assigned_to_existing} faces matched to existing people")

            if create_new and len(unassigned) > len(plan.assignments):
                for group in plan.groups:
                    if not _can_create_person(db, group, occurrences):
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
            summary.bodies_linked = relink_bodies(db, params, _people_in_frames(db, occurrences))

        summary.pending_faces = sum(1 for f in db.faces.values() if f.get("person_id") is None)
    return summary


def _can_rederive_body(db, body):
    return (body.get("link_method") in DERIVED_BODY_LINKS and body.get("ownership") not in ("manual", "none")
            and not db.persons.get(body.get("person_id"), {}).get("grouping_locked"))


def relink_bodies(db: JsonDatabase, params: pl.GroupingParams, occupied=None) -> int:
    """Re-derive outfit / weak-face body links (manual links are left alone)."""
    linked = 0
    with db.batch():
        models = person_models(db)
        if occupied is None:
            occupied = _people_in_frames(db, _face_occurrences(db))
        plan = gc.plan(gc.Snapshot(models=models, bodies=_body_inputs(db, occupied, refresh_derived=True)),
                       "apply", ["bodies"], params)
        for body in db.bodies.values():
            if _can_rederive_body(db, body):
                body["person_id"] = None
                body["link_method"] = None
                body["link_confidence"] = None
        db.save_db()
        for link in plan.body_links:
            if link.decision == "auto" and not db.persons.get(link.person_id, {}).get("grouping_locked"):
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
    occurrences = _face_occurrences(db)
    occupied = _people_in_frames(db, occurrences)
    _, pending, dismissed = _pending_faces(db, occurrences, occupied)
    distinct = set(db.distinct_pairs())
    for people in occupied.values():
        distinct.update(combinations(sorted(people), 2))
    snapshot = gc.Snapshot(models=person_models(db), pending=pending, bodies=_body_inputs(db, occupied),
                           distinct_pairs=sorted(distinct), dismissed_face_ids=dismissed)
    plan = gc.plan(snapshot, "review", gc.STAGES, params, max_suggestions_per_person)

    state = ReviewState()
    for a in plan.assignments:  # already best-first per person and capped
        state.suggestions.setdefault(a.person_id, []).append(FaceSuggestion(a.face_id, a.person_id, a.score))
    unsorted = list(plan.unsorted_face_ids)
    for group in plan.groups:
        if _group_frames(group.face_ids, occurrences) is None:
            unsorted.extend(group.face_ids)
        else:
            state.groups.append(GroupSuggestion(group.face_ids, group.cohesion, group.quality))
    state.duplicates = [(d.person_a, d.person_b, d.score) for d in plan.duplicates]
    state.body_links = list(plan.body_links)
    state.unsorted_face_ids = unsorted
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
