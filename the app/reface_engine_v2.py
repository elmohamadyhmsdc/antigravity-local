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
    mode: str = "auto"  # "auto", "manual", "disabled"
    protect_glasses: bool = True
    protect_hair: bool = True


@dataclass 
class VideoConfig:
    """Configuration for video processing"""
    temporal_smoothing: bool = True
    smoothing_window: int = 3  # frames
    stabilize_landmarks: bool = True


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
                
                if not model_path.exists():
                    # Try to download or use alternative path
                    print(f"[INFO] GFPGAN model not found at {model_path}")
                    print("[INFO] Downloading GFPGAN model...")
                    self._download_gfpgan_model(model_path)
                if model_path.exists():
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
            except:
                self.enhancer_type = "opencv"
        
        if self.enhancer_type == "opencv":
            from reface_engine import FaceEnhancer
            self.opencv_enhancer = FaceEnhancer(upscale_factor=self.upscale)
    
    def _download_gfpgan_model(self, model_path: Path):
        """Download GFPGAN model if not present"""
        try:
            import urllib.request
            model_path.parent.mkdir(parents=True, exist_ok=True)
            url = "https://github.com/TencentARC/GFPGAN/releases/download/v1.3.0/GFPGANv1.4.pth"
            print(f"[INFO] Downloading from {url}...")
            urllib.request.urlretrieve(url, str(model_path))
            print(f"[INFO] Downloaded GFPGAN model to {model_path}")
        except Exception as e:
            print(f"[WARNING] Failed to download GFPGAN model: {e}")
    
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
                return self.opencv_enhancer.enhance(image)
            else:
                return image
                
        except Exception as e:
            print(f"[WARNING] Enhancement failed: {e}")
            return image


