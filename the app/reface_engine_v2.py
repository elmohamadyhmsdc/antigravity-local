"""
Antigravity Local - Reface Engine V2
Enhanced face swapping with advanced occlusion handling, neural enhancement, and temporal consistency
"""

import os
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Union
from datetime import datetime
from dataclasses import dataclass
import warnings

import cv2
import numpy as np

# Add ALL NVIDIA DLL paths for ONNX Runtime CUDA support
if os.name == 'nt':
    _nvidia_base = os.path.join(sys.prefix, 'Lib', 'site-packages', 'nvidia')
    if os.path.isdir(_nvidia_base):
        for _pkg in os.listdir(_nvidia_base):
            _bin_dir = os.path.join(_nvidia_base, _pkg, 'bin')
            if os.path.isdir(_bin_dir):
                try:
                    os.add_dll_directory(_bin_dir)
                    os.environ['PATH'] = _bin_dir + os.pathsep + os.environ.get('PATH', '')
                except Exception:
                    pass

import insightface
from insightface.app import FaceAnalysis

# Import V1 components for compatibility
from reface_engine import RefaceResult, FaceData, Faceset, RefaceEngine
from ffmpeg_utils import _ffmpeg_exe, mux_audio


@dataclass
class EnhancementConfig:
    """Configuration for face enhancement"""
    enhancer_type: str = "opencv"  # "none", "opencv", "gfpgan", "codeformer"
    strength: float = 0.7  # 0.0 to 1.0
    upscale_factor: int = 2
    
    
@dataclass
class OcclusionConfig:
    """Configuration for occlusion handling"""
    enabled: bool = True
    protect_glasses: bool = True
    protect_hair: bool = True


@dataclass 
class VideoConfig:
    """Configuration for video processing"""
    temporal_smoothing: bool = True
    smoothing_window: int = 3  # frames


MAX_AUTO_DOWNLOAD_BYTES = 500 * 1024 * 1024   # project-wide cap for silent downloads


def is_valid_model_file(path: Union[Path, str], min_bytes: int = 100 * 1024 * 1024,
                        max_bytes: Optional[int] = None) -> bool:
    """Verify that a model file exists, is regular, readable, and big enough.

    max_bytes is the auto-download cap, not a property of a valid model, so it
    is only applied where that cap is what we are actually checking. A model a
    user placed there by hand is never rejected for being large.
    """
    p = Path(path)
    if not p.is_file():
        return False
    try:
        size = p.stat().st_size
        if size < min_bytes:
            return False
        if max_bytes is not None and size > max_bytes:
            return False
        with open(p, "rb") as f:
            f.read(1024)
        return True
    except Exception:
        return False


