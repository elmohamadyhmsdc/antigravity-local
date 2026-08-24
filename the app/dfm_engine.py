"""
Antigravity Local - DeepFaceLab DFM Model Engine
Loads trained SAEHD/AMP models exported as .dfm for high-quality face swapping

DFM files are ONNX models exported from DeepFaceLab containing:
- Encoder + Decoder neural networks trained on specific face pairs
- Input: Aligned face image (resolution x resolution x 3)
- Output: Swapped face + masks
"""

import os
import sys
from pathlib import Path
from typing import Optional, List, Tuple, Dict
from dataclasses import dataclass
from datetime import datetime

import cv2
import numpy as np

try:
    import onnxruntime as ort
    ONNX_AVAILABLE = True
except ImportError:
    ONNX_AVAILABLE = False
    print("[WARNING] onnxruntime not available. DFM models will not work.")


@dataclass
class DFMResult:
    """Result of a DFM inference"""
    success: bool
    swapped_face: Optional[np.ndarray] = None  # BGR, resolution x resolution x 3
    face_mask: Optional[np.ndarray] = None     # Grayscale mask for destination
    celeb_mask: Optional[np.ndarray] = None    # Grayscale mask for source/celeb
    message: str = ""


@dataclass  
class DFMModelInfo:
    """Information about a DFM model"""
    path: str
    name: str
    resolution: int
    model_type: str  # 'SAEHD', 'AMP', etc.
    created: Optional[datetime] = None
    file_size_mb: float = 0.0


