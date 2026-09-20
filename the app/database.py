"""
Antigravity Local - Database Module
JSON-based storage for face embedding and metadata.
Replaces PostgreSQL/pgvector with local JSON files and numpy-based similarity search.
"""

import os
import json
import time
import shutil
import logging
import threading
import contextlib
import numpy as np
from datetime import datetime
from typing import Optional, List, Tuple, Dict, Any, Iterable, Set
from pathlib import Path

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Constants
DATA_DIR = Path("data")
PERSONS_FILE = DATA_DIR / "persons.json"
FACES_FILE = DATA_DIR / "faces.json"

# Embedding dimension (InsightFace Buffalo_L produces 512-d embeddings)
EMBEDDING_DIM = 512

# (attribute, file name, indent). persons.json stays human-readable; the big
# collections are written compact.
_COLLECTIONS = (
    ("persons", "persons.json", 2),
    ("faces", "faces.json", None),
    ("bodies", "bodies.json", None),
    ("media", "media.json", None),
)


def norm_path(path: str) -> str:
    """Key used to recognise the same media file across scans."""
    return os.path.normcase(os.path.abspath(str(path)))


class JsonDatabase:
    """Local JSON store.

    persons/faces as before, plus (gallery v2):
      bodies - person detections: bbox, keypoints, outfit descriptor, and either
               face_id (linked through its face) or person_id + link_method
      media  - one record per scanned photo/video with every detection in it

    Only the default instance (no data_dir) is a process-wide singleton; pass a
    data_dir for an isolated store (tests, sandboxes).
    """
    _instance = None

    def __new__(cls, data_dir=None):
        if data_dir is not None:
            return super(JsonDatabase, cls).__new__(cls)
        if cls._instance is None:
            cls._instance = super(JsonDatabase, cls).__new__(cls)
        return cls._instance

    def __init__(self, data_dir=None):
        if getattr(self, "_initialized", False):
            return
        self.data_dir = Path(data_dir) if data_dir is not None else DATA_DIR

        self.persons: Dict[int, Dict[str, Any]] = {}
        self.faces: Dict[int, Dict[str, Any]] = {}
        self.bodies: Dict[int, Dict[str, Any]] = {}
        self.media: Dict[int, Dict[str, Any]] = {}

        self.next_person_id = 1
        self.next_face_id = 1
        self.next_body_id = 1
        self.next_media_id = 1

        self.version = 0            # bumps on every load/save; UI caches key on it
        self._lock = threading.RLock()
        self._defer_depth = 0
        self._dirty = False
        self._disk_sig = None
        self._media_by_path: Dict[str, int] = {}
        self._emb_cache = None

        self._load_db()
        self._initialized = True

    # --- Files ---

    def _file(self, name: str) -> Path:
        return self.data_dir / name

    def _signature(self):
        sig = []
        for _, name, _ in _COLLECTIONS:
            try:
                st = self._file(name).stat()
                sig.append((st.st_mtime_ns, st.st_size))
            except OSError:
                sig.append(None)
        return tuple(sig)

    def _load_db(self):
        """Load data from JSON files."""
        with self._lock:
            self.data_dir.mkdir(parents=True, exist_ok=True)
            for attr, name, _ in _COLLECTIONS:
                items, next_id = {}, 1
                path = self._file(name)
                if path.exists():
                    try:
                        with open(path, 'r', encoding='utf-8') as f:
                            data = json.load(f)
                        if isinstance(data, dict) and "items" in data:
                            items = {int(k): v for k, v in data["items"].items()}
                            next_id = data.get("next_id", 1)
                    except Exception as e:
                        logger.error(f"Failed to load {name}: {e}")
                setattr(self, attr, items)
                id_attr = {"persons": "next_person_id", "faces": "next_face_id",
                           "bodies": "next_body_id", "media": "next_media_id"}[attr]
                setattr(self, id_attr, max(next_id, max(items, default=0) + 1))
            self._media_by_path = {norm_path(m["path"]): mid for mid, m in self.media.items() if m.get("path")}
            self._emb_cache = None
            self._disk_sig = self._signature()
            self.version += 1

    def refresh_if_changed(self) -> bool:
        """Reload if another process (e.g. the job worker saving LoRA info)
        rewrote the files since we last loaded or saved them. Without this, our
        next save would silently overwrite its changes."""
        with self._lock:
            if self._defer_depth or self._signature() == self._disk_sig:
                return False
            logger.info("Data files changed on disk - reloading")
            self._load_db()
            return True

    def save_db(self):
        """Save data to JSON files atomically (deferred inside batch())."""
        with self._lock:
            if self._defer_depth:
                self._dirty = True
                return
            self.data_dir.mkdir(parents=True, exist_ok=True)
            for attr, name, indent in _COLLECTIONS:
                items = getattr(self, attr)
                path = self._file(name)
                if attr in ("bodies", "media") and not items and not path.exists():
                    continue  # don't create empty files for stores that never used them
                id_attr = {"persons": "next_person_id", "faces": "next_face_id",
                           "bodies": "next_body_id", "media": "next_media_id"}[attr]
                try:
                    temp_file = path.with_suffix('.tmp')
                    with open(temp_file, 'w', encoding='utf-8') as f:
                        json.dump({"next_id": getattr(self, id_attr), "items": items}, f,
                                  indent=indent, separators=None if indent else (',', ':'), default=str)
                    os.replace(temp_file, path)
                except Exception as e:
                    logger.error(f"Failed to save {name}: {e}")
            self._dirty = False
            self._disk_sig = self._signature()
            self.version += 1

    # Older callers
    save_persons = save_db
    save_faces = save_db

    @contextlib.contextmanager
    def batch(self):
        """Group many changes into one write (scanning, grouping, bulk edits)."""
        with self._lock:
            if not self._defer_depth:
                self.refresh_if_changed()
            self._defer_depth += 1
        try:
            yield self
        finally:
            with self._lock:
                self._defer_depth -= 1
                if not self._defer_depth and self._dirty:
                    self.save_db()

    def flush(self):
        """Write pending batched changes now (keeps the batch open) - lets a long
        scan persist progress so an interrupted run can resume."""
        with self._lock:
            if self._dirty:
                depth, self._defer_depth = self._defer_depth, 0
                try:
                    self.save_db()
                finally:
                    self._defer_depth = depth

    # --- Person Management ---

    def create_person(self, name: Optional[str] = None) -> int:
        self.refresh_if_changed()
        pid = self.next_person_id
        self.next_person_id += 1
        
        now = datetime.utcnow().isoformat()
        if not name:
            name = f"Person_{pid}"
            
        self.persons[pid] = {
            "id": pid,
            "name": name,
            "face_count": 0,
            "created_at": now,
            "updated_at": now
        }
        self.save_db()
        return pid

    def get_person(self, person_id: int) -> Optional[Dict]:
        return self.persons.get(person_id)

    def get_all_persons(self) -> List[Dict]:
        return list(self.persons.values())
        
    def get_person_by_id(self, person_id: int) -> Optional[Dict]:
        return self.persons.get(person_id)

    def get_all_faces(self) -> List[Dict]:
        return list(self.faces.values())

    def update_person_name(self, person_id: int, name: str):
        if person_id in self.persons:
            self.persons[person_id]["name"] = name
            self.persons[person_id]["updated_at"] = datetime.utcnow().isoformat()
            self.save_db()

    def update_person(self, person_id: int, updates: Dict):
        """Update person fields (e.g. name, updated_at)."""
        if person_id in self.persons:
            for key, val in updates.items():
                self.persons[person_id][key] = val
            if "updated_at" not in updates:
                self.persons[person_id]["updated_at"] = datetime.utcnow().isoformat()
            self.save_db()

    def set_person_lora_info(self, person_id: int, trigger_word: Optional[str] = None, lora_path: Optional[str] = None):
        """Attach LoRA training metadata to a person record."""
        if person_id not in self.persons:
            return
        if trigger_word is not None:
            self.persons[person_id]["trigger_word"] = trigger_word
        if lora_path is not None:
            self.persons[person_id]["lora_path"] = lora_path
        self.persons[person_id]["updated_at"] = datetime.utcnow().isoformat()
        self.save_db()

    def get_person_lora_info(self, person_id: int) -> Dict[str, Optional[str]]:
        """Return {trigger_word, lora_path} for a person, both None if unset."""
        person = self.persons.get(person_id, {})
        return {
            "trigger_word": person.get("trigger_word"),
            "lora_path": person.get("lora_path"),
        }

    def delete_person(self, person_id: int):
        """Delete a person. Faces associated with this person will become unassigned."""
        self.refresh_if_changed()
        if person_id in self.persons:
            del self.persons[person_id]

            # Unassign faces
            for face in self.faces.values():
                if face.get("person_id") == person_id:
                    face["person_id"] = None

            # Bodies linked straight to this person (no face of their own) come loose too
            for body in self.bodies.values():
                if body.get("person_id") == person_id:
                    body["person_id"] = None
                    body["link_method"] = None
                    body["link_confidence"] = None
            for other in self.persons.values():
                if person_id in (other.get("distinct_from") or ()):
                    other["distinct_from"] = [p for p in other["distinct_from"] if p != person_id]

            self.save_db()

    def set_person_avatar(self, person_id: int, face_id: int) -> bool:
        """Set a specific face as the primary avatar for a person."""
        if person_id not in self.persons or face_id not in self.faces:
            return False
        self.persons[person_id]["avatar_face_id"] = face_id
        self.persons[person_id]["updated_at"] = datetime.utcnow().isoformat()
        self.save_db()
        return True

    def get_person_avatar_face(self, person_id: int) -> Optional[Dict]:
        """Get the primary avatar face for a person, falling back to the highest quality face."""
        if person_id not in self.persons:
            return None
        person = self.persons[person_id]
        avatar_fid = person.get("avatar_face_id")
        if avatar_fid and avatar_fid in self.faces:
            return self.faces[avatar_fid]
        # Fallback to highest quality face for this person
        p_faces = self.get_faces_by_person(person_id)
        if not p_faces:
            return None
        return max(p_faces, key=lambda f: f.get("quality_score", 0.0))

    # --- Face Management ---

    def add_face(self,
                 embedding: List[float],
                 source_path: str,
                 person_id: Optional[int] = None,
                 bbox: Optional[Dict] = None,
                 quality_score: float = 0.0,
                 image_path: Optional[str] = None,
                 extra: Optional[Dict[str, Any]] = None) -> int:
        """`extra` carries the gallery-v2 detection metadata (media_id,
        frame_number, det_score, kps, pose, sharpness, quality_version, ...)."""
        self.refresh_if_changed()
        fid = self.next_face_id
        self.next_face_id += 1

        now = datetime.utcnow().isoformat()

        # Ensure embedding is a list (if numpy array came in)
        if hasattr(embedding, "tolist"):
            embedding = embedding.tolist()
        # 6 decimals is far below what cosine similarity can tell apart and
        # keeps faces.json (and its per-save cost) about a third of the size
        embedding = [round(float(v), 6) for v in embedding]

        self.faces[fid] = {
            "id": fid,
            "embedding": embedding,
            "source_path": source_path,
            "person_id": person_id,
            "bbox_x": bbox.get('x') if bbox else None,
            "bbox_y": bbox.get('y') if bbox else None,
            "bbox_width": bbox.get('w') if bbox else None,
            "bbox_height": bbox.get('h') if bbox else None,
            "quality_score": quality_score,
            "image_path": image_path,
            "created_at": now
        }
        if extra:
            self.faces[fid].update(extra)

        if person_id and person_id in self.persons:
            self.persons[person_id]["face_count"] += 1
            self.persons[person_id]["updated_at"] = now

        self._append_embedding(fid, embedding)
        self.save_db()
        return fid

    def update_face(self, face_id: int, updates: Dict[str, Any]) -> bool:
        """Patch a face record (used when a re-scan finds better metadata for a
        face that's already in the gallery)."""
        self.refresh_if_changed()
        face = self.faces.get(face_id)
        if face is None:
            return False
        face.update(updates)
        if "embedding" in updates:
            self._emb_cache = None
        self.save_db()
        return True

    def get_faces_by_person(self, person_id: int) -> List[Dict]:
        # Return simplified objects to match old API somewhat if needed,
        # but for now returning plain dicts is cleaner. Consumers should adapt.
        return [f for f in self.faces.values() if f.get("person_id") == person_id]

    def get_face(self, face_id: int) -> Optional[Dict]:
        return self.faces.get(face_id)

    def get_faces_by_source(self, source_path: str) -> List[Dict]:
        key = norm_path(source_path)
        return [f for f in self.faces.values()
                if f.get("source_path") and norm_path(f["source_path"]) == key]

    # --- Vector Search ---

    def _get_embedding_matrix(self) -> Tuple[np.ndarray, List[int]]:
        """All embeddings as an (N, 512) matrix plus their face ids.

        Cached: rebuilding it per duplicate check made scanning quadratic.
        The stamp catches code that edits self.faces directly."""
        cache = self._emb_cache
        stamp = (len(self.faces), self.next_face_id)
        if cache is not None and cache["stamp"] == stamp:
            return cache["buf"][:cache["n"]], cache["ids"]
        ids = []
        embeddings = []
        for fid, face in self.faces.items():
            if "embedding" in face and face["embedding"]:
                ids.append(fid)
                embeddings.append(face["embedding"])

        if not embeddings:
            matrix = np.array([])
        else:
            # Stack to create (N, 512) matrix
            matrix = np.array(embeddings, dtype=np.float32)
        self._emb_cache = {"stamp": stamp, "buf": matrix, "n": len(ids), "ids": ids}
        return matrix, ids

    def _append_embedding(self, face_id: int, embedding: List[float]):
        """Keep the matrix cache warm while a scan adds faces one at a time -
        rebuilding it on every added face made duplicate checking quadratic."""
        cache = self._emb_cache
        if cache is None or cache["n"] != len(cache["ids"]):
            return
        n, buf = cache["n"], cache["buf"]
        if buf.size == 0 or n >= buf.shape[0]:
            grown = np.zeros((max(32, n * 2), EMBEDDING_DIM), dtype=np.float32)
            if n:
                grown[:n] = buf[:n]
            buf = cache["buf"] = grown
        buf[n] = np.asarray(embedding, dtype=np.float32)
        cache["ids"].append(face_id)
        cache["n"] = n + 1
        cache["stamp"] = (len(self.faces), self.next_face_id)

    def get_embeddings_for(self, face_ids: List[int]) -> np.ndarray:
        """(len(face_ids), 512) matrix in the given order; missing faces are zeros."""
        out = np.zeros((len(face_ids), EMBEDDING_DIM), dtype=np.float32)
        for i, fid in enumerate(face_ids):
            emb = (self.faces.get(fid) or {}).get("embedding")
            if emb:
                out[i] = np.asarray(emb, dtype=np.float32)
        return out

    def find_duplicate(self, embedding: List[float], threshold: float = 0.05) -> Optional[Tuple[int, float]]:
        """
        Check if embedding is a duplicate.
        Returns (face_id, distance) if found, else None.
        """
        matrix, ids = self._get_embedding_matrix()
        if matrix.size == 0:
            return None
            
        # Normalize query vector
        query = np.array(embedding, dtype=np.float32)
        query_norm = np.linalg.norm(query)
        if query_norm > 0:
            query = query / query_norm
            
        # Normalize database vectors
        norms = np.linalg.norm(matrix, axis=1)
        norms[norms == 0] = 1e-10
        normalized_matrix = matrix / norms[:, np.newaxis]
        
        # Dot product -> Cosine Similarity
        similarities = np.dot(normalized_matrix, query)
        
        # Cosine Distance = 1 - Cosine Similarity
        # Note: floating point errors can make similarity > 1.0 slightly
        distances = 1 - similarities
        distances = np.maximum(distances, 0) # Clamp negative
        
        min_idx = np.argmin(distances)
        min_dist = distances[min_idx]
        
        if min_dist < threshold:
            return (ids[min_idx], float(min_dist))
            
        return None

    def find_similar_faces(self, embedding: List[float], limit: int = 10, threshold: float = 0.5) -> List[Tuple[int, float]]:
        matrix, ids = self._get_embedding_matrix()
        if matrix.size == 0:
            return []
            
        query = np.array(embedding, dtype=np.float32)
        query_norm = np.linalg.norm(query)
        if query_norm > 0:
            query = query / query_norm
            
        norms = np.linalg.norm(matrix, axis=1)
        norms[norms == 0] = 1e-10
        normalized_matrix = matrix / norms[:, np.newaxis]
        
        similarities = np.dot(normalized_matrix, query)
        distances = 1 - similarities
        distances = np.maximum(distances, 0)
        
        # Filter by threshold
        indices = np.where(distances < threshold)[0]
        
        if len(indices) == 0:
            return []
            
        # Sort by distance
        # We need to sort the subset
        filtered_distances = distances[indices]
        
        # Argsort returns indices relative to the filtered array
        sorted_indices_local = np.argsort(filtered_distances)
        
        # Map back to original indices
        final_indices = indices[sorted_indices_local][:limit]
        
        results = []
        for idx in final_indices:
            results.append((ids[idx], float(distances[idx])))
            
        return results

    def assign_face_to_person(self, face_id: int, person_id: Optional[int]):
        """Assign a face to a person, or unassign by passing person_id=None."""
        self.refresh_if_changed()
        if face_id not in self.faces:
            return

        old_pid = self.faces[face_id].get("person_id")
        if old_pid == person_id:
            return
            
        # If moving from another person, decrement their count
        if old_pid and old_pid in self.persons:
            self.persons[old_pid]["face_count"] = max(0, self.persons[old_pid]["face_count"] - 1)
            if self.persons[old_pid].get("avatar_face_id") == face_id:
                self.persons[old_pid]["avatar_face_id"] = None
            self.persons[old_pid]["updated_at"] = datetime.utcnow().isoformat()
            
        self.faces[face_id]["person_id"] = person_id
        
        if person_id and person_id in self.persons:
            self.persons[person_id]["face_count"] = self.persons[person_id].get("face_count", 0) + 1
            self.persons[person_id]["updated_at"] = datetime.utcnow().isoformat()
            
        self.save_db()

    def batch_assign_faces(self, face_ids: List[int], person_id: Optional[int]):
        """Batch assign multiple faces to a person (or unassign them if person_id=None)."""
        self.refresh_if_changed()
        now = datetime.utcnow().isoformat()
        affected_pids = set()
        if person_id and person_id in self.persons:
            affected_pids.add(person_id)

        for fid in face_ids:
            if fid not in self.faces:
                continue
            old_pid = self.faces[fid].get("person_id")
            if old_pid == person_id:
                continue
            if old_pid and old_pid in self.persons:
                self.persons[old_pid]["face_count"] = max(0, self.persons[old_pid].get("face_count", 0) - 1)
                if self.persons[old_pid].get("avatar_face_id") == fid:
                    self.persons[old_pid]["avatar_face_id"] = None
                affected_pids.add(old_pid)
            self.faces[fid]["person_id"] = person_id
            if person_id and person_id in self.persons:
                self.persons[person_id]["face_count"] = self.persons[person_id].get("face_count", 0) + 1

        for pid in affected_pids:
            if pid in self.persons:
                self.persons[pid]["updated_at"] = now

        self.save_db()

    def delete_face(self, face_id: int, delete_file: bool = True) -> bool:
        """Permanently delete a face from the database and optionally from disk."""
        self.refresh_if_changed()
        if face_id not in self.faces:
            return False
        face = self.faces[face_id]
        pid = face.get("person_id")
        if pid and pid in self.persons:
            self.persons[pid]["face_count"] = max(0, self.persons[pid].get("face_count", 0) - 1)
            if self.persons[pid].get("avatar_face_id") == face_id:
                self.persons[pid]["avatar_face_id"] = None
            self.persons[pid]["updated_at"] = datetime.utcnow().isoformat()

        img_path = face.get("image_path")
        if delete_file and img_path and os.path.exists(img_path):
            try:
                os.remove(img_path)
            except Exception as e:
                logger.warning(f"Failed to delete face crop file {img_path}: {e}")

        del self.faces[face_id]
        # A body that was identified through this face loses its link
        for body in self.bodies.values():
            if body.get("face_id") == face_id:
                body["face_id"] = None
        for m in self.media.values():
            dets = m.get("detections")
            if dets:
                m["detections"] = [d for d in dets if not (d[2] == "f" and d[3] == face_id)]
        self._emb_cache = None
        self.save_db()
        return True

    def merge_persons(self, source_person_id: int, target_person_id: int) -> bool:
        """Move all faces from source to target, then delete source."""
        self.refresh_if_changed()
        try:
            source_person_id = int(source_person_id)
            target_person_id = int(target_person_id)
        except (ValueError, TypeError):
            logger.error(f"Invalid person IDs for merge: {source_person_id}, {target_person_id}")
            return False

        if source_person_id == target_person_id:
            logger.warning(f"Cannot merge person into itself: {source_person_id}")
            return False

        if source_person_id not in self.persons:
            logger.warning(f"Source person {source_person_id} not found in database")
            return False

        if target_person_id not in self.persons:
            logger.warning(f"Target person {target_person_id} not found in database")
            return False

        # Move faces
        source_faces_count = 0
        for fid, face in self.faces.items():
            if face.get("person_id") == source_person_id:
                face["person_id"] = target_person_id
                source_faces_count += 1
            rejected = face.get("rejected_person_ids")
            if rejected and source_person_id in rejected:
                # "not this person" still holds once that person is part of the target
                face["rejected_person_ids"] = sorted(
                    {target_person_id if p == source_person_id else p for p in rejected})

        # Move bodies that were linked to the source person directly
        for body in self.bodies.values():
            if body.get("person_id") == source_person_id:
                body["person_id"] = target_person_id
            rejected = body.get("rejected_person_ids")
            if rejected and source_person_id in rejected:
                body["rejected_person_ids"] = sorted(
                    {target_person_id if p == source_person_id else p for p in rejected})

        target = self.persons[target_person_id]
        source = self.persons[source_person_id]
        # Update counts
        target["face_count"] = target.get("face_count", 0) + source_faces_count
        target["updated_at"] = datetime.utcnow().isoformat()
        if not target.get("avatar_face_id") and source.get("avatar_face_id"):
            target["avatar_face_id"] = source["avatar_face_id"]
        if source.get("name") and not target.get("name", "").strip():
            target["name"] = source["name"]
        if source.get("auto_created") and not target.get("auto_created"):
            pass  # a named person absorbing an auto group stays named
        distinct = set(target.get("distinct_from") or ()) | set(source.get("distinct_from") or ())
        distinct.discard(source_person_id)
        distinct.discard(target_person_id)
        if distinct:
            target["distinct_from"] = sorted(distinct)
        for other in self.persons.values():
            if source_person_id in (other.get("distinct_from") or ()):
                other["distinct_from"] = sorted(
                    {target_person_id if p == source_person_id else p for p in other["distinct_from"]}
                    - {other["id"]})

        # Delete source
        del self.persons[source_person_id]
        self.save_db()
        logger.info(f"Successfully merged person {source_person_id} into {target_person_id} ({source_faces_count} faces moved)")
        return True
        
    def get_stats(self) -> Dict[str, int]:
        self.refresh_if_changed()
        unassigned_count = sum(1 for face in self.faces.values() if face.get("person_id") is None)
        linked_bodies = sum(1 for b in self.bodies.values() if self.body_person_id(b) is not None)
        photos = sum(1 for m in self.media.values() if m.get("type") == "image")
        return {
            "total_persons": len(self.persons),
            "total_faces": len(self.faces),
            "unassigned_faces": unassigned_count,
            "total_bodies": len(self.bodies),
            "linked_bodies": linked_bodies,
            "total_media": len(self.media),
            "total_photos": photos,
            "total_videos": len(self.media) - photos,
        }
        
    def auto_assign_to_person(self, face_id: int, embedding: List[float], similarity_threshold: float = 0.35) -> int:
        """
        Automatically assign a face to an existing person based on similarity,
        or create a new person if no match is found.
        """
        # Search for similar faces that are ALREADY assigned to a person
        # We need to find the closest face that has a person_id
        
        matrix, ids = self._get_embedding_matrix()
        if matrix.size == 0:
            # No faces, create new person
            new_pid = self.create_person(f"Person_{face_id}")
            self.assign_face_to_person(face_id, new_pid)
            return new_pid

        # Normalize query
        query = np.array(embedding, dtype=np.float32)
        query /= np.linalg.norm(query)
        
        # Normalize DB
        norms = np.linalg.norm(matrix, axis=1)
        norms[norms == 0] = 1e-10
        normalized_matrix = matrix / norms[:, np.newaxis]
        
        dists = 1 - np.dot(normalized_matrix, query)
        
        # Sort indices by distance
        sorted_indices = np.argsort(dists)
        
        found_match = False
        matched_pid = None
        
        for idx in sorted_indices:
            dist = dists[idx]
            if dist > similarity_threshold:
                break
                
            fid = ids[idx]
            face_data = self.faces.get(fid)
            
            # Skip self
            if fid == face_id:
                continue
                
            pid = face_data.get("person_id")
            if pid is not None:
                matched_pid = pid
                found_match = True
                break
        
        if found_match and matched_pid:
            self.assign_face_to_person(face_id, matched_pid)
            return matched_pid
        else:
            new_pid = self.create_person(f"Person_{face_id}")
            self.assign_face_to_person(face_id, new_pid)
            return new_pid

    # -----------------------------------------------------------------
    # Corrections the user makes (so auto-grouping never re-does them)
    # -----------------------------------------------------------------

    def reject_face_from_person(self, face_id: int, person_id: Optional[int] = None):
        """"This face is not that person": unassign it and remember, so
        auto-grouping won't put it back."""
        self.refresh_if_changed()
        face = self.faces.get(face_id)
        if face is None:
            return
        pid = person_id if person_id is not None else face.get("person_id")
        with self.batch():  # one write, and no reload between the two edits
            if pid is not None:
                face["rejected_person_ids"] = sorted(set(face.get("rejected_person_ids") or ()) | {int(pid)})
            if face.get("person_id") == pid:
                self.assign_face_to_person(face_id, None)
            self.save_db()

    def reject_body_from_person(self, body_id: int, person_id: Optional[int] = None):
        self.refresh_if_changed()
        body = self.bodies.get(body_id)
        if body is None:
            return
        pid = person_id if person_id is not None else self.body_person_id(body)
        if pid is not None:
            body["rejected_person_ids"] = sorted(set(body.get("rejected_person_ids") or ()) | {int(pid)})
        if body.get("person_id") == pid:
            body["person_id"] = None
            body["link_method"] = None
            body["link_confidence"] = None
        if body.get("face_id") is not None and (self.faces.get(body["face_id"]) or {}).get("person_id") == pid:
            body["face_id"] = None  # the face stays, it just isn't this body's face
        self.save_db()

    def mark_persons_distinct(self, person_a: int, person_b: int):
        """"These two are different people" - keeps the pair out of merge suggestions."""
        self.refresh_if_changed()
        for a, b in ((person_a, person_b), (person_b, person_a)):
            person = self.persons.get(a)
            if person is not None:
                person["distinct_from"] = sorted(set(person.get("distinct_from") or ()) | {int(b)})
        self.save_db()

    def distinct_pairs(self) -> List[Tuple[int, int]]:
        pairs = set()
        for pid, person in self.persons.items():
            for other in person.get("distinct_from") or ():
                pairs.add((min(pid, other), max(pid, other)))
        return sorted(pairs)

    def dismiss_face_group(self, face_ids: Iterable[int]):
        """Hide these faces from "new group" suggestions until they change."""
        self.refresh_if_changed()
        for fid in face_ids:
            face = self.faces.get(fid)
            if face is not None:
                face["review_dismissed"] = True
        self.save_db()

    # -----------------------------------------------------------------
    # Bodies
    # -----------------------------------------------------------------

    def add_body(self, record: Dict[str, Any]) -> int:
        self.refresh_if_changed()
        bid = self.next_body_id
        self.next_body_id += 1
        record = dict(record)
        record["id"] = bid
        record.setdefault("created_at", datetime.utcnow().isoformat())
        record.setdefault("face_id", None)
        record.setdefault("person_id", None)
        record.setdefault("link_method", None)
        record.setdefault("link_confidence", None)
        self.bodies[bid] = record
        self.save_db()
        return bid

    def update_body(self, body_id: int, updates: Dict[str, Any]) -> bool:
        self.refresh_if_changed()
        body = self.bodies.get(body_id)
        if body is None:
            return False
        body.update(updates)
        self.save_db()
        return True

    def get_body(self, body_id: int) -> Optional[Dict]:
        return self.bodies.get(body_id)

    def get_all_bodies(self) -> List[Dict]:
        return list(self.bodies.values())

    def body_person_id(self, body: Dict) -> Optional[int]:
        """Who a body belongs to: its face's person if it has one, else the
        person it was linked to by outfit/weak face/by hand."""
        if not body:
            return None
        fid = body.get("face_id")
        if fid is not None:
            face = self.faces.get(fid)
            if face and face.get("person_id") is not None:
                return face["person_id"]
        pid = body.get("person_id")
        return pid if pid in self.persons else None

    def get_bodies_by_person(self, person_id: int) -> List[Dict]:
        return [b for b in self.bodies.values() if self.body_person_id(b) == person_id]

    def get_bodies_by_media(self, media_id: int) -> List[Dict]:
        return [b for b in self.bodies.values() if b.get("media_id") == media_id]

    def link_body_to_person(self, body_id: int, person_id: Optional[int],
                            method: str = "manual", confidence: Optional[float] = None) -> bool:
        self.refresh_if_changed()
        body = self.bodies.get(body_id)
        if body is None:
            return False
        body["person_id"] = person_id
        body["link_method"] = method if person_id is not None else None
        body["link_confidence"] = confidence
        self.save_db()
        return True

    def delete_body(self, body_id: int, delete_file: bool = True) -> bool:
        self.refresh_if_changed()
        body = self.bodies.pop(body_id, None)
        if body is None:
            return False
        crop = body.get("crop_path")
        if delete_file and crop and os.path.exists(crop):
            try:
                os.remove(crop)
            except Exception as e:
                logger.warning(f"Failed to delete body crop {crop}: {e}")
        for m in self.media.values():
            dets = m.get("detections")
            if dets:
                m["detections"] = [d for d in dets if not (d[2] == "b" and d[3] == body_id)]
        self.save_db()
        return True

    # -----------------------------------------------------------------
    # Media (one record per scanned photo / video)
    # -----------------------------------------------------------------

    def get_media(self, media_id: int) -> Optional[Dict]:
        return self.media.get(media_id)

    def get_all_media(self) -> List[Dict]:
        return list(self.media.values())

    def get_media_by_path(self, path: str) -> Optional[Dict]:
        mid = self._media_by_path.get(norm_path(path))
        return self.media.get(mid) if mid is not None else None

    def upsert_media(self, path: str, fields: Dict[str, Any]) -> int:
        """Create or update the record for a media file; returns its id."""
        self.refresh_if_changed()
        key = norm_path(path)
        mid = self._media_by_path.get(key)
        if mid is None or mid not in self.media:
            mid = self.next_media_id
            self.next_media_id += 1
            self.media[mid] = {"id": mid, "path": str(path), "name": os.path.basename(str(path)),
                               "detections": [], "created_at": datetime.utcnow().isoformat()}
            self._media_by_path[key] = mid
        self.media[mid].update(fields)
        self.save_db()
        return mid

    def delete_media(self, media_id: int, delete_children: bool = False) -> bool:
        self.refresh_if_changed()
        record = self.media.pop(media_id, None)
        if record is None:
            return False
        self._media_by_path.pop(norm_path(record.get("path", "")), None)
        with self.batch():
            if delete_children:
                for bid in [b["id"] for b in self.bodies.values() if b.get("media_id") == media_id]:
                    self.delete_body(bid)
                for fid in [f["id"] for f in self.faces.values() if f.get("media_id") == media_id]:
                    self.delete_face(fid)
            self.save_db()
        return True

    def media_person_ids(self, media_id: int) -> Set[int]:
        """Everyone who appears in one media file, by face or by body."""
        people = set()
        for face in self.faces.values():
            if face.get("media_id") == media_id and face.get("person_id") is not None:
                people.add(face["person_id"])
        for body in self.bodies.values():
            if body.get("media_id") == media_id:
                pid = self.body_person_id(body)
                if pid is not None:
                    people.add(pid)
        return people

    def media_index(self) -> Dict[int, Dict[str, Any]]:
        """media_id -> {faces, bodies, people, body_only_people} in one pass over
        the faces and bodies (the per-media loops above are O(N) each)."""
        index = {mid: {"faces": 0, "bodies": 0, "people": set(), "face_people": set()}
                 for mid in self.media}
        for face in self.faces.values():
            entry = index.get(face.get("media_id"))
            if entry is None:
                continue
            entry["faces"] += 1
            if face.get("person_id") is not None:
                entry["people"].add(face["person_id"])
                entry["face_people"].add(face["person_id"])
        for body in self.bodies.values():
            entry = index.get(body.get("media_id"))
            if entry is None:
                continue
            entry["bodies"] += 1
            pid = self.body_person_id(body)
            if pid is not None:
                entry["people"].add(pid)
        for entry in index.values():
            entry["body_only_people"] = entry["people"] - entry["face_people"]
        return index

    def person_media_ids(self, person_id: int) -> Set[int]:
        media = {f.get("media_id") for f in self.faces.values()
                 if f.get("person_id") == person_id and f.get("media_id") is not None}
        media |= {b.get("media_id") for b in self.bodies.values()
                  if b.get("media_id") is not None and self.body_person_id(b) == person_id}
        return {m for m in media if m in self.media}

    def person_source_paths(self, person_id: int) -> List[str]:
        """Source files for a person, including faces mined before media records
        existed (they only carry source_path)."""
        paths = {}
        for mid in self.person_media_ids(person_id):
            record = self.media[mid]
            paths[norm_path(record["path"])] = record["path"]
        for face in self.faces.values():
            if face.get("person_id") == person_id and face.get("source_path"):
                paths.setdefault(norm_path(face["source_path"]), face["source_path"])
        return list(paths.values())


