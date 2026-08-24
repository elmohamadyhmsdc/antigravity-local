"""
Face Detection Service using InsightFace
Detects faces, extracts embeddings, and assesses quality
"""

import insightface
import cv2
import numpy as np
from typing import List, Dict
import os
import uuid
from pathlib import Path


class FaceDetectionService:
    def __init__(self):
        """Initialize InsightFace model"""
        # Try GPU first, fallback to CPU if not available
        # For Advanced Optimus/MUX switch systems, ensure GPU is activated
        try:
            import onnxruntime as ort
            
            # Get available providers
            available_providers = ort.get_available_providers()
            print(f"[INFO] Available ONNX Runtime providers: {available_providers}")
            
            if 'CUDAExecutionProvider' in available_providers:
                # Configure CUDA provider options for better Optimus compatibility
                providers = [
                    ('CUDAExecutionProvider', {
                        'device_id': 0,
                        'arena_extend_strategy': 'kNextPowerOfTwo',
                        'gpu_mem_limit': 2 * 1024 * 1024 * 1024,  # 2GB limit
                        'cudnn_conv_algo_search': 'EXHAUSTIVE',
                        'do_copy_in_default_stream': True,
                    }),
                    'CPUExecutionProvider'
                ]
                print("[INFO] Using GPU (CUDA) for face detection")
                print("[INFO] CUDA provider configured for Optimus/MUX switch compatibility")
            else:
                providers = ['CPUExecutionProvider']
                print("[INFO] GPU not available, using CPU for face detection")
                print("[WARNING] If you have an NVIDIA GPU, ensure:")
                print("  1. onnxruntime-gpu is installed (not onnxruntime)")
                print("  2. NVIDIA drivers are up to date")
                print("  3. NVIDIA Control Panel is configured to use GPU for Python")
        except Exception as e:
            print(f"[WARNING] Could not check GPU availability: {e}. Using CPU.")
            providers = ['CPUExecutionProvider']
        
        self.model = insightface.app.FaceAnalysis(
            name='buffalo_l',  # or 'buffalo_s' for smaller model
            providers=providers
        )
        self.model.prepare(ctx_id=0, det_size=(640, 640))
        self.embeddings_dir = Path("embeddings")
        self.embeddings_dir.mkdir(exist_ok=True)

    async def detect_faces(self, image_path: str) -> List[Dict]:
        """
        Detect faces in an image and extract embeddings.
        
        Args:
            image_path: Path to the image file
            
        Returns:
            List of face detection results with:
            - bbox_x, bbox_y, bbox_width, bbox_height
            - quality_score (0.0 to 1.0)
            - confidence_score
            - embedding_file_path
            - landmarks (optional)
        """
        print(f"[DEBUG] detect_faces called with path: {image_path}")
        
        if not os.path.exists(image_path):
            print(f"[ERROR] Image file does not exist: {image_path}")
            raise FileNotFoundError(f"Image not found: {image_path}")

        # Read image
        print(f"[DEBUG] Reading image with OpenCV...")
        img = cv2.imread(image_path)
        if img is None:
            print(f"[ERROR] OpenCV could not read image: {image_path}")
            raise ValueError(f"Could not read image: {image_path}")

        print(f"[DEBUG] Image loaded successfully. Shape: {img.shape}")
        
        # Detect faces
        print(f"[DEBUG] Running InsightFace face detection...")
        faces = self.model.get(img)
        print(f"[DEBUG] InsightFace detected {len(faces)} faces")

        results = []
        for face in faces:
            # Extract bounding box
            bbox = face.bbox.astype(int)
            x, y, x2, y2 = bbox
            width = x2 - x
            height = y2 - y

            # Calculate quality score (based on detection confidence and face size)
            confidence = face.det_score
            face_area = width * height
            img_area = img.shape[0] * img.shape[1]
            size_ratio = face_area / img_area if img_area > 0 else 0
            
            # Quality score combines confidence and size (normalized)
            quality_score = min(confidence * (1 + size_ratio * 2), 1.0)

            # Only process faces with quality >= 0.6
            if quality_score >= 0.6:
                # Extract embedding
                embedding = face.normed_embedding
                
                # Save embedding to file
                embedding_filename = f"{uuid.uuid4()}.npy"
                embedding_path = self.embeddings_dir / embedding_filename
                np.save(str(embedding_path), embedding)
                
                absolute_path = str(embedding_path.absolute())
                print(f"[DEBUG] Saved embedding to: {absolute_path}")
                print(f"[DEBUG] Embedding file exists: {os.path.exists(absolute_path)}")

                # Extract landmarks if available
                landmarks = None
                if hasattr(face, 'landmark_2d_106') and face.landmark_2d_106 is not None:
                    landmarks = face.landmark_2d_106.tolist()

                results.append({
                    "bbox_x": float(x),
                    "bbox_y": float(y),
                    "bbox_width": float(width),
                    "bbox_height": float(height),
                    "quality_score": float(quality_score),
                    "confidence_score": float(confidence),
                    "embedding_file_path": absolute_path,
                    "landmarks": landmarks
                })

        return results

    def assess_face_quality(
        self,
        bbox: tuple,
        landmarks: np.ndarray = None,
        image_shape: tuple = None
    ) -> float:
        """
        Assess face quality based on bounding box, landmarks, and image properties.
        
        Args:
            bbox: (x, y, width, height) bounding box
            landmarks: Face landmarks (optional)
            image_shape: (height, width) of the image
            
        Returns:
            Quality score from 0.0 to 1.0
        """
        x, y, width, height = bbox
        
        # Check face size
        if image_shape:
            img_height, img_width = image_shape
            face_area = width * height
            img_area = img_width * img_height
            size_ratio = face_area / img_area if img_area > 0 else 0
            
            # Penalize very small faces
            if size_ratio < 0.01:
                return 0.0
        else:
            size_ratio = 1.0

        # Check aspect ratio (faces should be roughly square)
        aspect_ratio = width / height if height > 0 else 0
        aspect_score = 1.0 - abs(1.0 - aspect_ratio) * 0.5  # Penalize non-square faces

        # Basic quality score
        quality = min(size_ratio * 2, 1.0) * aspect_score

        return max(0.0, min(1.0, quality))