class NeuralEnhancer:
    """
    Neural face enhancement using GFPGAN or CodeFormer.
    Falls back to OpenCV-based enhancement if neural models unavailable.
    """
    
    def __init__(self, enhancer_type: str = "gfpgan", upscale: int = 2):
        self.enhancer_type = enhancer_type
        self.upscale = upscale
        self.gfpgan = None
        self.codeformer = None
        self.opencv_enhancer = None
        
        self._initialize_enhancer()
    
    def _initialize_enhancer(self):
        """Initialize the selected enhancer"""
        if self.enhancer_type == "gfpgan":
            try:
                from gfpgan import GFPGANer
                model_path = Path(__file__).parent / "models" / "GFPGANv1.4.pth"
                
                if not model_path.exists() or not is_valid_model_file(model_path):
                    # Try to download or use alternative path
                    print(f"[INFO] GFPGAN model not found or invalid at {model_path}")
                    self._download_gfpgan_model(model_path)
                if model_path.exists() and is_valid_model_file(model_path):
                    import torch
                    device = 'cuda' if torch.cuda.is_available() else 'cpu'
                    print(f"[INFO] Initializing GFPGANer on device: {device}")
                    
                    self.gfpgan = GFPGANer(
                        model_path=str(model_path),
                        upscale=self.upscale,
                        arch='clean',
                        channel_multiplier=2,
                        bg_upsampler=None,
                        device=device
                    )
                    print("[INFO] GFPGAN enhancer initialized")
                else:
                    print("[WARNING] GFPGAN model not available, falling back to OpenCV")
                    self.enhancer_type = "opencv"
                    
            except ImportError:
                print("[WARNING] GFPGAN not installed, falling back to OpenCV")
                self.enhancer_type = "opencv"
                
        elif self.enhancer_type == "codeformer":
            try:
                # CodeFormer requires additional setup
                # For now, fall back to GFPGAN or OpenCV
                print("[WARNING] CodeFormer not yet implemented, using GFPGAN")
                self.enhancer_type = "gfpgan"
                self._initialize_enhancer()
                return
            except Exception as e:
                print(f"[WARNING] CodeFormer initialization failed: {e}")
                self.enhancer_type = "opencv"
        
        if self.enhancer_type == "opencv":
            from reface_engine import FaceEnhancer
            self.opencv_enhancer = FaceEnhancer(upscale_factor=self.upscale)
    
    def _download_gfpgan_model(self, model_path: Path):
        """Download GFPGAN model if not present, using temporary file, validation, and single retry."""
        import urllib.request
        import shutil

        model_path = Path(model_path)
        model_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = model_path.with_suffix(model_path.suffix + ".part")
        url = "https://github.com/TencentARC/GFPGAN/releases/download/v1.3.0/GFPGANv1.4.pth"

        print(f"[INFO] GFPGAN model is ~340 MB. Downloading to {model_path.name}...")

        max_attempts = 2
        for attempt in range(1, max_attempts + 1):
            if tmp.exists():
                try:
                    tmp.unlink()
                except Exception:
                    pass
            try:
                with urllib.request.urlopen(url, timeout=30) as response:
                    content_length = response.headers.get("Content-Length")
                    total_size = int(content_length) if content_length and content_length.isdigit() else 0
                    if total_size > MAX_AUTO_DOWNLOAD_BYTES:
                        print(f"[WARNING] Remote model size ({total_size} bytes) exceeds limit of {MAX_AUTO_DOWNLOAD_BYTES} bytes. Download aborted.")
                        return

                    chunk_size = 1024 * 1024  # 1 MB
                    downloaded = 0
                    last_pct = 0
                    with open(tmp, "wb") as f:
                        while True:
                            chunk = response.read(chunk_size)
                            if not chunk:
                                break
                            f.write(chunk)
                            downloaded += len(chunk)
                            if total_size > 0:
                                pct = int((downloaded / total_size) * 100)
                                if pct >= last_pct + 5:
                                    print(f"[INFO] Download progress: {pct}% ({downloaded // (1024 * 1024)} MB / {total_size // (1024 * 1024)} MB)")
                                    last_pct = (pct // 5) * 5

                # Validate downloaded temporary file
                if not is_valid_model_file(tmp, max_bytes=MAX_AUTO_DOWNLOAD_BYTES):
                    actual_size = tmp.stat().st_size if tmp.exists() else 0
                    if tmp.exists():
                        tmp.unlink()
                    raise ValueError(f"Downloaded model failed validation (size: {actual_size} bytes, expected >= 100MB and <= 500MB)")

                # Move verified file to final path
                if model_path.exists():
                    try:
                        model_path.unlink()
                    except Exception:
                        pass
                shutil.move(str(tmp), str(model_path))
                print(f"[INFO] Downloaded and verified GFPGAN model to {model_path}")
                return

            except Exception as e:
                print(f"[WARNING] GFPGAN download attempt {attempt}/{max_attempts} failed: {e}")
                if tmp.exists():
                    try:
                        tmp.unlink()
                    except Exception:
                        pass
                if attempt == max_attempts:
                    print("[WARNING] GFPGAN download failed after retry. Run manually:")
                    print("python download_models.py --extras")
                    return
    
    def enhance(self, image: np.ndarray, strength: float = 0.7) -> np.ndarray:
        """
        Enhance the input image using the selected method.
        
        Args:
            image: BGR image array
            strength: Enhancement strength (0.0-1.0), used for blending
            
        Returns:
            Enhanced BGR image
        """
        if self.enhancer_type == "none":
            return image
            
        try:
            if self.enhancer_type == "gfpgan" and self.gfpgan:
                # GFPGAN enhancement
                _, _, enhanced = self.gfpgan.enhance(
                    image,
                    has_aligned=False,
                    only_center_face=False,
                    paste_back=True
                )
                
                # Blend with original based on strength
                if strength < 1.0:
                    # Resize original to match enhanced size
                    h, w = enhanced.shape[:2]
                    original_resized = cv2.resize(image, (w, h), interpolation=cv2.INTER_LANCZOS4)
                    enhanced = cv2.addWeighted(enhanced, strength, original_resized, 1 - strength, 0)
                
                return enhanced
                
            elif self.opencv_enhancer:
                enhanced = self.opencv_enhancer.enhance(image)
                if strength < 1.0:
                    h, w = enhanced.shape[:2]
                    original_resized = cv2.resize(image, (w, h), interpolation=cv2.INTER_LANCZOS4)
                    enhanced = cv2.addWeighted(enhanced, strength, original_resized, 1 - strength, 0)
                return enhanced
            else:
                return image
                
        except Exception as e:
            print(f"[WARNING] Enhancement failed: {e}")
            return image


def as_68_points(landmarks) -> Optional[np.ndarray]:
    """Return an (68, 2) float32 array, or None when the layout is not 68-point.

    The 68-point index conventions used by the occlusion mask are only valid
    for a 68-point array. A 106-point array is a different layout entirely and
    must not be reindexed with them.
    """
    if landmarks is None:
        return None
    try:
        pts = np.asarray(landmarks)
        if pts.ndim != 2 or pts.shape[1] < 2:
            return None
        if pts.shape[0] == 68:
            return np.asarray(pts[:, :2], dtype=np.float32)
    except Exception:
        return None
    return None


class OcclusionHandler:
    """
    Advanced occlusion handling using landmarks and geometric priors.
    Detects and preserves glasses, hands, hair that overlap with face.
    """
    def __init__(self):
        print("[INFO] OcclusionHandler initialized (landmark-based)")
    
    def generate_occlusion_mask(
        self, 
        image: np.ndarray,
        face_bbox: List[int],
        face_landmarks: Optional[np.ndarray] = None,
        protect_glasses: bool = True,
        protect_hair: bool = True
    ) -> np.ndarray:
        """
        Generate a mask indicating which pixels should be protected from swapping.
        
        Args:
            image: BGR image
            face_bbox: Face bounding box [x1, y1, x2, y2]
            face_landmarks: 2D face landmarks if available
            protect_glasses: Whether to protect glasses region
            protect_hair: Whether to protect hair region
            
        Returns:
            Binary mask (255 = protected, 0 = can be swapped)
        """
        h, w = image.shape[:2]
        occlusion_mask = np.zeros((h, w), dtype=np.uint8)
        
        x1, y1, x2, y2 = [int(b) for b in face_bbox]
        
        pts_68 = as_68_points(face_landmarks)
        if pts_68 is not None:
            # Use landmarks for more precise masking
            
            if protect_glasses:
                # Eye region (typically indices 36-47 for 68-point landmarks)
                try:
                    left_eye = pts_68[36:42]
                    right_eye = pts_68[42:48]
                    
                    # Expand eye regions for glasses
                    for eye_pts in [left_eye, right_eye]:
                        eye_center = np.mean(eye_pts, axis=0)
                        eye_width = np.max(eye_pts[:, 0]) - np.min(eye_pts[:, 0])
                        
                        # Create ellipse mask for glasses area
                        cv2.ellipse(
                            occlusion_mask,
                            (int(eye_center[0]), int(eye_center[1])),
                            (int(eye_width * 0.8), int(eye_width * 0.5)),
                            0, 0, 360, 255, -1
                        )
                except Exception as e:
                    print(f"[WARNING] Glasses occlusion mask failed: {e}")
                    pass
            
            if protect_hair:
                # Forehead/hair region above eyebrows
                try:
                    left_brow = pts_68[17:22]
                    right_brow = pts_68[22:27]
                    
                    brow_top = min(np.min(left_brow[:, 1]), np.min(right_brow[:, 1]))
                    face_top = max(0, y1)
                    
                    if brow_top > face_top:
                        # Half-ellipse mask narrower than box by ~10%
                        hair_mask = np.zeros((h, w), dtype=np.uint8)
                        cx = int((x1 + x2) / 2)
                        cy = int(brow_top)
                        box_w = x2 - x1
                        ax = max(1, int(0.45 * box_w))
                        ay = max(1, int(brow_top - face_top))
                        cv2.ellipse(hair_mask, (cx, cy), (ax, ay), 0, 180, 360, 255, -1)
                        occlusion_mask = cv2.bitwise_or(occlusion_mask, hair_mask)
                except Exception:
                    pass
        
        return occlusion_mask
    
    def apply_occlusion_protection(
        self,
        original: np.ndarray,
        swapped: np.ndarray,
        occlusion_mask: np.ndarray,
        feather_radius: int = 5
    ) -> np.ndarray:
        """
        Apply occlusion mask to preserve original pixels in protected areas.
        
        Args:
            original: Original image before swap
            swapped: Image after face swap
            occlusion_mask: Binary mask of protected areas
            feather_radius: Blur radius for soft edges
            
        Returns:
            Composited image
        """
        if occlusion_mask is None or np.sum(occlusion_mask) == 0:
            return swapped
        
        # Feather the mask for smooth transitions
        # Ensure kernel size is positive and odd
        if feather_radius > 0:
            ksize = max(1, int(feather_radius) * 2 + 1)
            if ksize % 2 == 0:
                ksize += 1
            occlusion_mask = cv2.GaussianBlur(occlusion_mask, (ksize, ksize), 0)
        
        # Normalize mask to 0-1 range
        mask_float = occlusion_mask.astype(np.float32) / 255.0
        mask_3ch = np.stack([mask_float] * 3, axis=-1)
        
        # Composite: protected areas from original, rest from swapped
        result = (original.astype(np.float32) * mask_3ch + 
                  swapped.astype(np.float32) * (1 - mask_3ch))
        
        return result.astype(np.uint8)


class TemporalStabilizer:
    """
    Temporal consistency for video face swapping.
    Reduces jitter and ensures smooth transitions between frames.
    """
    
    def __init__(self, window_size: int = 3):
        self.window_size = window_size
        self.frame_buffer = []
    
    def reset(self):
        """Reset buffers for new video"""
        self.frame_buffer = []
    
    def add_frame(self, frame: np.ndarray):
        """Add a frame to the buffer"""
        self.frame_buffer.append(frame.copy())
        
        # Keep buffer size limited
        if len(self.frame_buffer) > self.window_size:
            self.frame_buffer.pop(0)
    
    def blend_frames(self, current_frame: np.ndarray, blend_strength: float = 0.3) -> np.ndarray:
        """
        Blend current frame with rolling average of buffer to reduce flicker.
        """
        if not self.frame_buffer or blend_strength <= 0:
            return current_frame
        
        # Check if all frames in buffer match current_frame shape
        cur_shape = current_frame.shape
        for f in self.frame_buffer:
            if f.shape != cur_shape:
                return current_frame
        
        # Average with rolling buffer for temporal smoothing
        reference = np.mean(np.stack(self.frame_buffer).astype(np.float32), axis=0)
        
        blended = (current_frame.astype(np.float32) * (1.0 - blend_strength) +
                   reference * blend_strength)
        return np.clip(blended, 0, 255).astype(current_frame.dtype)


def compute_frame_range(fps: float, total_frames: int,
                        start_time: float = 0.0, end_time: Optional[float] = None) -> Tuple[int, int]:
    """Return (start_frame, end_frame) clamped to a sane range.

    total_frames <= 0 means the container did not report a count; the caller
    must then read until the stream ends instead of trusting a frame budget.
    """
    effective_fps = float(fps)
    if effective_fps <= 0:
        print("[WARNING] Invalid or zero FPS reported by container; falling back to 25.0")
        effective_fps = 25.0

    if end_time is not None and end_time <= 0:
        end_time = None

    start_frame = int(start_time * effective_fps) if start_time > 0 else 0

    if total_frames <= 0:
        # No frame budget to clamp against, but an explicit end time is still a
        # real instruction - honouring it here is what keeps trimming working on
        # containers that do not report a frame count.
        if end_time is not None:
            return (start_frame, max(start_frame + 1, int(end_time * effective_fps)))
        return (start_frame, -1)

    # When total_frames > 0:
    start_frame = max(0, min(start_frame, total_frames - 1))

    if end_time is not None:
        end_frame = min(int(end_time * effective_fps), total_frames)
    else:
        end_frame = total_frames

    end_frame = max(start_frame + 1, min(end_frame, total_frames))
    return (start_frame, end_frame)


def fit_to_frame(frame: np.ndarray, width: int, height: int) -> np.ndarray:
    """Resize only when the frame does not already match the writer's size."""
    h, w = frame.shape[:2]
    if w == width and h == height:
        return frame
    return cv2.resize(frame, (width, height), interpolation=cv2.INTER_LINEAR)


class _SourceProxy:
    """Minimal stand-in for an insightface Face on the source side.

    INSwapper.get only reads normed_embedding from the source face.
    """
    def __init__(self, embedding: np.ndarray):
        arr = np.asarray(embedding, dtype=np.float32)
        n = np.linalg.norm(arr)
        self.normed_embedding = arr / n if n > 0 else arr
        self.embedding = arr


def get_source_face(fd, app) -> Optional[Union[_SourceProxy, object]]:
    """Return a fast _SourceProxy if embedding is valid; fallback to image detection."""
    emb = getattr(fd, 'embedding', None)
    if emb is not None:
        arr = np.asarray(emb)
        if arr.size == 512:
            return _SourceProxy(arr)
    if getattr(fd, 'image_path', None) and app is not None:
        src_img = cv2.imread(fd.image_path)
        if src_img is not None:
            faces = app.get(src_img)
            if faces:
                return faces[0]
# Tunable. Enhancing a face that the source never resolved just invents detail
# that clashes with the rest of the frame, so the gate is deliberately strict.
MIN_FRAME_SHORT_SIDE = 540      # pixels
MIN_FACE_HEIGHT = 128           # pixels, in the original frame
MIN_FACE_SHARPNESS = 60.0       # variance of Laplacian on the face crop


def should_enhance_face(frame_shape, face_bbox, face_crop) -> bool:
    """True only when the source actually resolved this face.

    Three independent gates, all of which must pass: the frame is not a
    low-resolution source, the face occupies enough pixels to carry real
    detail, and the crop is actually in focus rather than motion-blurred.
    """
    if frame_shape is None or face_bbox is None or face_crop is None:
        return False
    if min(frame_shape[0], frame_shape[1]) < MIN_FRAME_SHORT_SIDE:
        return False
    x1, y1, x2, y2 = [int(round(v)) for v in face_bbox]
    face_h = y2 - y1
    if face_h < MIN_FACE_HEIGHT:
        return False
    if not isinstance(face_crop, np.ndarray) or face_crop.size == 0:
        return False
    try:
        if len(face_crop.shape) == 3:
            gray = cv2.cvtColor(face_crop, cv2.COLOR_BGR2GRAY)
        else:
            gray = face_crop
        sharpness = float(cv2.Laplacian(gray, cv2.CV_64F).var())
        return sharpness >= MIN_FACE_SHARPNESS
    except Exception:
        return False


class RefaceEngineV2(RefaceEngine):
    """
    Enhanced face swapping engine (V2).
    
    Builds on V1 with:
    - Advanced occlusion handling
    - Neural face enhancement (GFPGAN/CodeFormer)
    - Improved color correction
    - Temporal consistency for video
    """
    
    VERSION = "2.0"
    
    def __init__(
        self,
        output_dir: str = None,
        enhancement_config: EnhancementConfig = None,
        occlusion_config: OcclusionConfig = None,
        video_config: VideoConfig = None
    ):
        # Initialize parent with minimal enhancement (we handle it ourselves)
        super().__init__(
            output_dir=output_dir,
            enable_enhancement=False,
            upscale=1
        )
        
        # V2 configurations
        self.enhancement_config = enhancement_config or EnhancementConfig()
        self.occlusion_config = occlusion_config or OcclusionConfig()
        self.video_config = video_config or VideoConfig()
        
        # Initialize V2 components
        self.neural_enhancer = None
        self.occlusion_handler = None
        self.temporal_stabilizer = None
        
        self._initialize_v2_components()
        
        print(f"[INFO] RefaceEngine V2 initialized")
    
    def _initialize_v2_components(self):
        """Initialize V2 enhancement components"""
        # Neural enhancer
        if self.enhancement_config.enhancer_type != "none":
            self.neural_enhancer = NeuralEnhancer(
                enhancer_type=self.enhancement_config.enhancer_type,
                upscale=self.enhancement_config.upscale_factor
            )
        
        # Occlusion handler
        if self.occlusion_config.enabled:
            self.occlusion_handler = OcclusionHandler()
        
        # Temporal stabilizer for video
        if self.video_config.temporal_smoothing:
            self.temporal_stabilizer = TemporalStabilizer(
                window_size=self.video_config.smoothing_window
            )
    
    def _advanced_color_correction(
        self, 
        source_img: np.ndarray, 
        target_img: np.ndarray,
        face_mask: Optional[np.ndarray] = None
    ) -> np.ndarray:
        """
        Advanced color correction with skin-tone awareness.
        """
        try:
            if face_mask is not None and not np.any(face_mask > 127):
                return source_img

            # Convert to LAB
            s_lab = cv2.cvtColor(source_img, cv2.COLOR_BGR2LAB).astype(np.float32)
            t_lab = cv2.cvtColor(target_img, cv2.COLOR_BGR2LAB).astype(np.float32)
            
            # If we have a face mask, compute stats only on face region
            if face_mask is not None:
                mask_bool = face_mask > 127
                s_mean = np.mean(s_lab[mask_bool], axis=0)
                s_std = np.std(s_lab[mask_bool], axis=0)
                t_mean = np.mean(t_lab[mask_bool], axis=0)
                t_std = np.std(t_lab[mask_bool], axis=0)
            else:
                s_mean = np.mean(s_lab, axis=(0, 1))
                s_std = np.std(s_lab, axis=(0, 1))
                t_mean = np.mean(t_lab, axis=(0, 1))
                t_std = np.std(t_lab, axis=(0, 1))
            
            # Apply color transfer
            result_lab = s_lab.copy()
            for i in range(3):
                result_lab[:, :, i] = ((s_lab[:, :, i] - s_mean[i]) * 
                                       (t_std[i] / (s_std[i] + 1e-6)) + t_mean[i])
            
            # Clip and convert back
            result_lab = np.clip(result_lab, 0, 255).astype(np.uint8)
            result = cv2.cvtColor(result_lab, cv2.COLOR_LAB2BGR)
            
            if face_mask is not None:
                mask_float = (face_mask > 127).astype(np.float32)
                feathered = cv2.GaussianBlur(mask_float, (15, 15), 0)
                feathered[feathered < 1e-3] = 0.0
                feathered = np.clip(feathered, 0.0, 1.0)
                if feathered.ndim == 2:
                    feathered = feathered[:, :, np.newaxis]
                blended = result.astype(np.float32) * feathered + source_img.astype(np.float32) * (1.0 - feathered)
                result = np.clip(blended, 0, 255).astype(np.uint8)
            
            return result
            
        except Exception as e:
            print(f"[WARNING] Color correction failed: {e}")
            return source_img
    
    def reface_with_faceset_v2(
        self,
        target_image_path: str,
        faceset: Faceset,
        target_face_indices: Optional[List[int]] = None,
        use_angle_matching: bool = True,
        apply_occlusion: bool = True
    ) -> RefaceResult:
        """
        Enhanced face swap with V2 features.
        """
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        try:
            # Load target image
            target_img = cv2.imread(target_image_path)
            if target_img is None:
                return RefaceResult(False, None, f"Could not load: {target_image_path}")
            
            # Keep original for occlusion compositing
            original_img = target_img.copy()
            
            # Detect faces in target
            target_faces = self.app.get(target_img)
            if not target_faces:
                return RefaceResult(False, None, "No faces detected in target")
            
            if self.swapper is None:
                return RefaceResult(False, None, "Inswapper model not loaded")
            
            if not faceset.faces:
                return RefaceResult(False, None, "Faceset is empty")
            
            result_img = target_img.copy()
            faces_swapped = 0
            
            # Pre-load source faces (fast _SourceProxy or fallback to detection)
            source_face_cache = {}
            for i, fd in enumerate(faceset.faces):
                face = get_source_face(fd, self.app)
                if face is not None:
                    source_face_cache[i] = face
            
            if not source_face_cache:
                return RefaceResult(False, None, "Could not load any source faces")
            
            fallback_source = list(source_face_cache.values())[0]
            
            # Determine faces to swap
            if target_face_indices is not None:
                faces_to_swap = [(idx, target_faces[idx]) for idx in target_face_indices 
                                 if 0 <= idx < len(target_faces)]
            else:
                faces_to_swap = list(enumerate(target_faces))
            
            swapped_mask = np.zeros(result_img.shape[:2], dtype=np.uint8)
            
            # Process each face
            for idx, target_face in faces_to_swap:
                source_face = None
                
                # Angle matching
                if use_angle_matching and len(source_face_cache) > 1:
                    target_pose = self._get_face_pose(target_face)
                    source_data = faceset.get_best_match(target_pose)
                    
                    if source_data:
                        for i, fd in enumerate(faceset.faces):
                            if fd.image_path == source_data.image_path and i in source_face_cache:
                                source_face = source_face_cache[i]
                                break
                
                if source_face is None:
                    source_face = fallback_source
                
                # Generate occlusion mask before swap
                # Bind the box before it is needed: the feather radius below is
                # derived from it, so it has to exist before the occlusion step.
                x1, y1, x2, y2 = target_face.bbox.astype(int)

                occlusion_mask = None
                if apply_occlusion and self.occlusion_handler:
                    landmarks = getattr(target_face, 'landmark_3d_68', None)
                    if landmarks is None:
                        landmarks = getattr(target_face, 'landmark_2d_106', None)

                    occlusion_mask = self.occlusion_handler.generate_occlusion_mask(
                        original_img,
                        [x1, y1, x2, y2],
                        landmarks,
                        protect_glasses=self.occlusion_config.protect_glasses,
                        protect_hair=self.occlusion_config.protect_hair
                    )

                # Perform swap
                result_img = self.swapper.get(result_img, target_face, source_face, paste_back=True)

                # Apply occlusion protection
                if occlusion_mask is not None and np.sum(occlusion_mask) > 0:
                    feather_radius = max(5, int(0.04 * (x2 - x1)))
                    result_img = self.occlusion_handler.apply_occlusion_protection(
                        original_img, result_img, occlusion_mask, feather_radius=feather_radius
                    )

                cv2.rectangle(swapped_mask, (x1, y1), (x2, y2), 255, -1)
                faces_swapped += 1
            
            # Apply color correction once for all swapped faces
            if swapped_mask.any():
                result_img = self._advanced_color_correction(result_img, original_img, swapped_mask)
            
            # Apply neural enhancement
            if self.neural_enhancer:
                result_img = self.neural_enhancer.enhance(
                    result_img,
                    strength=self.enhancement_config.strength
                )
            
            # Save result
            result_path = self.output_dir / f"refaced_v2_{timestamp}.jpg"
            cv2.imwrite(str(result_path), result_img, [cv2.IMWRITE_JPEG_QUALITY, 95])
            
            return RefaceResult(
                success=True,
                output_path=str(result_path),
                message=f"V2 Face swap completed ({faces_swapped} faces swapped)",
                faces_swapped=faces_swapped
            )
            
        except Exception as e:
            import traceback
            traceback.print_exc()
            return RefaceResult(False, None, f"Error: {str(e)}")
    
    def reface_video_with_faceset_v2(
        self,
        target_video_path: str,
        faceset: Faceset,
        target_face_indices: Optional[List[int]] = None,
        use_angle_matching: bool = True,
        apply_occlusion: bool = True,
        enhancement_mode: str = "auto",
        resume_from_frame: int = 0,
        finalize: bool = True,
        progress_callback=None,
        start_time: float = 0.0,
        end_time: Optional[float] = None
    ) -> RefaceResult:
        """
        Enhanced video face swap with temporal consistency.
        """
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        cap = None
        out = None
        try:
            if self.swapper is None:
                return RefaceResult(False, None, "Inswapper model not loaded")
            
            cap = cv2.VideoCapture(target_video_path)
            if not cap.isOpened():
                return RefaceResult(False, None, f"Could not open: {target_video_path}")
            
            fps = float(cap.get(cv2.CAP_PROP_FPS))
            if fps <= 0:
                print("[WARNING] Invalid or zero FPS reported by container; falling back to 25.0")
                fps = 25.0
            width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            
            # Calculate output dimensions (never upscale video frames)
            out_width = width
            out_height = height
            
            # Output path
            result_path = self.output_dir / f"refaced_v2_video_{timestamp}.avi"
            fourcc = cv2.VideoWriter_fourcc(*'MJPG') # Use Motion JPEG for higher quality intermediate
            out = cv2.VideoWriter(str(result_path), fourcc, int(round(fps)), (out_width, out_height))
            
            # Pre-cache source faces (fast _SourceProxy or fallback to detection)
            source_face_cache = {}
            for i, fd in enumerate(faceset.faces):
                face = get_source_face(fd, self.app)
                if face is not None:
                    source_face_cache[i] = face
            
            if not source_face_cache:
                cap.release()
                return RefaceResult(False, None, "Could not load any source faces")
            
            fallback_source = list(source_face_cache.values())[0]
            
            
            # Calculate frame range from time parameters
            start_frame, end_frame = compute_frame_range(fps, total_frames, start_time, end_time)
            if resume_from_frame > 0:
                if end_frame != -1:
                    start_frame = min(start_frame + resume_from_frame, end_frame - 1)
                else:
                    start_frame = start_frame + resume_from_frame

            if end_frame != -1:
                frames_to_process = max(1, end_frame - start_frame)
                print(f"[INFO] Processing frames {start_frame} to {end_frame} ({frames_to_process} frames, {frames_to_process/fps:.1f}s)")
            else:
                # 0 means "unknown". Never invent a denominator: a made-up one
                # makes the reported ratio climb past 1.0 and Streamlit's
                # progress bar rejects that.
                frames_to_process = 0
                print(f"[INFO] Processing from frame {start_frame} to end of stream (container reported no frame count)")
            
            # Reset temporal stabilizer
            if self.temporal_stabilizer:
                self.temporal_stabilizer.reset()
            
            frames_processed = 0
            total_swaps = 0
            enhanced_faces = 0
            skipped_faces = 0          # failed the quality gate
            unenhanced_faces = 0       # enhancement was off or unavailable
            current_frame = start_frame
            stopped = False
            resized_frames_count = 0
            
            # Seek to start frame
            if start_frame > 0:
                cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
            
            while end_frame == -1 or current_frame < end_frame:
                ret, frame = cap.read()
                if not ret:
                    break
                
                original_frame = frame.copy()
                target_faces = self.app.get(frame)
                
                swapped_mask = np.zeros(frame.shape[:2], dtype=np.uint8)
                # Reset per frame: the enhancement pass below reads this outside
                # the `if target_faces` block, so a face-less frame must not keep
                # the previous frame's boxes.
                faces_to_swap = []
                if target_faces:
                    if target_face_indices is not None:
                        for idx in target_face_indices:
                            if 0 <= idx < len(target_faces):
                                faces_to_swap.append(target_faces[idx])
                    else:
                        faces_to_swap = target_faces
                    
                    for target_face in faces_to_swap:
                        source_face = None
                        
                        if use_angle_matching and len(source_face_cache) > 1:
                            target_pose = self._get_face_pose(target_face)
                            source_data = faceset.get_best_match(target_pose)
                            
                            if source_data:
                                for i, fd in enumerate(faceset.faces):
                                    if fd.image_path == source_data.image_path and i in source_face_cache:
                                        source_face = source_face_cache[i]
                                        break
                        
                        if source_face is None:
                            source_face = fallback_source
                        
                        # Bind the box before it is needed: the feather radius
                        # below is derived from it.
                        x1, y1, x2, y2 = target_face.bbox.astype(int)

                        # Generate occlusion mask before swap
                        occlusion_mask = None
                        if apply_occlusion and self.occlusion_handler:
                            landmarks = getattr(target_face, 'landmark_3d_68', None)
                            if landmarks is None:
                                landmarks = getattr(target_face, 'landmark_2d_106', None)

                            occlusion_mask = self.occlusion_handler.generate_occlusion_mask(
                                original_frame,
                                [x1, y1, x2, y2],
                                landmarks,
                                protect_glasses=self.occlusion_config.protect_glasses,
                                protect_hair=self.occlusion_config.protect_hair
                            )

                        # Perform swap
                        frame = self.swapper.get(frame, target_face, source_face, paste_back=True)

                        # Apply occlusion protection
                        if occlusion_mask is not None and np.sum(occlusion_mask) > 0:
                            feather_radius = max(5, int(0.04 * (x2 - x1)))
                            frame = self.occlusion_handler.apply_occlusion_protection(
                                original_frame, frame, occlusion_mask, feather_radius=feather_radius
                            )

                        cv2.rectangle(swapped_mask, (x1, y1), (x2, y2), 255, -1)
                        total_swaps += 1
                
                # Color correction once per frame on swapped areas
                if swapped_mask.any():
                    frame = self._advanced_color_correction(frame, original_frame, swapped_mask)
                
                # Face-only enhancement gated by quality / mode (never enhance full video frame)
                if faces_to_swap and self.neural_enhancer and enhancement_mode != "off":
                    for target_face in faces_to_swap:
                        x1, y1, x2, y2 = target_face.bbox.astype(int)
                        # Crop face with 20% margin
                        w = x2 - x1
                        h = y2 - y1
                        margin_x = int(0.20 * w)
                        margin_y = int(0.20 * h)
                        crop_x1 = max(0, x1 - margin_x)
                        crop_y1 = max(0, y1 - margin_y)
                        crop_x2 = min(frame.shape[1], x2 + margin_x)
                        crop_y2 = min(frame.shape[0], y2 + margin_y)

                        face_crop = frame[crop_y1:crop_y2, crop_x1:crop_x2]
                        if face_crop.size == 0:
                            continue

                        should_enhance = False
                        if enhancement_mode == "always":
                            should_enhance = True
                        elif enhancement_mode == "auto":
                            orig_crop = original_frame[crop_y1:crop_y2, crop_x1:crop_x2]
                            should_enhance = should_enhance_face(original_frame.shape, target_face.bbox, orig_crop)

                        if should_enhance:
                            enhanced_faces += 1
                            enhanced_crop = self.neural_enhancer.enhance(
                                face_crop.copy(),
                                strength=self.enhancement_config.strength
                            )
                            if enhanced_crop.shape[:2] != face_crop.shape[:2]:
                                enhanced_crop = cv2.resize(
                                    enhanced_crop,
                                    (face_crop.shape[1], face_crop.shape[0]),
                                    interpolation=cv2.INTER_LANCZOS4
                                )
                            ch, cw = face_crop.shape[:2]
                            if ch > 10 and cw > 10:
                                feather_x = max(3, int(cw * 0.10))
                                feather_y = max(3, int(ch * 0.10))
                                ksize_x = feather_x * 2 + 1
                                ksize_y = feather_y * 2 + 1
                                inner_mask = np.zeros((ch, cw), dtype=np.float32)
                                inner_mask[feather_y:max(feather_y + 1, ch - feather_y),
                                           feather_x:max(feather_x + 1, cw - feather_x)] = 1.0
                                blend_mask = cv2.GaussianBlur(inner_mask, (ksize_x, ksize_y), 0)
                                blend_mask = np.expand_dims(blend_mask, axis=2)
                                blended = (enhanced_crop.astype(np.float32) * blend_mask +
                                           face_crop.astype(np.float32) * (1.0 - blend_mask)).astype(np.uint8)
                                frame[crop_y1:crop_y2, crop_x1:crop_x2] = blended
                            else:
                                frame[crop_y1:crop_y2, crop_x1:crop_x2] = enhanced_crop
                        else:
                            skipped_faces += 1
                elif faces_to_swap and (enhancement_mode == "off" or not self.neural_enhancer):
                    unenhanced_faces += len(faces_to_swap)
                
                # Temporal stabilization
                if self.temporal_stabilizer and self.video_config.temporal_smoothing:
                    # Use a lighter blend to reduce ghosting while maintaining stability
                    blend_strength = 0.20 if self.neural_enhancer else 0.10
                    self.temporal_stabilizer.add_frame(frame)
                    frame = self.temporal_stabilizer.blend_frames(frame, blend_strength=blend_strength)
                

                if frame.shape[1] != out_width or frame.shape[0] != out_height:
                    frame = fit_to_frame(frame, out_width, out_height)
                    resized_frames_count += 1

                out.write(frame)
                frames_processed += 1
                current_frame += 1
                
                if progress_callback and frames_processed % 5 == 0:
                    # With an unknown total, grow the denominator with the work
                    # done so the ratio stays inside [0, 1] and still advances.
                    progress_total = frames_to_process or (frames_processed + 1)
                    if progress_callback(frames_processed, progress_total) is False:
                        stopped = True
                        break
            
            cap.release()
            out.release()
            print(f"[INFO] enhanced {enhanced_faces} face(s), "
                  f"skipped {skipped_faces} below the quality gate, "
                  f"{unenhanced_faces} with enhancement off")

            if resized_frames_count > 0:
                print(f"[WARNING] {resized_frames_count} frame(s) were resized to fit writer dimensions ({out_width}x{out_height})")
            
            # If not finalize (part rendering for resume), return segment path directly
            if not finalize:
                part_status = " (stopped early)" if stopped else ""
                return RefaceResult(
                    success=True,
                    output_path=str(result_path),
                    message=f"V2 video part rendered ({frames_processed} frames){part_status}",
                    faces_swapped=total_swaps
                )
            
            # Convert to MP4
            mp4_path = result_path.with_suffix('.mp4')
            try:
                import subprocess
                ffmpeg_exe = _ffmpeg_exe()
                
                ffmpeg_cmd = [
                    ffmpeg_exe, '-y',
                    '-i', str(result_path),
                    '-c:v', 'libx264',
                    '-preset', 'medium',      # Slower but better quality
                    '-crf', '16',             # Lower CRF means higher quality (visually lossless)
                    '-pix_fmt', 'yuv420p',
                    str(mp4_path)
                ]
                subprocess.run(ffmpeg_cmd, capture_output=True, check=True)
                result_path.unlink(missing_ok=True)
                result_path = mp4_path
                print(f"[INFO] Converted to MP4: {mp4_path}")

                # Preserve source audio
                if mux_audio(mp4_path, target_video_path, start_time, end_time):
                    print(f"[INFO] V2 video: original audio preserved")
            except Exception as e:
                print(f"[WARNING] FFmpeg conversion failed: {e}")
            
            if progress_callback and not stopped:
                final_total = frames_to_process or max(frames_processed, 1)
                progress_callback(final_total, final_total)
            
            # Build result message with trim info
            trim_info = ""
            if start_time > 0 or end_time is not None:
                trim_info = f" (trimmed {start_time:.1f}s - {end_time:.1f}s)" if end_time else f" (from {start_time:.1f}s)"
            
            status_text = "stopped early" if stopped else "completed"
            return RefaceResult(
                success=True,
                output_path=str(result_path),
                message=f"V2 Video {status_text} ({total_swaps} swaps in {frames_processed} frames){trim_info}",
                faces_swapped=total_swaps
            )
            
        except Exception as e:
            import traceback
            traceback.print_exc()
            return RefaceResult(False, None, f"Error: {str(e)}")
        finally:
            if cap is not None and hasattr(cap, 'isOpened') and cap.isOpened():
                try:
                    cap.release()
                except Exception:
                    pass
            if out is not None and hasattr(out, 'isOpened') and out.isOpened():
                try:
                    out.release()
                except Exception:
                    pass


if __name__ == "__main__":
    print("Testing RefaceEngine V2...")
    
    try:
        engine = RefaceEngineV2()
        print(f"✅ RefaceEngine V2 initialized!")
        print(f"   Version: {engine.VERSION}")
        print(f"   Enhancer: {engine.enhancement_config.enhancer_type}")
        print(f"   Occlusion handling: {engine.occlusion_config.enabled}")
        print(f"   Temporal smoothing: {engine.video_config.temporal_smoothing}")
        
        if engine.swapper:
            print("✅ Inswapper model loaded")
        else:
            print("⚠️ Download inswapper_128.onnx to models/ folder")
    except Exception as e:
        print(f"❌ Initialization failed: {e}")
        import traceback
        traceback.print_exc()
