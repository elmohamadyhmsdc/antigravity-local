"""
Face Gallery - Python Face Recognition Service
FastAPI service for face detection, clustering, and face swapping
"""

import os
import sys
from pathlib import Path

# Force NVIDIA GPU activation for Advanced Optimus/MUX switch systems
# This must be done BEFORE importing any CUDA-dependent libraries
os.environ['NvOptimusEnablement'] = '1'
os.environ['CUDA_VISIBLE_DEVICES'] = '0'  # Use first GPU

# Add CUDA DLL paths to PATH for onnxruntime-gpu
# Error 126 means missing dependencies - we need CUDA runtime DLLs in PATH
def setup_cuda_path():
    """Add CUDA runtime DLL paths to PATH before loading onnxruntime"""
    current_path = os.environ.get('PATH', '')
    paths_to_add = []
    
    # 1. Add NVIDIA driver CUDA DLLs (usually in System32)
    nvidia_driver_paths = [
        r"C:\Windows\System32",
        r"C:\Program Files\NVIDIA Corporation\NVSMI",
    ]
    
    # Also check for cuDNN in common locations
    # cuDNN is required by onnxruntime-gpu but installed separately
    cudnn_paths = []
    for version in ['12.6', '12.5', '12.4', '12.3', '12.2', '12.1', '12.0']:
        cudnn_bin = Path(fr"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v{version}\bin")
        if cudnn_bin.exists():
            # Check if cuDNN DLL exists
            if list(cudnn_bin.glob("cudnn*.dll")):
                cudnn_paths.append(str(cudnn_bin))
                print(f"[INFO] Found cuDNN in CUDA v{version} bin directory")
                break
    
    # 2. Add CUDA Toolkit paths if installed
    # Check both Program Files locations and all versions including 13.x
    cuda_toolkit_paths = []
    base_paths = [
        Path(r"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA"),
        Path(r"C:\Program Files (x86)\NVIDIA GPU Computing Toolkit\CUDA"),
    ]
    
    # Check versions (prioritize 12.x for onnxruntime-gpu 1.23.2, then 11.x, then 13.x)
    # onnxruntime-gpu 1.23.2 requires CUDA 12.x DLLs (cublasLt64_12.dll, etc.)
    versions = ['12.6', '12.5', '12.4', '12.3', '12.2', '12.1', '12.0', '11.8', '11.7', '11.6', '13.1', '13.0']
    
    for base_path in base_paths:
        if base_path.exists():
            for version in versions:
                # Check both bin and lib/x64 (CUDA 13.x might use lib/x64)
                bin_path = base_path / f"v{version}" / "bin"
                lib_path = base_path / f"v{version}" / "lib" / "x64"
                
                # Prefer bin, but also add lib/x64 if it exists
                if bin_path.exists():
                    cuda_toolkit_paths.append(str(bin_path))
                    print(f"[INFO] Found CUDA Toolkit v{version} bin: {bin_path}")
                if lib_path.exists():
                    cuda_toolkit_paths.append(str(lib_path))
                    print(f"[INFO] Found CUDA Toolkit v{version} lib/x64: {lib_path}")
                
                if cuda_toolkit_paths:
                    break  # Use first found version
            if cuda_toolkit_paths:
                break
    
    # 3. Add onnxruntime-gpu's bundled CUDA DLLs (if any)
    try:
        import site
        site_packages = site.getsitepackages()
        for site_pkg in site_packages:
            ort_cuda_path = Path(site_pkg) / "onnxruntime" / "capi"
            if ort_cuda_path.exists():
                paths_to_add.append(str(ort_cuda_path))
    except:
        pass
    
    # Combine all paths (cuDNN paths are already in cuda_toolkit_paths if copied correctly)
    all_paths = nvidia_driver_paths + cuda_toolkit_paths + cudnn_paths + paths_to_add
    
    # Prepend to PATH (must be first for DLL loading)
    if all_paths:
        new_path = ';'.join(all_paths) + ';' + current_path
        os.environ['PATH'] = new_path
        print(f"[INFO] Added {len(all_paths)} CUDA DLL paths to PATH")
        if cuda_toolkit_paths:
            print(f"[INFO] Found CUDA Toolkit: {cuda_toolkit_paths[0]}")
        else:
            print("[WARNING] CUDA Toolkit not found in standard location.")
            print("[WARNING] onnxruntime-gpu requires CUDA Toolkit DLLs.")
            print("[WARNING] Run 'python check_cuda_dlls.py' for diagnosis.")
    else:
        print("[ERROR] No CUDA paths found. GPU will not work!")
        print("[ERROR] onnxruntime-gpu requires CUDA Toolkit to be installed.")
        print("[ERROR] Download from: https://developer.nvidia.com/cuda-downloads")
        print("[ERROR] Or use CPU version: pip install onnxruntime==1.16.3")

