"""
Antigravity Local - Face Mining Engine
Generator-pattern face extraction from videos with pgvector deduplication
"""

import os
import sys
from pathlib import Path
from typing import Generator, Dict, Any, Optional, List, Tuple
from dataclasses import dataclass
from datetime import datetime

import cv2
import numpy as np
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Force NVIDIA GPU activation for Advanced Optimus/MUX switch systems
os.environ['NvOptimusEnablement'] = '1'
os.environ['CUDA_VISIBLE_DEVICES'] = '0'


def setup_cuda_path():
    """Add CUDA runtime DLL paths to PATH before loading onnxruntime"""
    current_path = os.environ.get('PATH', '')
    paths_to_add = []
    
    # Check for CUDA Toolkit in common locations
    for version in ['12.6', '12.5', '12.4', '12.3', '12.2', '12.1', '12.0', '11.8']:
        cuda_bin = Path(fr"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v{version}\bin")
        if cuda_bin.exists():
            paths_to_add.append(str(cuda_bin))
            print(f"[INFO] Found CUDA Toolkit v{version}")
            break
    
    if paths_to_add:
        new_path = ';'.join(paths_to_add) + ';' + current_path
        os.environ['PATH'] = new_path


# Setup CUDA paths before importing InsightFace
setup_cuda_path()

import insightface
from database import find_duplicate, add_face, init_db


@dataclass
class FaceData:
    """Container for extracted face data"""
    embedding: np.ndarray
    bbox: Tuple[float, float, float, float]  # x, y, width, height
    quality_score: float
    confidence_score: float
    landmarks: Optional[np.ndarray]
    source_path: str
    frame_number: Optional[int]
    face_image: np.ndarray


