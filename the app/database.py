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
import numpy as np
from datetime import datetime
from typing import Optional, List, Tuple, Dict, Any
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

class JsonDatabase:
    _instance = None
    _initialized = False

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(JsonDatabase, cls).__new__(cls)
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        
        self.persons: Dict[int, Dict[str, Any]] = {}
        self.faces: Dict[int, Dict[str, Any]] = {}
        
        self.next_person_id = 1
        self.next_face_id = 1
        
        self._load_db()
        self._initialized = True

    def _load_db(self):
        """Load data from JSON files."""
        if not DATA_DIR.exists():
            DATA_DIR.mkdir(parents=True, exist_ok=True)
        
        # Load Persons
        if PERSONS_FILE.exists():
            try:
                with open(PERSONS_FILE, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    if isinstance(data, dict) and "items" in data:
                        self.persons = {int(k): v for k, v in data["items"].items()}
                        self.next_person_id = data.get("next_id", 1)
                    else:
                        self.persons = {}
                        self.next_person_id = 1
            except Exception as e:
                logger.error(f"Failed to load persons.json: {e}")
                self.persons = {}
        else:
             self.persons = {}

        # Load Faces
        if FACES_FILE.exists():
            try:
                with open(FACES_FILE, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    if isinstance(data, dict) and "items" in data:
                        self.faces = {int(k): v for k, v in data["items"].items()}
                        self.next_face_id = data.get("next_id", 1)
                    else:
                        self.faces = {}
                        self.next_face_id = 1
            except Exception as e:
                logger.error(f"Failed to load faces.json: {e}")
                self.faces = {}
        else:
            self.faces = {}
            
    def save_db(self):
        """Save data to JSON files atomically."""
        if not DATA_DIR.exists():
            DATA_DIR.mkdir(parents=True, exist_ok=True)

        # Save Persons
        try:
            temp_file = PERSONS_FILE.with_suffix('.tmp')
            with open(temp_file, 'w', encoding='utf-8') as f:
                json.dump({
                    "next_id": self.next_person_id,
                    "items": self.persons
                }, f, indent=2, default=str)
            
            # Atomic replace (simulated)
            if PERSONS_FILE.exists():
                os.replace(temp_file, PERSONS_FILE)
            else:
                os.rename(temp_file, PERSONS_FILE)
                
        except Exception as e:
            logger.error(f"Failed to save persons.json: {e}")

        # Save Faces
        try:
            temp_file = FACES_FILE.with_suffix('.tmp')
            with open(temp_file, 'w', encoding='utf-8') as f:
                json.dump({
                    "next_id": self.next_face_id,
                    "items": self.faces
                }, f, indent=2, default=str)
                
            if FACES_FILE.exists():
                os.replace(temp_file, FACES_FILE)
            else:
                os.rename(temp_file, FACES_FILE)
                
        except Exception as e:
            logger.error(f"Failed to save faces.json: {e}")

    # --- Person Management ---

    def create_person(self, name: Optional[str] = None) -> int:
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
        if person_id in self.persons:
            del self.persons[person_id]
            
            # Unassign faces
            for face in self.faces.values():
                if face.get("person_id") == person_id:
                    face["person_id"] = None
            
            self.save_db()

    # --- Face Management ---

    def add_face(self, 
                 embedding: List[float], 
                 source_path: str, 
                 person_id: Optional[int] = None,
                 bbox: Optional[Dict] = None,
                 quality_score: float = 0.0,
                 image_path: Optional[str] = None) -> int:
        
        fid = self.next_face_id
        self.next_face_id += 1
        
        now = datetime.utcnow().isoformat()
        
        # Ensure embedding is a list (if numpy array came in)
        if hasattr(embedding, "tolist"):
            embedding = embedding.tolist()
            
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
        
        if person_id and person_id in self.persons:
            self.persons[person_id]["face_count"] += 1
            self.persons[person_id]["updated_at"] = now
            
        self.save_db()
        return fid

    def get_faces_by_person(self, person_id: int) -> List[Dict]:
        # Return simplified objects to match old API somewhat if needed, 
        # but for now returning plain dicts is cleaner. Consumers should adapt.
        return [f for f in self.faces.values() if f.get("person_id") == person_id]

    def get_face(self, face_id: int) -> Optional[Dict]:
        return self.faces.get(face_id)

    # --- Vector Search ---

    def _get_embedding_matrix(self) -> Tuple[np.ndarray, List[int]]:
        """Helper to get all embeddings as a matrix and their corresponding IDs."""
        ids = []
        embeddings = []
        for fid, face in self.faces.items():
            if "embedding" in face and face["embedding"]:
                ids.append(fid)
                embeddings.append(face["embedding"])
        
        if not embeddings:
            return np.array([]), []
            
        # Stack to create (N, 512) matrix
        return np.array(embeddings, dtype=np.float32), ids

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

    def assign_face_to_person(self, face_id: int, person_id: int):
        if face_id not in self.faces:
            return
        
        old_pid = self.faces[face_id].get("person_id")
        
        # If moving from another person, decrement their count
        if old_pid and old_pid in self.persons:
            self.persons[old_pid]["face_count"] = max(0, self.persons[old_pid]["face_count"] - 1)
            self.persons[old_pid]["updated_at"] = datetime.utcnow().isoformat()
            
        self.faces[face_id]["person_id"] = person_id
        
        if person_id in self.persons:
            self.persons[person_id]["face_count"] += 1
            self.persons[person_id]["updated_at"] = datetime.utcnow().isoformat()
            
        self.save_db()

    def merge_persons(self, source_person_id: int, target_person_id: int):
        """Move all faces from source to target, then delete source."""
        if source_person_id not in self.persons or target_person_id not in self.persons:
            return
            
        # Move faces
        source_faces_count = 0
        for fid, face in self.faces.items():
            if face.get("person_id") == source_person_id:
                face["person_id"] = target_person_id
                source_faces_count += 1
        
        # Update counts
        self.persons[target_person_id]["face_count"] += source_faces_count
        self.persons[target_person_id]["updated_at"] = datetime.utcnow().isoformat()
        
        # Delete source
        del self.persons[source_person_id]
        self.save_db()
        
    def get_stats(self) -> Dict[str, int]:
        unassigned_count = sum(1 for face in self.faces.values() if face.get("person_id") is None)
        return {
            "total_persons": len(self.persons),
            "total_faces": len(self.faces),
            "unassigned_faces": unassigned_count
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
    
def merge_persons(session=None, source_person_id=None, target_person_id=None):
    db_instance.merge_persons(source_person_id, target_person_id)

def delete_person(person_id):
    db_instance.delete_person(person_id)
    
def get_stats():
    return db_instance.get_stats()

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