# --- Module Level Exported Functions (for backward compatibility / ease of use) ---

db_instance = JsonDatabase()

def init_db():
    # Just ensure directory availability
    db_instance._load_db()
    
# Compatibility wrappers
class MockSession:
    def __init__(self, *args, **kwargs): pass
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def diff(self): pass
    def commit(self): pass
    def close(self): pass
    def add(self, *args): pass
    def query(self, *args): return self
    def filter(self, *args): return self
    def all(self): return []

def get_session():
    return MockSession()
    
def get_db():
    return MockSession()

def get_all_persons():
    return db_instance.get_all_persons()
    
def get_person_by_id(person_id):
    return db_instance.get_person_by_id(person_id)

def create_person(name=None):
    return db_instance.create_person(name)

def add_person(name=None):
    return db_instance.create_person(name)
    
def update_person_name(person_id, name):
    db_instance.update_person_name(person_id, name)

def set_person_lora_info(person_id, trigger_word=None, lora_path=None):
    db_instance.set_person_lora_info(person_id, trigger_word, lora_path)

def get_person_lora_info(person_id):
    return db_instance.get_person_lora_info(person_id)

def add_face(embedding, source_path, person_id=None, bbox=None, quality_score=0.0, image_path=None):
    return db_instance.add_face(embedding, source_path, person_id, bbox, quality_score, image_path)