# Setup CUDA paths before any imports
setup_cuda_path()

from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Dict, Optional, Any
import uvicorn

# Try to initialize CUDA context to force GPU activation
# Note: We check providers but don't create a session yet (that happens in FaceDetectionService)
try:
    import pycuda.driver as cuda
    cuda.init()
    print("[INFO] CUDA initialized via pycuda - GPU should be activated")
except ImportError:
    # pycuda not installed, that's okay
    pass
except Exception as e:
    print(f"[WARNING] pycuda initialization error: {e}")

# Check if CUDA provider is available (but don't load it yet)
try:
    import onnxruntime as ort
    providers = ort.get_available_providers()
    if 'CUDAExecutionProvider' in providers:
        print(f"[INFO] CUDA provider detected in available providers: {providers}")
    else:
        print(f"[WARNING] CUDA provider not in available providers: {providers}")
except Exception as e:
    print(f"[WARNING] Could not check ONNX Runtime providers: {e}")

from services.face_detection import FaceDetectionService
from services.face_clustering import FaceClusteringService
from services.face_swap import FaceSwapService

app = FastAPI(title="Face Recognition Service", version="1.0.0")

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize services
face_detection_service = FaceDetectionService()
face_clustering_service = FaceClusteringService()
face_swap_service = FaceSwapService()


class FaceDetectionRequest(BaseModel):
    image_path: str


class FaceDetectionResponse(BaseModel):
    faces: List[Dict]


class ClusteringRequest(BaseModel):
    embedding_paths: List[str]


class ClusteringResponse(BaseModel):
    clusters: Dict[int, List[int]]


class MergeRequest(BaseModel):
    embedding_paths: List[str]
    quality_scores: List[float]


class MergeResponse(BaseModel):
    merged_embedding_path: str


class FaceSwapRequest(BaseModel):
    source_face_id: int
    source_image_path: str
    target_image_path: str
    bbox: Dict[str, float]


class FaceSwapResponse(BaseModel):
    result_path: str
    success: bool
    message: Optional[str] = None


class FindMatchRequest(BaseModel):
    face_embedding_path: str
    person_embeddings: Dict[int, List[str]]  # person_id -> list of embedding paths


class FindMatchResponse(BaseModel):
    person_id: int  # -1 if no match found
    distance: float = -1.0  # Cosine distance to the best match (only if match found)
    best_distance: float = -1.0  # Best distance found (even if no match)


class FindMatchingGroupRequest(BaseModel):
    new_embedding_path: str
    existing_group_embeddings: List[Dict[str, Any]]  # List of dicts with 'group_id' and 'embedding_path'
    similarity_threshold: float = 0.7


class FindMatchingGroupResponse(BaseModel):
    matched_group_id: Optional[int] = None
    similarity_score: float = 0.0


class CompareSimilarityRequest(BaseModel):
    embedding_path1: str
    embedding_path2: str


class CompareSimilarityResponse(BaseModel):
    euclidean_distance: float
    cosine_similarity: float
    cosine_distance: float
    manhattan_distance: float
    chebyshev_distance: float
    recommendation: str


@app.get("/")
async def root():
    return {"message": "Face Recognition Service API", "version": "1.0.0"}


@app.get("/health")
async def health():
    return {"status": "healthy"}


@app.post("/api/faces/detect", response_model=FaceDetectionResponse)
async def detect_faces(request: FaceDetectionRequest):
    """
    Detect faces in an image and extract embeddings.
    Returns bounding boxes, quality scores, and embedding file paths.
    """
    try:
        print(f"[DEBUG] Face detection request received for: {request.image_path}")
        
        if not os.path.exists(request.image_path):
            print(f"[ERROR] Image not found: {request.image_path}")
            raise HTTPException(status_code=404, detail=f"Image not found: {request.image_path}")

        print(f"[DEBUG] Calling face_detection_service.detect_faces...")
        faces = await face_detection_service.detect_faces(request.image_path)
        print(f"[DEBUG] Face detection returned {len(faces)} faces")
        
        for i, face in enumerate(faces):
            print(f"[DEBUG] Face {i+1}: Quality={face.get('quality_score', 0):.3f}, Confidence={face.get('confidence_score', 0):.3f}")
        
        return FaceDetectionResponse(faces=faces)
    except Exception as e:
        print(f"[ERROR] Exception in detect_faces: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Error detecting faces: {str(e)}")


