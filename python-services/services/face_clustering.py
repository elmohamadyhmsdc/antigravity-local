"""
Face Clustering Service using DBSCAN
Clusters face embeddings and merges embeddings
"""

import numpy as np
from sklearn.cluster import DBSCAN
from typing import List, Dict, Any
import os
import uuid
from pathlib import Path


class FaceClusteringService:
    def __init__(self):
        """Initialize clustering service"""
        self.embeddings_dir = Path("embeddings")
        self.embeddings_dir.mkdir(exist_ok=True)
        
        # DBSCAN parameters - tuned for accurate clustering
        # eps: Maximum distance between samples in the same cluster (cosine distance)
        # Lower eps = stricter clustering (fewer faces per cluster, more clusters)
        # Higher eps = looser clustering (more faces per cluster, fewer clusters)
        # Using 0.28 for extremely strict clustering - only group faces that are VERY similar
        # This prevents dissimilar faces from being grouped together, especially when many faces are in one image
        # The issue with DBSCAN is "chaining" - if A is similar to B, and B is similar to C,
        # then A, B, C all end up in one cluster even if A and C are not similar
        # Lower eps reduces this chaining effect
        self.eps = 0.28  # Extremely strict - only cluster faces that are VERY similar
        self.min_samples = 2  # Minimum number of samples in a cluster
        
        # Matching threshold - stricter than clustering to avoid false matches
        # Cosine distance threshold for matching faces to existing persons
        # Lower = stricter (fewer false matches, but might miss some true matches)
        # 0.3 = very strict, 0.35 = strict, 0.4 = moderate, 0.45 = loose
        # Using 0.3 for very strict matching to prevent false positives
        self.match_threshold = 0.3  # Very strict - only match if truly similar

    async def cluster_faces(self, embedding_paths: List[str]) -> Dict[int, List[int]]:
        """
        Cluster face embeddings using DBSCAN.
        
        Args:
            embedding_paths: List of paths to embedding files (.npy)
            
        Returns:
            Dictionary mapping cluster_id to list of face indices.
            Cluster ID -1 indicates noise/outliers.
        """
        print(f"[DEBUG] cluster_faces called with {len(embedding_paths)} embedding paths")
        
        if not embedding_paths:
            print("[WARNING] No embedding paths provided")
            return {}

        # Load embeddings
        embeddings = []
        valid_indices = []
        
        print(f"[DEBUG] Loading embeddings from {len(embedding_paths)} paths...")
        for idx, path in enumerate(embedding_paths):
            if os.path.exists(path):
                try:
                    embedding = np.load(path)
                    embeddings.append(embedding)
                    valid_indices.append(idx)
                    print(f"[DEBUG] Loaded embedding {idx}: {path}, shape: {embedding.shape}")
                except Exception as e:
                    print(f"[ERROR] Error loading embedding {path}: {e}")
                    import traceback
                    traceback.print_exc()
                    continue
            else:
                print(f"[WARNING] Embedding file does not exist: {path}")

        print(f"[DEBUG] Successfully loaded {len(embeddings)} embeddings out of {len(embedding_paths)} paths")
        print(f"[DEBUG] Valid indices: {valid_indices}")

        if len(embeddings) < 2:
            print(f"[WARNING] Insufficient embeddings ({len(embeddings)}) for clustering. Need at least 2.")
            return {}

        # Convert to numpy array
        embeddings_array = np.array(embeddings)
        print(f"[DEBUG] Embeddings array shape: {embeddings_array.shape}")

        # Apply DBSCAN clustering
        print(f"[DEBUG] Applying DBSCAN clustering with eps={self.eps}, min_samples={self.min_samples}, metric='cosine'")
        clustering = DBSCAN(eps=self.eps, min_samples=self.min_samples, metric='cosine')
        cluster_labels = clustering.fit_predict(embeddings_array)
        
        print(f"[DEBUG] Clustering completed. Cluster labels: {cluster_labels}")
        print(f"[DEBUG] Unique cluster IDs: {set(cluster_labels)}")
        print(f"[DEBUG] Number of noise points (label=-1): {sum(1 for label in cluster_labels if label == -1)}")

        # Group indices by cluster
        clusters: Dict[int, List[int]] = {}
        for i, label in enumerate(cluster_labels):
            original_idx = valid_indices[i]
            if label not in clusters:
                clusters[label] = []
            clusters[label].append(original_idx)
            print(f"[DEBUG] Face index {original_idx} (embedding {i}) assigned to cluster {label}")

        print(f"[DEBUG] Clusters before filtering: {clusters}")

        # Filter clusters: remove noise clusters and very small clusters
        # Noise cluster (-1) with single sample should be removed
        # Also remove clusters with only 1 face (they should be noise or unmatched)
        clusters_to_remove = []
        for cluster_id, face_indices in clusters.items():
            if len(face_indices) == 1:
                clusters_to_remove.append(cluster_id)
                print(f"[DEBUG] Removing cluster {cluster_id} with only 1 face (indices: {face_indices})")
        
        for cluster_id in clusters_to_remove:
            del clusters[cluster_id]

        print(f"[DEBUG] Final clusters: {clusters}")
        print(f"[DEBUG] Returning {len(clusters)} clusters")

        return clusters

    async def merge_embeddings(
        self,
        embedding_paths: List[str],
        quality_scores: List[float]
    ) -> str:
        """
        Merge multiple face embeddings using weighted average based on quality scores.
        
        Args:
            embedding_paths: List of paths to embedding files
            quality_scores: List of quality scores (0.0 to 1.0) corresponding to each embedding
            
        Returns:
            Path to the merged embedding file
        """
        if len(embedding_paths) != len(quality_scores):
            raise ValueError("embedding_paths and quality_scores must have the same length")

        if not embedding_paths:
            raise ValueError("At least one embedding path is required")

        # Load embeddings
        embeddings = []
        weights = []
        
        for path, quality in zip(embedding_paths, quality_scores):
            if os.path.exists(path):
                try:
                    embedding = np.load(path)
                    embeddings.append(embedding)
                    weights.append(quality)
                except Exception as e:
                    print(f"Error loading embedding {path}: {e}")
                    continue

        if not embeddings:
            raise ValueError("No valid embeddings found")

        # Normalize weights
        weights = np.array(weights)
        weights = weights / weights.sum() if weights.sum() > 0 else np.ones(len(weights)) / len(weights)

        # Weighted average
        embeddings_array = np.array(embeddings)
        merged_embedding = np.average(embeddings_array, axis=0, weights=weights)
        
        # Normalize the merged embedding
        merged_embedding = merged_embedding / np.linalg.norm(merged_embedding)

        # Save merged embedding
        merged_filename = f"merged_{uuid.uuid4()}.npy"
        merged_path = self.embeddings_dir / merged_filename
        np.save(str(merged_path), merged_embedding)

        return str(merged_path.absolute())

    async def find_best_match(
        self,
        face_embedding_path: str,
        person_embeddings: Dict[int, List[str]]
    ) -> tuple[int, float, float]:
        """
        Find the best matching person for a face embedding by comparing against ALL faces of each person.
        
        Args:
            face_embedding_path: Path to the face embedding file (.npy)
            person_embeddings: Dictionary mapping person_id to list of embedding file paths for that person
            
        Returns:
            Tuple of (person_id, best_distance, best_distance) where:
            - person_id: ID of the best matching person, or -1 if no match found within threshold
            - best_distance: The cosine distance to the best match
            Uses stricter threshold (0.35) than clustering (0.4) to avoid false matches.
        """
        print(f"[DEBUG] find_best_match called with face: {face_embedding_path}, {len(person_embeddings)} persons")
        
        if not os.path.exists(face_embedding_path):
            print(f"[WARNING] Face embedding file does not exist: {face_embedding_path}")
            return (-1, float('inf'), float('inf'))
        
        if not person_embeddings:
            print("[DEBUG] No person embeddings provided")
            return (-1, float('inf'), float('inf'))
        
        # Load face embedding
        try:
            face_embedding = np.load(face_embedding_path)
            face_embedding = face_embedding / np.linalg.norm(face_embedding)  # Normalize
        except Exception as e:
            print(f"[ERROR] Error loading face embedding {face_embedding_path}: {e}")
            return (-1, float('inf'), float('inf'))
        
        best_person_id = -1
        best_distance = float('inf')
        best_person_distances = {}  # Track best distance per person for logging
        
        # Compare against ALL faces of EACH person, find the best match per person
        for person_id, embedding_paths in person_embeddings.items():
            person_best_distance = float('inf')
            person_matches = 0
            
            # Compare against all faces of this person
            for embedding_path in embedding_paths:
                if not os.path.exists(embedding_path):
                    print(f"[WARNING] Person {person_id} embedding file does not exist: {embedding_path}")
                    continue
                
                try:
                    person_embedding = np.load(embedding_path)
                    person_embedding = person_embedding / np.linalg.norm(person_embedding)  # Normalize
                    
                    # Calculate cosine distance (1 - cosine similarity)
                    cosine_similarity = np.dot(face_embedding, person_embedding)
                    cosine_distance = 1.0 - cosine_similarity
                    
                    person_matches += 1
                    if cosine_distance < person_best_distance:
                        person_best_distance = cosine_distance
                    
                    print(f"[DEBUG] Person {person_id}, face {person_matches}: distance={cosine_distance:.4f}, similarity={cosine_similarity:.4f}")
                except Exception as e:
                    print(f"[ERROR] Error loading person {person_id} embedding {embedding_path}: {e}")
                    continue
            
            # Track best distance for this person
            if person_best_distance < float('inf'):
                best_person_distances[person_id] = person_best_distance
                print(f"[DEBUG] Person {person_id} best distance: {person_best_distance:.4f} (from {person_matches} faces)")
                
                # Update global best if this person is better
                if person_best_distance < best_distance:
                    best_distance = person_best_distance
                    best_person_id = person_id
        
        # Log all person distances for debugging
        print(f"[DEBUG] All person distances: {sorted(best_person_distances.items(), key=lambda x: x[1])}")
        
        # Check if best match is within threshold (use stricter threshold for matching)
        if best_person_id >= 0 and best_distance <= self.match_threshold:
            print(f"[DEBUG] ✓ Best match found: person {best_person_id} with distance {best_distance:.4f} (match threshold: {self.match_threshold}, clustering threshold: {self.eps})")
            return (best_person_id, best_distance, best_distance)
        else:
            print(f"[DEBUG] ✗ No match found within threshold. Best distance: {best_distance:.4f} to person {best_person_id} (match threshold: {self.match_threshold}, clustering threshold: {self.eps})")
            return (-1, best_distance, best_distance)

    async def find_matching_group(
        self,
        new_embedding_path: str,
        existing_group_embeddings: List[Dict[str, Any]],
        similarity_threshold: float = 0.7
    ) -> Dict[str, Any]:
        """
        Find matching group for a new face embedding by comparing against existing group average embeddings.
        
        Args:
            new_embedding_path: Path to the new face embedding file (.npy)
            existing_group_embeddings: List of dicts with 'group_id' and 'embedding_path'
            similarity_threshold: Cosine similarity threshold (0.0 to 1.0)
            
        Returns:
            Dictionary with 'matched_group_id' and 'similarity_score', or None if no match
        """
        print(f"[DEBUG] find_matching_group called with new embedding: {new_embedding_path}, {len(existing_group_embeddings)} groups")
        
        if not os.path.exists(new_embedding_path):
            print(f"[WARNING] New embedding file does not exist: {new_embedding_path}")
            return {"matched_group_id": None, "similarity_score": 0.0}
        
        if not existing_group_embeddings:
            print("[DEBUG] No existing group embeddings provided")
            return {"matched_group_id": None, "similarity_score": 0.0}
        
        # Load new face embedding
        try:
            new_embedding = np.load(new_embedding_path)
            new_embedding = new_embedding / np.linalg.norm(new_embedding)  # Normalize
        except Exception as e:
            print(f"[ERROR] Error loading new embedding {new_embedding_path}: {e}")
            return {"matched_group_id": None, "similarity_score": 0.0}
        
        best_group_id = None
        best_similarity = -1.0
        
        # Compare against all group average embeddings
        for group_info in existing_group_embeddings:
            group_id = group_info.get("group_id")
            embedding_path = group_info.get("embedding_path")
            
            if not embedding_path or not os.path.exists(embedding_path):
                print(f"[WARNING] Group {group_id} embedding file does not exist: {embedding_path}")
                continue
            
            try:
                group_embedding = np.load(embedding_path)
                group_embedding = group_embedding / np.linalg.norm(group_embedding)  # Normalize
                
                # Calculate cosine similarity
                cosine_similarity = np.dot(new_embedding, group_embedding)
                
                print(f"[DEBUG] Group {group_id}: similarity={cosine_similarity:.4f}")
                
                if cosine_similarity > best_similarity:
                    best_similarity = cosine_similarity
                    best_group_id = group_id
            except Exception as e:
                print(f"[ERROR] Error loading group {group_id} embedding {embedding_path}: {e}")
                continue
        
        # Check if best match is within threshold
        if best_group_id is not None and best_similarity >= similarity_threshold:
            print(f"[DEBUG] ✓ Best match found: group {best_group_id} with similarity {best_similarity:.4f} (threshold: {similarity_threshold})")
            return {"matched_group_id": best_group_id, "similarity_score": float(best_similarity)}
        else:
            print(f"[DEBUG] ✗ No match found within threshold. Best similarity: {best_similarity:.4f} to group {best_group_id} (threshold: {similarity_threshold})")
            return {"matched_group_id": None, "similarity_score": float(best_similarity)}

    async def compare_similarity(
        self,
        embedding_path1: str,
        embedding_path2: str
    ) -> Dict[str, Any]:
        """
        Compare similarity between two face embeddings using multiple metrics.
        
        Args:
            embedding_path1: Path to first embedding file (.npy)
            embedding_path2: Path to second embedding file (.npy)
            
        Returns:
            Dictionary with similarity metrics and recommendation
        """
        print(f"[DEBUG] compare_similarity called with embeddings: {embedding_path1}, {embedding_path2}")
        
        if not os.path.exists(embedding_path1):
            raise ValueError(f"Embedding file 1 does not exist: {embedding_path1}")
        if not os.path.exists(embedding_path2):
            raise ValueError(f"Embedding file 2 does not exist: {embedding_path2}")
        
        # Load embeddings
        try:
            embedding1 = np.load(embedding_path1)
            embedding2 = np.load(embedding_path2)
            
            # Normalize
            embedding1 = embedding1 / np.linalg.norm(embedding1)
            embedding2 = embedding2 / np.linalg.norm(embedding2)
        except Exception as e:
            raise ValueError(f"Error loading embeddings: {e}")
        
        # Calculate various distance metrics
        # Euclidean distance
        euclidean_distance = float(np.linalg.norm(embedding1 - embedding2))
        
        # Cosine similarity and distance
        cosine_similarity = float(np.dot(embedding1, embedding2))
        cosine_distance = 1.0 - cosine_similarity
        
        # Manhattan distance (L1 norm)
        manhattan_distance = float(np.sum(np.abs(embedding1 - embedding2)))
        
        # Chebyshev distance (L∞ norm)
        chebyshev_distance = float(np.max(np.abs(embedding1 - embedding2)))
        
        # Recommendation based on cosine similarity (most relevant for face embeddings)
        if cosine_similarity >= 0.7:
            recommendation = "likely_same_person"
        elif cosine_similarity >= 0.5:
            recommendation = "possibly_same_person"
        else:
            recommendation = "likely_different_person"
        
        result = {
            "euclidean_distance": euclidean_distance,
            "cosine_similarity": cosine_similarity,
            "cosine_distance": cosine_distance,
            "manhattan_distance": manhattan_distance,
            "chebyshev_distance": chebyshev_distance,
            "recommendation": recommendation
        }
        
        print(f"[DEBUG] Similarity comparison: cosine_similarity={cosine_similarity:.4f}, recommendation={recommendation}")
        
        return result