def get_faces_by_person(person_id):
    return db_instance.get_faces_by_person(person_id)

def get_all_faces():
    return db_instance.get_all_faces()

def find_duplicate(session=None, embedding=None, threshold=0.05):
    # session arg is ignored, kept for compatibility
    return db_instance.find_duplicate(embedding, threshold)

def find_similar_faces(session=None, embedding=None, limit=10, threshold=0.5):
    return db_instance.find_similar_faces(embedding, limit, threshold)

def assign_face_to_person(face_id, person_id):
    return db_instance.assign_face_to_person(face_id, person_id)
    
def auto_assign_to_person(session=None, face_id=None, embedding=None, similarity_threshold=0.35):
    if face_id is None or embedding is None: return None
    return db_instance.auto_assign_to_person(face_id, embedding, similarity_threshold)
    
def merge_persons(*args, **kwargs):
    """
    Merge source_person into target_person.
    Supports both:
      merge_persons(source_id, target_id)
      merge_persons(session, source_id, target_id)
      merge_persons(source_person_id=..., target_person_id=...)
    """
    if len(args) == 2:
        src, tgt = args[0], args[1]
    elif len(args) >= 3:
        src, tgt = args[1], args[2]
    else:
        src = kwargs.get("source_person_id", kwargs.get("source_id"))
        tgt = kwargs.get("target_person_id", kwargs.get("target_id"))

    if src is not None and tgt is not None:
        return db_instance.merge_persons(src, tgt)
    return False