@app.post("/api/faces/cluster", response_model=ClusteringResponse)
async def cluster_faces(request: ClusteringRequest):
    """
    Cluster face embeddings using DBSCAN.
    Returns a dictionary mapping cluster_id to list of face indices.
    """
    try:
        print(f"[DEBUG] Clustering request received with {len(request.embedding_paths)} embedding paths")
        print(f"[DEBUG] Embedding paths: {request.embedding_paths[:5]}...")  # Log first 5
        
        clusters = await face_clustering_service.cluster_faces(request.embedding_paths)
        
        print(f"[DEBUG] Clustering completed. Returning {len(clusters)} clusters")
        for cluster_id, face_indices in clusters.items():
            print(f"[DEBUG] Cluster {cluster_id}: {len(face_indices)} faces (indices: {face_indices})")
        
        return ClusteringResponse(clusters=clusters)
    except Exception as e:
        print(f"[ERROR] Exception in cluster_faces: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Error clustering faces: {str(e)}")


@app.post("/api/faces/merge", response_model=MergeResponse)
async def merge_faces(request: MergeRequest):
    """
    Merge multiple face embeddings using weighted average based on quality scores.
    Returns path to merged embedding file.
    """
    try:
        if len(request.embedding_paths) != len(request.quality_scores):
            raise HTTPException(
                status_code=400,
                detail="embedding_paths and quality_scores must have the same length"
            )

        merged_path = await face_clustering_service.merge_embeddings(
            request.embedding_paths,
            request.quality_scores
        )
        
        return MergeResponse(merged_embedding_path=merged_path)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error merging faces: {str(e)}")


@app.post("/api/faces/find-match", response_model=FindMatchResponse)
async def find_best_match(request: FindMatchRequest):
    """
    Find the best matching person for a face embedding by comparing against ALL faces of each person.
    Returns the person_id of the best matching person, or -1 if no match found within threshold.
    """
    try:
        person_id, distance, best_distance = await face_clustering_service.find_best_match(
            request.face_embedding_path,
            request.person_embeddings
        )
        
        return FindMatchResponse(
            person_id=person_id,
            distance=distance if person_id >= 0 else -1.0,
            best_distance=best_distance
        )
    except Exception as e:
        print(f"[ERROR] Exception in find_best_match: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Error finding best match: {str(e)}")


@app.post("/api/faces/find-matching-group", response_model=FindMatchingGroupResponse)
async def find_matching_group(request: FindMatchingGroupRequest):
    """
    Find matching group for a new face embedding by comparing against existing group average embeddings.
    Returns the group_id of the best matching group, or None if no match found within threshold.
    """
    try:
        result = await face_clustering_service.find_matching_group(
            request.new_embedding_path,
            request.existing_group_embeddings,
            request.similarity_threshold
        )
        
        return FindMatchingGroupResponse(
            matched_group_id=result.get("matched_group_id"),
            similarity_score=result.get("similarity_score", 0.0)
        )
    except Exception as e:
        print(f"[ERROR] Exception in find_matching_group: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Error finding matching group: {str(e)}")


@app.post("/api/faces/compare-similarity", response_model=CompareSimilarityResponse)
async def compare_similarity(request: CompareSimilarityRequest):
    """
    Compare similarity between two face embeddings using multiple metrics.
    Returns various distance metrics and a recommendation.
    """
    try:
        result = await face_clustering_service.compare_similarity(
            request.embedding_path1,
            request.embedding_path2
        )
        
        return CompareSimilarityResponse(
            euclidean_distance=result["euclidean_distance"],
            cosine_similarity=result["cosine_similarity"],
            cosine_distance=result["cosine_distance"],
            manhattan_distance=result["manhattan_distance"],
            chebyshev_distance=result["chebyshev_distance"],
            recommendation=result["recommendation"]
        )
    except Exception as e:
        print(f"[ERROR] Exception in compare_similarity: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Error comparing similarity: {str(e)}")


@app.post("/api/faceswap/process", response_model=FaceSwapResponse)
async def process_face_swap(request: FaceSwapRequest):
    """
    Process face swap using DeepFaceLab.
    Swaps the source face onto the target image.
    """
    try:
        if not os.path.exists(request.source_image_path):
            raise HTTPException(
                status_code=404,
                detail=f"Source image not found: {request.source_image_path}"
            )
        
        if not os.path.exists(request.target_image_path):
            raise HTTPException(
                status_code=404,
                detail=f"Target image not found: {request.target_image_path}"
            )

        result_path = await face_swap_service.swap_faces(
            source_image_path=request.source_image_path,
            target_image_path=request.target_image_path,
            bbox=request.bbox
        )

        return FaceSwapResponse(
            result_path=result_path,
            success=True,
            message="Face swap completed successfully"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error processing face swap: {str(e)}")


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)

