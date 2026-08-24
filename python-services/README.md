# Face Recognition Python Service

FastAPI service for face detection, clustering, and face swapping using InsightFace and DeepFaceLab.

## Setup

1. Install Python 3.9+ (recommended: 3.10 or 3.11)

2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

3. Download InsightFace models (buffalo_l):
   - Models will be automatically downloaded on first run
   - Or download manually from: https://github.com/deepinsight/insightface

4. Configure DeepFaceLab (optional, for face swapping):
   - Set `DEEPFACELAB_PATH` environment variable to DeepFaceLab installation path
   - Set `DEEPFACELAB_WORKSPACE` environment variable to workspace directory

## Running the Service

```bash
python main.py
```

Or with uvicorn:
```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

The service will be available at `http://localhost:8000`

## API Endpoints

### Health Check
- `GET /` - Service info
- `GET /health` - Health check

### Face Detection
- `POST /api/faces/detect` - Detect faces in an image
  ```json
  {
    "image_path": "/path/to/image.jpg"
  }
  ```

### Face Clustering
- `POST /api/faces/cluster` - Cluster face embeddings
  ```json
  {
    "embedding_paths": ["/path/to/embedding1.npy", "/path/to/embedding2.npy"]
  }
  ```

### Face Merging
- `POST /api/faces/merge` - Merge face embeddings
  ```json
  {
    "embedding_paths": ["/path/to/embedding1.npy"],
    "quality_scores": [0.9]
  }
  ```

### Face Swap
- `POST /api/faceswap/process` - Process face swap
  ```json
  {
    "source_face_id": 1,
    "source_image_path": "/path/to/source.jpg",
    "target_image_path": "/path/to/target.jpg",
    "bbox": {
      "x": 100,
      "y": 100,
      "width": 200,
      "height": 200
    }
  }
  ```

## Configuration

### InsightFace Model
- Default model: `buffalo_l` (larger, more accurate)
- Alternative: `buffalo_s` (smaller, faster)
- Change in `services/face_detection.py`

### DBSCAN Clustering
- `eps`: 0.4 (maximum distance between samples in cluster)
- `min_samples`: 2 (minimum samples per cluster)
- Adjust in `services/face_clustering.py`

### Quality Threshold
- Minimum quality score: 0.6
- Faces below this threshold are filtered out
- Adjust in `services/face_detection.py`

## Directory Structure

- `main.py` - FastAPI application
- `services/` - Service modules
  - `face_detection.py` - Face detection and embedding extraction
  - `face_clustering.py` - DBSCAN clustering and embedding merging
  - `face_swap.py` - DeepFaceLab integration for face swapping
- `embeddings/` - Stored face embeddings (auto-created)
- `results/` - Face swap results (auto-created)

## GPU Support

For GPU acceleration with InsightFace:
1. Install CUDA and cuDNN
2. Install onnxruntime-gpu: `pip install onnxruntime-gpu`
3. Update `face_detection.py` to use `'CUDAExecutionProvider'`

## DeepFaceLab Integration

The face swap service supports DeepFaceLab integration:
1. Install DeepFaceLab separately
2. Set environment variables:
   - `DEEPFACELAB_PATH` - Path to DeepFaceLab installation
   - `DEEPFACELAB_WORKSPACE` - Workspace directory for processing
3. Implement actual CLI calls in `services/face_swap.py`

## Notes

- Face embeddings are stored as `.npy` files
- Quality scores range from 0.0 to 1.0
- Only faces with quality >= 0.6 are processed
- DBSCAN uses cosine distance for clustering
- Face swap requires DeepFaceLab or alternative library