def delete_person(person_id):
    db_instance.delete_person(person_id)

def delete_face(face_id, delete_file=True):
    return db_instance.delete_face(face_id, delete_file=delete_file)

def set_person_avatar(person_id, face_id):
    return db_instance.set_person_avatar(person_id, face_id)

def get_person_avatar_face(person_id):
    return db_instance.get_person_avatar_face(person_id)

def batch_assign_faces(face_ids, person_id):
    return db_instance.batch_assign_faces(face_ids, person_id)
    
def get_stats():
    return db_instance.get_stats()

def update_face(face_id, updates):
    return db_instance.update_face(face_id, updates)

def get_faces_by_source(source_path):
    return db_instance.get_faces_by_source(source_path)

def reject_face_from_person(face_id, person_id=None):
    return db_instance.reject_face_from_person(face_id, person_id)

def mark_persons_distinct(person_a, person_b):
    return db_instance.mark_persons_distinct(person_a, person_b)

def add_body(record):
    return db_instance.add_body(record)

def get_all_bodies():
    return db_instance.get_all_bodies()

def get_bodies_by_person(person_id):
    return db_instance.get_bodies_by_person(person_id)

def link_body_to_person(body_id, person_id, method="manual", confidence=None):
    return db_instance.link_body_to_person(body_id, person_id, method, confidence)

def get_all_media():
    return db_instance.get_all_media()

def get_media_by_path(path):
    return db_instance.get_media_by_path(path)

def person_media_ids(person_id):
    return db_instance.person_media_ids(person_id)

def test_vector_similarity():
    print("Testing vector similarity...")
    test_embedding = np.random.rand(EMBEDDING_DIM).astype(np.float32)
    test_embedding /= np.linalg.norm(test_embedding)
    
    # Add a dummy face
    fid = db_instance.add_face(test_embedding.tolist(), "test_source.jpg")
    print(f"Added test face {fid}")
    
    # Search for it
    dup = db_instance.find_duplicate(test_embedding.tolist())
    if dup:
        print(f"Found duplicate: {dup}")
        return True
    else:
        print("Failed to find duplicate!")
        return False

if __name__ == "__main__":
    init_db()
    test_vector_similarity()