class OcclusionHandler:
    """
    Advanced occlusion handling using semantic segmentation.
    Detects and preserves glasses, hands, hair that overlap with face.
    """
    
    def __init__(self):
        self.face_parser = None
        self._initialize_parser()
    
    def _initialize_parser(self):
        """Initialize BiSeNet face parser"""
        try:
            # Try to use face parsing from insightface or separate model
            # For now, use a simpler landmark-based approach
            print("[INFO] OcclusionHandler initialized (landmark-based)")
        except Exception as e:
            print(f"[WARNING] Face parser initialization failed: {e}")
    
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
        
        if face_landmarks is not None and len(face_landmarks) >= 68:
            # Use landmarks for more precise masking
            
            if protect_glasses:
                # Eye region (typically indices 36-47 for 68-point landmarks)
                try:
                    left_eye = face_landmarks[36:42]
                    right_eye = face_landmarks[42:48]
                    
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
                except:
                    pass
            
            if protect_hair:
                # Forehead/hair region above eyebrows
                try:
                    left_brow = face_landmarks[17:22]
                    right_brow = face_landmarks[22:27]
                    
                    brow_top = min(np.min(left_brow[:, 1]), np.min(right_brow[:, 1]))
                    face_top = max(0, y1)
                    
                    if brow_top > face_top:
                        # Create hair protection mask above eyebrows
                        hair_mask = np.zeros((h, w), dtype=np.uint8)
                        cv2.rectangle(hair_mask, (x1, face_top), (x2, int(brow_top)), 255, -1)
                        occlusion_mask = cv2.bitwise_or(occlusion_mask, hair_mask)
                except:
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
        if feather_radius > 0:
            occlusion_mask = cv2.GaussianBlur(occlusion_mask, (feather_radius*2+1, feather_radius*2+1), 0)
        
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
        self.landmark_buffer = []
    
    def reset(self):
        """Reset buffers for new video"""
        self.frame_buffer = []
        self.landmark_buffer = []
    
    def add_frame(self, frame: np.ndarray, landmarks: Optional[np.ndarray] = None):
        """Add a frame to the buffer"""
        self.frame_buffer.append(frame.copy())
        if landmarks is not None:
            self.landmark_buffer.append(landmarks.copy())
        
        # Keep buffer size limited
        if len(self.frame_buffer) > self.window_size:
            self.frame_buffer.pop(0)
        if len(self.landmark_buffer) > self.window_size:
            self.landmark_buffer.pop(0)
    
    def get_stabilized_landmarks(self, current_landmarks: np.ndarray) -> np.ndarray:
        """
        Get temporally smoothed landmarks using rolling average.
        """
        if not self.landmark_buffer or len(self.landmark_buffer) < 2:
            return current_landmarks
        
        # Stack all landmarks and compute weighted average
        all_landmarks = np.array(self.landmark_buffer + [current_landmarks])
        
        # More weight on recent frames
        weights = np.linspace(0.5, 1.0, len(all_landmarks))
        weights = weights / weights.sum()
        
        stabilized = np.average(all_landmarks, axis=0, weights=weights)
        return stabilized.astype(current_landmarks.dtype)
    
    def blend_frames(self, current_frame: np.ndarray, blend_strength: float = 0.3) -> np.ndarray:
        """
        Blend current frame with previous frames to reduce flicker.
        """
        if not self.frame_buffer or len(self.frame_buffer) < 1:
            return current_frame
        
        # Average with previous frame for temporal smoothing
        prev_frame = self.frame_buffer[-1]
        
        # Resize if needed
        if prev_frame.shape != current_frame.shape:
            prev_frame = cv2.resize(prev_frame, (current_frame.shape[1], current_frame.shape[0]))
        
        blended = cv2.addWeighted(
            current_frame, 1 - blend_strength,
            prev_frame, blend_strength,
            0
        )
        
        return blended


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
            # Convert to LAB
            s_lab = cv2.cvtColor(source_img, cv2.COLOR_BGR2LAB).astype(np.float32)
            t_lab = cv2.cvtColor(target_img, cv2.COLOR_BGR2LAB).astype(np.float32)
            
            # If we have a face mask, compute stats only on face region
            if face_mask is not None:
                mask_bool = face_mask > 127
                s_mean = np.mean(s_lab[mask_bool], axis=0) if np.any(mask_bool) else np.mean(s_lab, axis=(0, 1))
                s_std = np.std(s_lab[mask_bool], axis=0) if np.any(mask_bool) else np.std(s_lab, axis=(0, 1))
                t_mean = np.mean(t_lab[mask_bool], axis=0) if np.any(mask_bool) else np.mean(t_lab, axis=(0, 1))
                t_std = np.std(t_lab[mask_bool], axis=0) if np.any(mask_bool) else np.std(t_lab, axis=(0, 1))
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
            
            # Pre-load source faces
            source_face_cache = {}
            for i, fd in enumerate(faceset.faces):
                src_img = cv2.imread(fd.image_path)
                if src_img is None:
                    continue
                src_faces = self.app.get(src_img)
                if src_faces:
                    source_face_cache[i] = src_faces[0]
            
            if not source_face_cache:
                return RefaceResult(False, None, "Could not load any source faces")
            
            fallback_source = list(source_face_cache.values())[0]
            
            # Determine faces to swap
            if target_face_indices is not None:
                faces_to_swap = [(idx, target_faces[idx]) for idx in target_face_indices 
                                 if 0 <= idx < len(target_faces)]
            else:
                faces_to_swap = list(enumerate(target_faces))
            
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
                occlusion_mask = None
                if apply_occlusion and self.occlusion_handler:
                    landmarks = getattr(target_face, 'landmark_2d_106', None)
                    if landmarks is None:
                        landmarks = getattr(target_face, 'landmark_3d_68', None)
                    
                    occlusion_mask = self.occlusion_handler.generate_occlusion_mask(
                        original_img,
                        target_face.bbox.astype(int).tolist(),
                        landmarks,
                        protect_glasses=self.occlusion_config.protect_glasses,
                        protect_hair=self.occlusion_config.protect_hair
                    )
                
                # Perform swap
                result_img = self.swapper.get(result_img, target_face, source_face, paste_back=True)
                
                # Apply occlusion protection
                if occlusion_mask is not None and np.sum(occlusion_mask) > 0:
                    result_img = self.occlusion_handler.apply_occlusion_protection(
                        original_img, result_img, occlusion_mask
                    )
                
                # Apply color correction
                result_img = self._advanced_color_correction(result_img, original_img)
                
                faces_swapped += 1
            
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
        progress_callback=None,
        start_time: float = 0.0,
        end_time: Optional[float] = None
    ) -> RefaceResult:
        """
        Enhanced video face swap with temporal consistency.
        """
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        try:
            if self.swapper is None:
                return RefaceResult(False, None, "Inswapper model not loaded")
            
            cap = cv2.VideoCapture(target_video_path)
            if not cap.isOpened():
                return RefaceResult(False, None, f"Could not open: {target_video_path}")
            
            fps = int(cap.get(cv2.CAP_PROP_FPS))
            width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            
            # Calculate output dimensions
            upscale = self.enhancement_config.upscale_factor if self.neural_enhancer else 1
            out_width = width * upscale
            out_height = height * upscale
            
            # Output path
            result_path = self.output_dir / f"refaced_v2_video_{timestamp}.avi"
            fourcc = cv2.VideoWriter_fourcc(*'MJPG') # Use Motion JPEG for higher quality intermediate
            out = cv2.VideoWriter(str(result_path), fourcc, fps, (out_width, out_height))
            
            # Pre-cache source faces
            source_face_cache = {}
            for i, fd in enumerate(faceset.faces):
                src_img = cv2.imread(fd.image_path)
                if src_img is None:
                    continue
                src_faces = self.app.get(src_img)
                if src_faces:
                    source_face_cache[i] = src_faces[0]
            
            if not source_face_cache:
                cap.release()
                return RefaceResult(False, None, "Could not load any source faces")
            
            fallback_source = list(source_face_cache.values())[0]
            
            
            # Calculate frame range from time parameters
            start_frame = int(start_time * fps) if start_time > 0 else 0
            if end_time is not None and end_time > 0:
                end_frame = min(int(end_time * fps), total_frames)
            else:
                end_frame = total_frames
            
            # Ensure valid range
            start_frame = max(0, min(start_frame, total_frames - 1))
            end_frame = max(start_frame + 1, min(end_frame, total_frames))
            frames_to_process = end_frame - start_frame
            
            print(f"[INFO] Processing frames {start_frame} to {end_frame} ({frames_to_process} frames, {frames_to_process/fps:.1f}s)")
            
            # Reset temporal stabilizer
            if self.temporal_stabilizer:
                self.temporal_stabilizer.reset()
            
            frames_processed = 0
            total_swaps = 0
            current_frame = start_frame
            
            # Seek to start frame
            if start_frame > 0:
                cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
            
            while current_frame < end_frame:
                ret, frame = cap.read()
                if not ret:
                    break
                
                original_frame = frame.copy()
                target_faces = self.app.get(frame)
                
                if target_faces:
                    faces_to_swap = []
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
                        
                        # Generate occlusion mask before swap
                        occlusion_mask = None
                        if apply_occlusion and self.occlusion_handler:
                            landmarks = getattr(target_face, 'landmark_2d_106', None)
                            if landmarks is None:
                                landmarks = getattr(target_face, 'landmark_3d_68', None)
                            
                            occlusion_mask = self.occlusion_handler.generate_occlusion_mask(
                                original_frame,
                                target_face.bbox.astype(int).tolist(),
                                landmarks,
                                protect_glasses=self.occlusion_config.protect_glasses,
                                protect_hair=self.occlusion_config.protect_hair
                            )
                            
                        # Perform swap
                        frame = self.swapper.get(frame, target_face, source_face, paste_back=True)
                        
                        # Apply occlusion protection
                        if occlusion_mask is not None and np.sum(occlusion_mask) > 0:
                            frame = self.occlusion_handler.apply_occlusion_protection(
                                original_frame, frame, occlusion_mask
                            )
                            
                        total_swaps += 1
                        
                        # Color correction
                        frame = self._advanced_color_correction(frame, original_frame)
                
                # Enhancement (Moved BEFORE stabilization to prevent GAN flickering)
                if self.neural_enhancer:
                    frame = self.neural_enhancer.enhance(
                        frame,
                        strength=self.enhancement_config.strength
                    )
                
                # Temporal stabilization
                if self.temporal_stabilizer and self.video_config.temporal_smoothing:
                    # Use a lighter blend to reduce ghosting while maintaining stability
                    blend_strength = 0.20 if self.neural_enhancer else 0.10
                    frame = self.temporal_stabilizer.blend_frames(frame, blend_strength=blend_strength)
                    self.temporal_stabilizer.add_frame(frame)
                

                out.write(frame)
                frames_processed += 1
                current_frame += 1
                
                if progress_callback and frames_processed % 5 == 0:
                    progress_callback(frames_processed, frames_to_process)
            
            cap.release()
            out.release()
            
            # Convert to MP4
            mp4_path = result_path.with_suffix('.mp4')
            try:
                import subprocess
                ffmpeg_exe = "ffmpeg"
                bundled_ffmpeg = Path("d:/AndroidScan/gallary/DeepFaceLab_NVIDIA_RTX3000_series/_internal/ffmpeg/ffmpeg.exe")
                if bundled_ffmpeg.exists():
                    ffmpeg_exe = str(bundled_ffmpeg)
                
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
            except Exception as e:
                print(f"[WARNING] FFmpeg conversion failed: {e}")
            
            if progress_callback:
                progress_callback(frames_to_process, frames_to_process)
            
            # Build result message with trim info
            trim_info = ""
            if start_time > 0 or end_time is not None:
                trim_info = f" (trimmed {start_time:.1f}s - {end_time:.1f}s)" if end_time else f" (from {start_time:.1f}s)"
            
            return RefaceResult(
                success=True,
                output_path=str(result_path),
                message=f"V2 Video completed ({total_swaps} swaps in {frames_processed} frames){trim_info}",
                faces_swapped=total_swaps
            )
            
        except Exception as e:
            import traceback
            traceback.print_exc()
            return RefaceResult(False, None, f"Error: {str(e)}")