class DFMEngine:
    """
    DeepFaceLab DFM Model Engine.
    Uses ONNX runtime to load exported .dfm models for face swap inference.
    
    DFM models are trained in DeepFaceLab and exported using:
    - `6) export SAEHD as dfm.bat`
    - `6) export AMP as dfm.bat`
    
    The exported model transforms destination faces into source/celebrity faces.
    """
    
    # Default search paths for DFM models
    DEFAULT_SEARCH_PATHS = [
        Path(__file__).parent / "models",
        Path(__file__).parent / "dfm_models",
    ]
    
    def __init__(self, model_path: str = None):
        """
        Initialize the DFM engine.
        
        Args:
            model_path: Optional path to a specific .dfm model.
                       If None, no model is loaded initially.
        """
        if not ONNX_AVAILABLE:
            raise RuntimeError("onnxruntime is required for DFM models. Install with: pip install onnxruntime-gpu")
        
        self.model_path: Optional[Path] = None
        self.session: Optional[ort.InferenceSession] = None
        self.resolution: int = 128
        self.model_info: Optional[DFMModelInfo] = None
        
        # ONNX execution providers (prefer GPU)
        self.providers = ['CUDAExecutionProvider', 'CPUExecutionProvider']
        
        if model_path:
            self.load_model(model_path)
    
    def load_model(self, model_path: str) -> bool:
        """
        Load a DFM model from disk.
        
        Args:
            model_path: Path to the .dfm file
            
        Returns:
            True if loaded successfully, False otherwise
        """
        path = Path(model_path)
        
        if not path.exists():
            print(f"[DFM] Model not found: {path}")
            return False
        
        if not path.suffix.lower() in ['.dfm', '.onnx']:
            print(f"[DFM] Invalid model format: {path.suffix}")
            return False
        
        try:
            # Close existing session if any
            if self.session:
                self.session = None
            
            # Load with ONNX runtime
            print(f"[DFM] Loading model: {path.name}")
            sess_options = ort.SessionOptions()
            sess_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
            
            self.session = ort.InferenceSession(
                str(path), 
                sess_options=sess_options,
                providers=self.providers
            )
            
            # Get model metadata
            input_info = self.session.get_inputs()[0]
            input_shape = input_info.shape
            
            # Detect resolution from input shape
            # DFM models typically have input shape: [batch, height, width, channels] or [batch, channels, height, width]
            if len(input_shape) == 4:
                # Try to find the resolution dimension
                if input_shape[1] == input_shape[2]:  # NHWC with H=W
                    self.resolution = input_shape[1] if isinstance(input_shape[1], int) else 128
                elif input_shape[2] == input_shape[3]:  # NCHW with H=W
                    self.resolution = input_shape[2] if isinstance(input_shape[2], int) else 128
                else:
                    self.resolution = 128  # Default
            else:
                self.resolution = 128
            
            # Store model info
            self.model_path = path
            self.model_info = DFMModelInfo(
                path=str(path),
                name=path.stem,
                resolution=self.resolution,
                model_type=self._detect_model_type(path),
                file_size_mb=path.stat().st_size / (1024 * 1024),
                created=datetime.fromtimestamp(path.stat().st_mtime)
            )
            
            # Check which provider is actually being used
            actual_provider = self.session.get_providers()[0] if self.session.get_providers() else "Unknown"
            
            print(f"[DFM] ✓ Model loaded: {path.name}")
            print(f"[DFM]   Resolution: {self.resolution}x{self.resolution}")
            print(f"[DFM]   Provider: {actual_provider}")
            print(f"[DFM]   Size: {self.model_info.file_size_mb:.1f} MB")
            
            return True
            
        except Exception as e:
            print(f"[DFM] Error loading model: {e}")
            self.session = None
            self.model_path = None
            return False
    
    def _detect_model_type(self, path: Path) -> str:
        """Detect model type from path or metadata."""
        name = path.name.lower()
        if 'saehd' in name:
            return 'SAEHD'
        elif 'amp' in name:
            return 'AMP'
        elif 'quick96' in name:
            return 'Quick96'
        elif 'rtm' in name:
            return 'RTM'
        return 'Unknown'
    
    def is_loaded(self) -> bool:
        """Check if a model is loaded."""
        return self.session is not None
    
    def swap_face(
        self, 
        aligned_face: np.ndarray,
    ) -> DFMResult:
        """
        Perform face swap using the loaded DFM model.
        
        Args:
            aligned_face: Face image aligned to DFL standard.
                         Must be (resolution x resolution x 3) in BGR format.
                         
        Returns:
            DFMResult with swapped face and masks
        """
        if not self.is_loaded():
            return DFMResult(success=False, message="No DFM model loaded")
        
        try:
            # Validate input
            if aligned_face is None:
                return DFMResult(success=False, message="Input face is None")
            
            # Resize to model resolution if needed
            h, w = aligned_face.shape[:2]
            if h != self.resolution or w != self.resolution:
                aligned_face = cv2.resize(
                    aligned_face, 
                    (self.resolution, self.resolution),
                    interpolation=cv2.INTER_LANCZOS4
                )
            
            # Preprocess: normalize to 0-1 float
            face_input = aligned_face.astype(np.float32) / 255.0
            
            # Add batch dimension: (H, W, C) -> (1, H, W, C)
            face_input = face_input[np.newaxis, ...]
            
            # Run inference
            # DFM model inputs/outputs:
            # - Input: 'in_face:0' (1, H, W, 3)
            # - Outputs: 
            #   - 'out_face_mask:0' (destination face mask)
            #   - 'out_celeb_face:0' (swapped face)
            #   - 'out_celeb_face_mask:0' (source/celeb face mask)
            
            input_name = self.session.get_inputs()[0].name
            outputs = self.session.run(None, {input_name: face_input})
            
            # Parse outputs based on count
            if len(outputs) >= 3:
                out_face_mask = outputs[0][0]      # Destination mask
                out_celeb_face = outputs[1][0]     # Swapped face
                out_celeb_mask = outputs[2][0]     # Source mask
            elif len(outputs) == 2:
                out_celeb_face = outputs[0][0]
                out_face_mask = outputs[1][0]
                out_celeb_mask = out_face_mask
            else:
                out_celeb_face = outputs[0][0]
                out_face_mask = None
                out_celeb_mask = None
            
            # Post-process: convert back to uint8 BGR
            swapped_face = np.clip(out_celeb_face * 255, 0, 255).astype(np.uint8)
            
            face_mask = None
            celeb_mask = None
            
            if out_face_mask is not None:
                # Handle different mask formats (H,W,1) or (H,W)
                if len(out_face_mask.shape) == 3:
                    out_face_mask = out_face_mask[..., 0]
                face_mask = np.clip(out_face_mask * 255, 0, 255).astype(np.uint8)
            
            if out_celeb_mask is not None:
                if len(out_celeb_mask.shape) == 3:
                    out_celeb_mask = out_celeb_mask[..., 0]
                celeb_mask = np.clip(out_celeb_mask * 255, 0, 255).astype(np.uint8)
            
            return DFMResult(
                success=True,
                swapped_face=swapped_face,
                face_mask=face_mask,
                celeb_mask=celeb_mask,
                message="DFM swap successful"
            )
            
        except Exception as e:
            import traceback
            traceback.print_exc()
            return DFMResult(
                success=False,
                message=f"DFM inference error: {str(e)}"
            )
    
    def swap_and_blend(
        self,
        target_image: np.ndarray,
        aligned_face: np.ndarray,
        face_matrix: np.ndarray,
        blend_amount: float = 1.0
    ) -> np.ndarray:
        """
        Swap face and blend back into the original image.
        
        Args:
            target_image: Original full image (BGR)
            aligned_face: Face aligned/cropped from target (resolution x resolution x 3)
            face_matrix: 2x3 affine transformation matrix used for alignment
            blend_amount: How much to blend (0.0 = original, 1.0 = full swap)
            
        Returns:
            Result image with swapped face blended in
        """
        result = self.swap_face(aligned_face)
        
        if not result.success:
            print(f"[DFM] Swap failed: {result.message}")
            return target_image
        
        # Get the swapped face and mask
        swapped = result.swapped_face
        mask = result.celeb_mask if result.celeb_mask is not None else result.face_mask
        
        if mask is None:
            # Create a simple elliptical mask if none provided
            mask = np.zeros((self.resolution, self.resolution), dtype=np.uint8)
            cv2.ellipse(mask, 
                       (self.resolution // 2, self.resolution // 2),
                       (self.resolution // 2 - 10, self.resolution // 2 - 5),
                       0, 0, 360, 255, -1)
            mask = cv2.GaussianBlur(mask, (15, 15), 0)
        
        # Create inverse transformation to map back to original image
        h, w = target_image.shape[:2]
        inv_matrix = cv2.invertAffineTransform(face_matrix)
        
        # Warp swapped face back to original image space
        swapped_warped = cv2.warpAffine(
            swapped, inv_matrix, (w, h),
            borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0)
        )
        
        # Warp mask back to original image space
        mask_warped = cv2.warpAffine(
            mask, inv_matrix, (w, h),
            borderMode=cv2.BORDER_CONSTANT, borderValue=0
        )
        
        # Apply blend amount
        mask_float = (mask_warped.astype(np.float32) / 255.0) * blend_amount
        mask_float = mask_float[..., np.newaxis]  # Add channel dimension
        
        # Blend
        result_image = target_image.astype(np.float32) * (1 - mask_float) + \
                       swapped_warped.astype(np.float32) * mask_float
        
        return np.clip(result_image, 0, 255).astype(np.uint8)
    
    @staticmethod
    def list_available_models(search_paths: List[str] = None) -> List[DFMModelInfo]:
        """
        Find all .dfm files in the given paths.
        
        Args:
            search_paths: List of directories to search. 
                         If None, uses default search paths.
                         
        Returns:
            List of DFMModelInfo objects for found models
        """
        if search_paths is None:
            search_paths = [str(p) for p in DFMEngine.DEFAULT_SEARCH_PATHS]
        
        # Add DeepFaceLab workspace path if it exists
        dfl_workspace = Path("d:/AndroidScan/gallary/DeepFaceLab_NVIDIA_RTX3000_series/workspace")
        if dfl_workspace.exists():
            search_paths.append(str(dfl_workspace))
        
        models = []
        seen_paths = set()
        
        for search_path in search_paths:
            path = Path(search_path)
            if not path.exists():
                continue
            
            # Search for .dfm files recursively
            for dfm_file in path.glob("**/*.dfm"):
                if str(dfm_file) in seen_paths:
                    continue
                seen_paths.add(str(dfm_file))
                
                try:
                    info = DFMModelInfo(
                        path=str(dfm_file),
                        name=dfm_file.stem,
                        resolution=128,  # Will be detected when loaded
                        model_type=DFMEngine._detect_model_type_static(dfm_file),
                        file_size_mb=dfm_file.stat().st_size / (1024 * 1024),
                        created=datetime.fromtimestamp(dfm_file.stat().st_mtime)
                    )
                    models.append(info)
                except Exception as e:
                    print(f"[DFM] Error reading {dfm_file}: {e}")
            
            # Also search for .onnx files (some exported models use this extension)
            for onnx_file in path.glob("**/*.onnx"):
                if str(onnx_file) in seen_paths:
                    continue
                # Only include if it looks like a DFL model
                if 'dfm' in onnx_file.name.lower() or 'model' in onnx_file.name.lower():
                    seen_paths.add(str(onnx_file))
                    try:
                        info = DFMModelInfo(
                            path=str(onnx_file),
                            name=onnx_file.stem,
                            resolution=128,
                            model_type=DFMEngine._detect_model_type_static(onnx_file),
                            file_size_mb=onnx_file.stat().st_size / (1024 * 1024),
                            created=datetime.fromtimestamp(onnx_file.stat().st_mtime)
                        )
                        models.append(info)
                    except Exception as e:
                        print(f"[DFM] Error reading {onnx_file}: {e}")
        
        # Sort by name
        models.sort(key=lambda m: m.name.lower())
        
        return models
    
    @staticmethod
    def _detect_model_type_static(path: Path) -> str:
        """Static version of model type detection."""
        name = path.name.lower()
        if 'saehd' in name:
            return 'SAEHD'
        elif 'amp' in name:
            return 'AMP'
        elif 'quick96' in name:
            return 'Quick96'
        elif 'rtm' in name:
            return 'RTM'
        return 'Unknown'


# Utility functions for face alignment (DFL-compatible)

def get_transform_matrix(
    landmarks: np.ndarray,
    output_size: int = 128,
    face_type: str = 'whole_face'
) -> np.ndarray:
    """
    Calculate the transformation matrix for face alignment.
    
    This creates a DFL-compatible alignment matrix from facial landmarks.
    
    Args:
        landmarks: 5-point or 106-point facial landmarks
        output_size: Target size for aligned face
        face_type: Type of face crop ('whole_face', 'full_face', 'head')
        
    Returns:
        2x3 affine transformation matrix
    """
    # Standard 5-point landmark positions for alignment
    # These are the target positions for: left eye, right eye, nose, left mouth, right mouth
    
    if face_type == 'whole_face':
        # Whole face includes more area
        scale = 1.0
        padding = 0.1
    elif face_type == 'full_face':
        scale = 0.8
        padding = 0.1
    else:  # head
        scale = 1.5
        padding = 0.2
    
    # Extract key points from landmarks
    if len(landmarks) >= 106:
        # InsightFace 106-point landmarks
        left_eye = np.mean(landmarks[33:42], axis=0)
        right_eye = np.mean(landmarks[87:96], axis=0)
        nose = landmarks[86]
        left_mouth = landmarks[52]
        right_mouth = landmarks[61]
    elif len(landmarks) >= 68:
        # Dlib 68-point landmarks
        left_eye = np.mean(landmarks[36:42], axis=0)
        right_eye = np.mean(landmarks[42:48], axis=0)
        nose = landmarks[30]
        left_mouth = landmarks[48]
        right_mouth = landmarks[54]
    elif len(landmarks) == 5:
        # 5-point landmarks
        left_eye = landmarks[0]
        right_eye = landmarks[1]
        nose = landmarks[2]
        left_mouth = landmarks[3]
        right_mouth = landmarks[4]
    else:
        raise ValueError(f"Unsupported landmark count: {len(landmarks)}")
    
    # Source points
    src_pts = np.float32([left_eye, right_eye, nose])
    
    # Target points (normalized positions)
    eye_dist = 0.3 * output_size
    dst_pts = np.float32([
        [output_size * 0.35, output_size * 0.35],  # Left eye
        [output_size * 0.65, output_size * 0.35],  # Right eye
        [output_size * 0.5, output_size * 0.55],   # Nose
    ])
    
    # Calculate affine transform
    matrix = cv2.getAffineTransform(src_pts, dst_pts)
    
    return matrix


def align_face(
    image: np.ndarray,
    landmarks: np.ndarray,
    output_size: int = 128,
    face_type: str = 'whole_face'
) -> Tuple[np.ndarray, np.ndarray]:
    """
    Align and crop a face from an image.
    
    Args:
        image: Source image (BGR)
        landmarks: Facial landmarks
        output_size: Target size for aligned face
        face_type: Type of face crop
        
    Returns:
        Tuple of (aligned_face, transformation_matrix)
    """
    matrix = get_transform_matrix(landmarks, output_size, face_type)
    
    aligned = cv2.warpAffine(
        image, matrix, (output_size, output_size),
        borderMode=cv2.BORDER_REPLICATE
    )
    
    return aligned, matrix


if __name__ == "__main__":
    print("DeepFaceLab DFM Engine Test")
    print("=" * 50)
    
    # List available models
    print("\nSearching for DFM models...")
    models = DFMEngine.list_available_models()
    
    if models:
        print(f"\nFound {len(models)} DFM model(s):")
        for m in models:
            print(f"  - {m.name} ({m.model_type}, {m.file_size_mb:.1f} MB)")
            print(f"    Path: {m.path}")
    else:
        print("\nNo DFM models found.")
        print("To create a DFM model:")
        print("1. Train a model in DeepFaceLab (SAEHD or AMP)")
        print("2. Export using: 6) export SAEHD as dfm.bat")
        print("3. Place the .dfm file in the models/ directory")
    
    # Test loading if models exist
    if models:
        print(f"\nTesting model load: {models[0].name}")
        engine = DFMEngine(models[0].path)
        print(f"Model loaded: {engine.is_loaded()}")