class FaceMiner:
    """
    Face mining engine using generator pattern.
    Extracts faces from videos/images with deduplication via pgvector.
    """
    
    def __init__(
        self,
        frame_interval: float = None,
        quality_threshold: float = None,
        duplicate_threshold: float = None,
        output_dir: str = None
    ):
        """
        Initialize FaceMiner with InsightFace model.
        
        Args:
            frame_interval: Seconds between frame extractions (default from .env or 1.0)
            quality_threshold: Minimum quality score for face (default from .env or 0.6)
            duplicate_threshold: Max cosine distance for duplicate detection (default from .env or 0.05)
            output_dir: Directory to save extracted face images
        """
        # Load settings from environment or use defaults
        self.frame_interval = frame_interval or float(os.getenv("FRAME_INTERVAL", "1.0"))
        self.quality_threshold = quality_threshold or float(os.getenv("QUALITY_THRESHOLD", "0.6"))
        self.duplicate_threshold = duplicate_threshold or float(os.getenv("DUPLICATE_THRESHOLD", "0.05"))
        self.output_dir = Path(output_dir or os.getenv("OUTPUT_DIR", "./extracted_faces"))
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # Initialize InsightFace model
        self._init_model()
        
        # Statistics
        self.stats = {
            "videos_processed": 0,
            "frames_processed": 0,
            "faces_detected": 0,
            "faces_saved": 0,
            "duplicates_skipped": 0
        }
    
    def _init_model(self):
        """Initialize InsightFace model with GPU support"""
        try:
            import onnxruntime as ort
            available_providers = ort.get_available_providers()
            print(f"[INFO] Available ONNX Runtime providers: {available_providers}")
            
            if 'CUDAExecutionProvider' in available_providers:
                providers = [
                    ('CUDAExecutionProvider', {
                        'device_id': 0,
                        'arena_extend_strategy': 'kNextPowerOfTwo',
                        'gpu_mem_limit': 2 * 1024 * 1024 * 1024,  # 2GB
                        'cudnn_conv_algo_search': 'EXHAUSTIVE',
                        'do_copy_in_default_stream': True,
                    }),
                    'CPUExecutionProvider'
                ]
                print("[INFO] Using GPU (CUDA) for face detection")
            else:
                providers = ['CPUExecutionProvider']
                print("[WARNING] GPU not available, using CPU")
        except Exception as e:
            print(f"[WARNING] Could not check GPU: {e}. Using CPU.")
            providers = ['CPUExecutionProvider']
        
        self.model = insightface.app.FaceAnalysis(
            name='buffalo_l',
            providers=providers
        )
        self.model.prepare(ctx_id=0, det_size=(640, 640))
        print("[INFO] InsightFace Buffalo_L model loaded")
    
    def extract_frames(self, video_path: str) -> Generator[Tuple[int, np.ndarray], None, None]:
        """
        Generator that yields frames from a video at specified interval.
        
        Args:
            video_path: Path to video file
            
        Yields:
            Tuple of (frame_number, frame_image)
        """
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            print(f"[ERROR] Could not open video: {video_path}")
            return
        
        fps = cap.get(cv2.CAP_PROP_FPS)
        frame_skip = int(fps * self.frame_interval) if fps > 0 else 30
        
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        print(f"[INFO] Video: {video_path}")
        print(f"[INFO] FPS: {fps}, Total frames: {total_frames}, Extracting every {frame_skip} frames")
        
        frame_number = 0
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            
            if frame_number % frame_skip == 0:
                yield (frame_number, frame)
            
            frame_number += 1
        
        cap.release()
    
    def detect_faces(self, frame: np.ndarray) -> List[FaceData]:
        """
        Detect faces in a frame using InsightFace.
        
        Args:
            frame: BGR image array
            
        Returns:
            List of FaceData objects for detected faces
        """
        faces = self.model.get(frame)
        results = []
        
        for face in faces:
            bbox = face.bbox.astype(int)
            x, y, x2, y2 = bbox
            width = x2 - x
            height = y2 - y
            
            # Calculate quality score
            confidence = face.det_score
            face_area = width * height
            img_area = frame.shape[0] * frame.shape[1]
            size_ratio = face_area / img_area if img_area > 0 else 0
            quality_score = min(confidence * (1 + size_ratio * 2), 1.0)
            
            # Filter by quality threshold
            if quality_score >= self.quality_threshold:
                # Extract face image with padding
                pad = int(max(width, height) * 0.2)
                y1 = max(0, y - pad)
                y2_pad = min(frame.shape[0], y2 + pad)
                x1 = max(0, x - pad)
                x2_pad = min(frame.shape[1], x2 + pad)
                face_image = frame[y1:y2_pad, x1:x2_pad].copy()
                
                # Get landmarks if available
                landmarks = None
                if hasattr(face, 'landmark_2d_106') and face.landmark_2d_106 is not None:
                    landmarks = face.landmark_2d_106
                
                results.append(FaceData(
                    embedding=face.normed_embedding,
                    bbox=(float(x), float(y), float(width), float(height)),
                    quality_score=quality_score,
                    confidence_score=float(confidence),
                    landmarks=landmarks,
                    source_path="",  # Will be set by caller
                    frame_number=None,  # Will be set by caller
                    face_image=face_image
                ))
        
        return results
    
    def is_duplicate(self, embedding: np.ndarray) -> Optional[Tuple[int, float]]:
        """
        Check if embedding is a duplicate using pgvector cosine distance.
        
        Args:
            embedding: 512-d face embedding
            
        Returns:
            Tuple of (existing_face_id, distance) if duplicate, None otherwise
        """
        return find_duplicate(
            embedding=embedding.tolist(),
            threshold=self.duplicate_threshold
        )
    
    def save_face(self, face_data: FaceData, person_id: Optional[int] = None) -> int:
        """
        Save face to database and disk.
        
        Args:
            face_data: FaceData object
            person_id: Optional person ID to assign
            
        Returns:
            ID of the saved face record
        """
        # Generate unique filename
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        filename = f"face_{timestamp}.jpg"
        image_path = self.output_dir / filename
        
        # Save face image
        cv2.imwrite(str(image_path), face_data.face_image)
        
        # Save to database - convert numpy types to Python native types
        bbox_dict = {
            'x': float(face_data.bbox[0]),
            'y': float(face_data.bbox[1]),
            'w': float(face_data.bbox[2]),
            'h': float(face_data.bbox[3])
        }
        
        face_id = add_face(
            embedding=face_data.embedding.tolist(),
            source_path=face_data.source_path,
            person_id=person_id,
            bbox=bbox_dict,
            quality_score=float(face_data.quality_score),
            image_path=str(image_path)
        )
        
        return face_id
    
    def mine_video(self, video_path: str) -> Generator[Dict[str, Any], None, None]:
        """
        Generator that mines faces from a single video.
        
        Args:
            video_path: Path to video file
            
        Yields:
            Dictionary with face info: {face_id, quality, is_new, frame_number}
        """
        video_path = str(video_path)
        print(f"\n[INFO] Mining video: {video_path}")
        
        for frame_number, frame in self.extract_frames(video_path):
            self.stats["frames_processed"] += 1
            
            faces = self.detect_faces(frame)
            self.stats["faces_detected"] += len(faces)
            
            for face_data in faces:
                face_data.source_path = video_path
                face_data.frame_number = frame_number
                
                # Check for duplicates
                duplicate = self.is_duplicate(face_data.embedding)
                
                if duplicate:
                    self.stats["duplicates_skipped"] += 1
                    yield {
                        "face_id": duplicate[0],
                        "quality": face_data.quality_score,
                        "is_new": False,
                        "frame_number": frame_number,
                        "distance": duplicate[1]
                    }
                else:
                    # Save new face
                    face_id = self.save_face(face_data)
                    self.stats["faces_saved"] += 1
                    yield {
                        "face_id": face_id,
                        "quality": face_data.quality_score,
                        "is_new": True,
                        "frame_number": frame_number,
                        "image_path": str(self.output_dir / f"face_{datetime.now().strftime('%Y%m%d_%H%M%S_%f')}.jpg")
                    }
        
        self.stats["videos_processed"] += 1
    
    def mine_videos(self, folder_path: str) -> Generator[Dict[str, Any], None, None]:
        """
        Generator that mines faces from all videos in a folder.
        
        Args:
            folder_path: Path to folder containing videos
            
        Yields:
            Dictionary with face info for each detected face
        """
        folder = Path(folder_path)
        video_extensions = {'.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm'}
        
        videos = [f for f in folder.iterdir() if f.suffix.lower() in video_extensions]
        print(f"[INFO] Found {len(videos)} videos in {folder_path}")
        
        for video_path in videos:
            yield from self.mine_video(str(video_path))
        
        self.print_stats()
    
    def mine_image(self, image_path: str) -> Generator[Dict[str, Any], None, None]:
        """
        Generator that mines faces from a single image.
        
        Args:
            image_path: Path to image file
            
        Yields:
            Dictionary with face info
        """
        image_path = str(image_path)
        print(f"[INFO] Mining image: {image_path}")
        
        frame = cv2.imread(image_path)
        if frame is None:
            print(f"[ERROR] Could not read image: {image_path}")
            return
        
        faces = self.detect_faces(frame)
        self.stats["faces_detected"] += len(faces)
        
        for face_data in faces:
            face_data.source_path = image_path
            face_data.frame_number = None
            
            # Check for duplicates
            duplicate = self.is_duplicate(face_data.embedding)
            
            if duplicate:
                self.stats["duplicates_skipped"] += 1
                yield {
                    "face_id": duplicate[0],
                    "quality": face_data.quality_score,
                    "is_new": False,
                    "distance": duplicate[1]
                }
            else:
                face_id = self.save_face(face_data)
                self.stats["faces_saved"] += 1
                yield {
                    "face_id": face_id,
                    "quality": face_data.quality_score,
                    "is_new": True
                }
    
    def print_stats(self):
        """Print mining statistics"""
        print("\n" + "=" * 50)
        print("FACE MINING STATISTICS")
        print("=" * 50)
        print(f"Videos processed:    {self.stats['videos_processed']}")
        print(f"Frames processed:    {self.stats['frames_processed']}")
        print(f"Faces detected:      {self.stats['faces_detected']}")
        print(f"Faces saved (new):   {self.stats['faces_saved']}")
        print(f"Duplicates skipped:  {self.stats['duplicates_skipped']}")
        print("=" * 50)


if __name__ == "__main__":
    # Example usage
    # init_db is already imported
    
    print("Initializing database...")
    init_db()
    
    print("\nInitializing FaceMiner...")
    miner = FaceMiner()
    
    # Mine from default video folder
    video_folder = os.getenv("VIDEO_FOLDER", "./videos")
    if Path(video_folder).exists():
        print(f"\nMining videos from: {video_folder}")
        for face_info in miner.mine_videos(video_folder):
            status = "NEW" if face_info["is_new"] else "DUP"
            print(f"  [{status}] Face #{face_info['face_id']}, Quality: {face_info['quality']:.2f}")
    else:
        print(f"[WARNING] Video folder not found: {video_folder}")
        print("Set VIDEO_FOLDER in .env or create the directory")