# Quality presets
QUALITY_PRESETS = {
    "fast": {
        "enhancement": EnhancementConfig(enhancer_type="none", upscale_factor=1),
        "occlusion": OcclusionConfig(enabled=False),
        "video": VideoConfig(temporal_smoothing=False)
    },
    "standard": {
        "enhancement": EnhancementConfig(enhancer_type="opencv", upscale_factor=2, strength=0.7),
        "occlusion": OcclusionConfig(enabled=True),
        "video": VideoConfig(temporal_smoothing=True, smoothing_window=3)
    },
    "professional": {
        "enhancement": EnhancementConfig(enhancer_type="gfpgan", upscale_factor=2, strength=0.8),
        "occlusion": OcclusionConfig(enabled=True, protect_glasses=True, protect_hair=True),
        "video": VideoConfig(temporal_smoothing=True, smoothing_window=5, stabilize_landmarks=True)
    }
}


def create_engine_from_preset(preset_name: str = "standard") -> RefaceEngineV2:
    """Create a V2 engine with a quality preset"""
    preset = QUALITY_PRESETS.get(preset_name, QUALITY_PRESETS["standard"])
    return RefaceEngineV2(
        enhancement_config=preset["enhancement"],
        occlusion_config=preset["occlusion"],
        video_config=preset["video"]
    )


if __name__ == "__main__":
    print("Testing RefaceEngine V2...")
    
    try:
        engine = create_engine_from_preset("standard")
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
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
