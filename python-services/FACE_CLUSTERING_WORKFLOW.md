# Face Clustering Workflow - Detailed Documentation

## Overview

The Face Clustering workflow is a multi-stage process that automatically groups similar faces together using machine learning algorithms. This system uses **DBSCAN (Density-Based Spatial Clustering of Applications with Noise)** to identify faces belonging to the same person across multiple media files.

## Architecture Overview

The workflow spans three layers:
1. **Backend (C# .NET Core)**: Orchestrates the clustering job, manages database operations
2. **Python Service (FastAPI)**: Performs the actual clustering algorithm using scikit-learn
3. **Database (SQL Server)**: Stores face embeddings, detected faces, and person assignments

## Complete Workflow Steps

### Step 1: Job Trigger

**Location**: `backend/FaceGallery.Api/Controllers/PersonsController.cs`

The clustering process can be triggered in two ways:
- **Manual Trigger**: `POST /api/persons/cluster` endpoint
- **Automatic Trigger**: Scheduled via Hangfire background job system

```csharp
// Manual trigger example
var jobId = Hangfire.BackgroundJob.Enqueue<FaceClusteringJob>(job => job.ProcessAsync());
```

### Step 2: Query Unassigned Faces

**Location**: `backend/FaceGallery.Api/Jobs/FaceClusteringJob.cs` (lines 30-42)

The job queries the database for all faces that:
- Have `PersonId == null` (not yet assigned to a person)
- Have `QualityScore >= 0.6` (meet minimum quality threshold)

**SQL Query Equivalent**:
```sql
SELECT * FROM DetectedFaces 
WHERE PersonId IS NULL AND QualityScore >= 0.6
```

**Why Quality Threshold?**
- Low-quality face detections (blurry, side profile, occluded) produce unreliable embeddings
- Filtering ensures only high-confidence faces are clustered
- Reduces noise and improves clustering accuracy

### Step 3: Validate Embedding Files

**Location**: `backend/FaceGallery.Api/Jobs/FaceClusteringJob.cs` (lines 58-85)

For each detected face, the system:
1. Checks if the embedding file path exists in the filesystem
2. Separates faces into two lists:
   - **Valid faces**: Embedding file exists and is accessible
   - **Missing faces**: Embedding file is missing (logged as warning)

**Why This Step?**
- Embeddings are stored as `.npy` files on disk (not in database)
- File system issues or deleted files would cause clustering to fail
- Early validation prevents processing errors later

**Minimum Requirement**: At least 2 valid faces are needed for clustering (DBSCAN requires multiple samples)

### Step 4: Call Python Clustering Service

**Location**: `backend/FaceGallery.Api/Services/FaceRecognitionService.cs` (lines 71-125)

The C# backend makes an HTTP POST request to the Python FastAPI service:

**Request**:
```json
POST http://localhost:8000/api/faces/cluster
{
  "embedding_paths": [
    "D:/embeddings/face_123.npy",
    "D:/embeddings/face_456.npy",
    ...
  ]
}
```

**Response**:
```json
{
  "clusters": {
    "0": [0, 1, 2],      // Cluster 0 contains faces at indices 0, 1, 2
    "1": [3, 4],         // Cluster 1 contains faces at indices 3, 4
    "2": [5, 6, 7, 8]    // Cluster 2 contains faces at indices 5, 6, 7, 8
  }
}
```

**Note**: Cluster ID `-1` indicates noise/outliers (faces that don't belong to any cluster)

### Step 5: Load Face Embeddings

**Location**: `python-services/services/face_clustering.py` (lines 41-62)

The Python service:
1. Iterates through each embedding file path
2. Loads the `.npy` file using NumPy: `np.load(path)`
3. Validates the embedding shape (typically 512-dimensional vector for InsightFace)
4. Tracks valid indices for mapping back to original face IDs

**Embedding Format**:
- **File Type**: NumPy binary format (`.npy`)
- **Shape**: 1D array of floats, typically `(512,)` for InsightFace buffalo_l model
- **Content**: Normalized feature vector representing facial characteristics

**Error Handling**:
- Missing files are logged and skipped
- Corrupted files trigger exceptions with full stack traces
- Only successfully loaded embeddings proceed to clustering

### Step 6: Convert to NumPy Array

**Location**: `python-services/services/face_clustering.py` (line 69)

All loaded embeddings are combined into a 2D NumPy array:
- **Shape**: `(num_faces, embedding_dimension)`
- **Example**: `(100, 512)` for 100 faces with 512-dimensional embeddings
- **Purpose**: Required format for scikit-learn DBSCAN algorithm

### Step 7: Apply DBSCAN Clustering

**Location**: `python-services/services/face_clustering.py` (lines 72-75)

**DBSCAN Algorithm**:
```python
clustering = DBSCAN(eps=0.4, min_samples=2, metric='cosine')
cluster_labels = clustering.fit_predict(embeddings_array)
```

**Parameters Explained**:

1. **`eps=0.4`** (Epsilon):
   - Maximum distance between two samples for them to be considered neighbors
   - Using **cosine distance** metric
   - Value of 0.4 means faces with cosine similarity > 0.6 are considered similar
   - **Lower values** = stricter clustering (fewer faces per cluster)
   - **Higher values** = looser clustering (more faces per cluster)

2. **`min_samples=2`**:
   - Minimum number of faces required to form a cluster
   - Faces that don't meet this threshold are marked as noise (cluster ID = -1)
   - Prevents single-face clusters (which may be false positives)

3. **`metric='cosine'`**:
   - Uses cosine similarity/distance for comparing embeddings
   - Better for high-dimensional vectors than Euclidean distance
   - Cosine distance = 1 - cosine_similarity
   - Range: 0 (identical) to 2 (opposite)

**How DBSCAN Works**:
1. For each face embedding, find all neighbors within `eps` distance
2. If a face has at least `min_samples` neighbors, it becomes a **core point**
3. Core points and their neighbors form a **cluster**
4. Faces that don't meet the criteria are marked as **noise** (cluster ID = -1)

**Output**: Array of cluster labels, one per face
- Example: `[0, 0, 0, 1, 1, -1, 2, 2, 2]`
  - Faces 0, 1, 2 → Cluster 0
  - Faces 3, 4 → Cluster 1
  - Face 5 → Noise (no cluster)
  - Faces 6, 7, 8 → Cluster 2

### Step 8: Group Indices by Cluster

**Location**: `python-services/services/face_clustering.py` (lines 81-88)

The cluster labels are converted into a dictionary mapping:
- **Key**: Cluster ID (integer, -1 for noise)
- **Value**: List of face indices belonging to that cluster

**Example Output**:
```python
{
  0: [0, 1, 2],      # Cluster 0 has 3 faces
  1: [3, 4],         # Cluster 1 has 2 faces
  -1: [5],           # Noise: 1 face doesn't belong to any cluster
  2: [6, 7, 8]       # Cluster 2 has 3 faces
}
```

**Index Mapping**:
- Indices correspond to the position in the `embedding_paths` input array
- Face at index 0 = first embedding path
- Face at index 1 = second embedding path, etc.

### Step 9: Filter Noise Clusters

**Location**: `python-services/services/face_clustering.py` (lines 92-95)

Single-face noise clusters are removed:
- If cluster ID `-1` exists and contains only one face, it's removed
- **Rationale**: Single faces that don't cluster with others are likely:
  - Low quality detections
  - Faces of people who only appear once
  - False positive face detections

**Result**: Only meaningful clusters (2+ faces) are returned to the backend

### Step 10: Map Clusters to Persons

**Location**: `backend/FaceGallery.Api/Jobs/FaceClusteringJob.cs` (lines 109-189)

For each cluster returned by the Python service:

#### 10a. Check for Existing Person Assignment
- Iterates through faces in the cluster
- If any face already has a `PersonId`, that person is used
- **Why?**: Handles edge cases where faces were manually assigned or re-clustered

#### 10b. Create New Person (if needed)
- If no existing person found, creates a new `Person` record
- Person is initially unnamed (can be named later by user)
- Saves to database immediately to get `PersonId`

#### 10c. Assign Faces to Person
- Updates each face in the cluster:
  - Sets `PersonId` to the person's ID
  - Sets `ClusterId` to the cluster ID (for tracking)
- Only assigns faces that don't already have a `PersonId`

**Index Mapping Challenge**:
- Python service returns indices based on **valid faces only** (0, 1, 2, ...)
- Backend must map these back to original `DetectedFace` database records
- Uses the `validFaces` list created in Step 3 to map indices correctly

### Step 11: Save Results to Database

**Location**: `backend/FaceGallery.Api/Jobs/FaceClusteringJob.cs` (lines 191-193)

All face assignments are saved to the database in a single transaction:
- Updates `DetectedFaces` table with `PersonId` and `ClusterId`
- Ensures data consistency (all or nothing)
- Logs summary statistics

## Data Flow Diagram

```
┌─────────────────┐
│  User/System    │
│  Triggers Job   │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  FaceClusteringJob (C# Backend)     │
│  1. Query unassigned faces          │
│  2. Validate embedding files        │
└────────┬────────────────────────────┘
         │
         │ HTTP POST /api/faces/cluster
         │ { embedding_paths: [...] }
         ▼
┌─────────────────────────────────────┐
│  FaceClusteringService (Python)     │
│  3. Load embeddings from .npy files │
│  4. Convert to NumPy array          │
│  5. Apply DBSCAN clustering         │
│  6. Group indices by cluster        │
│  7. Filter noise                    │
└────────┬────────────────────────────┘
         │
         │ HTTP Response
         │ { clusters: { 0: [0,1,2], ... } }
         ▼
┌─────────────────────────────────────┐
│  FaceClusteringJob (C# Backend)     │
│  8. Map clusters to Persons         │
│  9. Create/update Person records    │
│ 10. Assign faces to persons         │
│ 11. Save to database                │
└─────────────────────────────────────┘
```

## Key Data Structures

### Face Embedding File
- **Format**: NumPy binary (`.npy`)
- **Location**: File system (path stored in `DetectedFaces.EmbeddingFilePath`)
- **Content**: 512-dimensional float array (normalized)
- **Example Path**: `D:/embeddings/face_12345.npy`

### Cluster Result Format
```python
{
  0: [0, 1, 2],      # Cluster 0: faces at indices 0, 1, 2
  1: [3, 4],         # Cluster 1: faces at indices 3, 4
  2: [5, 6, 7]       # Cluster 2: faces at indices 5, 6, 7
}
```

### Database Tables Involved

**DetectedFaces**:
- `FaceId` (PK)
- `PersonId` (FK, nullable) - **Updated during clustering**
- `ClusterId` (nullable) - **Set during clustering**
- `EmbeddingFilePath` (string) - Path to `.npy` file
- `QualityScore` (float) - Must be >= 0.6

**Persons**:
- `PersonId` (PK)
- `Name` (nullable) - Can be set by user later
- `CreatedAt`, `UpdatedAt` (timestamps)

## Configuration Parameters

### DBSCAN Parameters
**Location**: `python-services/services/face_clustering.py` (lines 20-22)

| Parameter | Current Value | Description | Tuning Guide |
|-----------|--------------|-------------|--------------|
| `eps` | 0.4 | Maximum distance for clustering | **Lower** (0.3): Stricter, fewer false positives<br>**Higher** (0.5): Looser, more faces per cluster |
| `min_samples` | 2 | Minimum faces per cluster | **Lower** (2): Allow small clusters<br>**Higher** (3): Require more evidence |
| `metric` | 'cosine' | Distance metric | Usually keep as 'cosine' for embeddings |

### Quality Threshold
**Location**: `backend/FaceGallery.Api/Jobs/FaceClusteringJob.cs` (line 33)

| Parameter | Current Value | Description |
|-----------|--------------|-------------|
| `QualityScore` | >= 0.6 | Minimum face quality to include |

## Performance Considerations

### Scalability
- **Small datasets** (< 100 faces): Processes in seconds
- **Medium datasets** (100-1000 faces): Processes in 10-30 seconds
- **Large datasets** (1000+ faces): May take minutes; consider batching

### Optimization Strategies
1. **Batch Processing**: Process faces in batches of 500-1000
2. **Incremental Clustering**: Only cluster newly detected faces
3. **GPU Acceleration**: Use GPU-enabled NumPy/ONNX for faster embedding operations
4. **Caching**: Cache loaded embeddings in memory for repeated clustering

### Memory Usage
- Each embedding: ~2KB (512 floats × 4 bytes)
- 1000 faces: ~2MB of embeddings
- DBSCAN algorithm: O(n²) memory complexity for distance matrix
- **Recommendation**: Process in batches for > 5000 faces

## Error Handling

### Common Issues and Solutions

1. **Missing Embedding Files**
   - **Symptom**: Warnings in logs about missing files
   - **Cause**: Files deleted or path incorrect
   - **Solution**: Re-run face detection to regenerate embeddings

2. **No Clusters Returned**
   - **Symptom**: All faces marked as noise
   - **Cause**: `eps` too low or faces are too dissimilar
   - **Solution**: Increase `eps` parameter or check embedding quality

3. **Too Many Small Clusters**
   - **Symptom**: Many clusters with only 2-3 faces
   - **Cause**: `eps` too low or `min_samples` too low
   - **Solution**: Increase `eps` or `min_samples`

4. **Faces Merged Incorrectly**
   - **Symptom**: Different people in same cluster
   - **Cause**: `eps` too high
   - **Solution**: Decrease `eps` parameter

5. **Index Mapping Errors**
   - **Symptom**: Wrong faces assigned to persons
   - **Cause**: Mismatch between Python indices and database faces
   - **Solution**: Verify `validFaces` mapping logic

## Testing and Validation

### Manual Testing
1. Trigger clustering: `POST /api/persons/cluster`
2. Check logs for cluster assignments
3. Query database: `SELECT * FROM DetectedFaces WHERE PersonId IS NOT NULL`
4. Verify faces in same cluster belong to same person

### Validation Metrics
- **Cluster Purity**: Percentage of faces correctly grouped
- **Coverage**: Percentage of faces assigned to clusters (vs. noise)
- **Cluster Count**: Number of unique persons identified

## Related Workflows

### Face Detection Workflow
- Runs before clustering
- Extracts face embeddings and saves to `.npy` files
- Populates `DetectedFaces` table

### Face Merging Workflow
- Can be used after clustering
- Merges multiple embeddings from same person into single representative embedding
- Uses weighted average based on quality scores

### Person Management
- Users can manually assign faces to persons
- Users can name persons
- Users can merge persons (combine clusters)

## Future Enhancements

1. **Incremental Clustering**: Only process new faces, merge with existing clusters
2. **Adaptive Parameters**: Automatically tune `eps` based on dataset characteristics
3. **Hierarchical Clustering**: Support for sub-clusters (e.g., different ages of same person)
4. **Confidence Scores**: Assign confidence to cluster assignments
5. **Visual Validation**: UI to review and correct cluster assignments

## References

- **DBSCAN Algorithm**: [scikit-learn Documentation](https://scikit-learn.org/stable/modules/generated/sklearn.cluster.DBSCAN.html)
- **InsightFace**: [GitHub Repository](https://github.com/deepinsight/insightface)
- **Cosine Similarity**: Mathematical foundation for face embedding comparison

