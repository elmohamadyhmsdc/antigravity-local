"""
Antigravity Local - Reface Engine
Face swapping using InsightFace with faceset building and angle matching
"""

import os
import sys
import shutil
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from datetime import datetime

import cv2
import numpy as np
from dataclasses import dataclass, field

# Make stdout/stderr tolerant of emoji on non-UTF-8 consoles (cp1252 on Windows
# would otherwise crash engine init at the first emoji print). Affects the whole
# process, so it also covers V2/V3 and job_manager which import this module.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# Add ALL NVIDIA DLL paths for ONNX Runtime CUDA support
from cuda_dll_dirs import add_nvidia_dll_dirs
add_nvidia_dll_dirs()

import insightface
from insightface.app import FaceAnalysis


@dataclass
class RefaceResult:
    """Result of a reface operation"""
    success: bool
    output_path: Optional[str]
    message: str
    faces_swapped: int = 0


@dataclass
class FaceData:
    """Data for a single face in a faceset"""
    image_path: str
    embedding: np.ndarray
    pose: Tuple[float, float, float]  # yaw, pitch, roll
    bbox: List[int]
    quality: float = 0.0


class FaceEnhancer:
    """Face enhancement using OpenCV techniques."""
    
    def __init__(self, upscale_factor: int = 2):
        self.upscale_factor = upscale_factor
        print(f"[INFO] Using OpenCV enhancer with {upscale_factor}x upscale")
    
    def enhance(self, image: np.ndarray) -> np.ndarray:
        """Enhance image using OpenCV techniques (Unsharp Mask + Bilateral)."""
        try:
            h, w = image.shape[:2]
            new_h, new_w = h * self.upscale_factor, w * self.upscale_factor
            
            # 1. High-quality resize
            upscaled = cv2.resize(image, (new_w, new_h), interpolation=cv2.INTER_LANCZOS4)
            
            # 2. Denoise slightly to avoid enhancing artifacts
            denoised = cv2.fastNlMeansDenoisingColored(upscaled, None, 3, 3, 7, 21)
            
            # 3. Unsharp Masking (USM) for realistic detail enhancement
            gaussian = cv2.GaussianBlur(denoised, (0, 0), 2.0)
            unsharp_image = cv2.addWeighted(denoised, 1.5, gaussian, -0.5, 0)
            
            # 4. Slight saturation boost for vibrancy
            hsv = cv2.cvtColor(unsharp_image, cv2.COLOR_BGR2HSV)
            hsv[..., 1] = cv2.multiply(hsv[..., 1], 1.1)
            enhanced = cv2.cvtColor(hsv, cv2.COLOR_HSV2BGR)
            
            return enhanced
        except Exception as e:
            print(f"[WARNING] Enhancement failed: {e}")
            return image
            print(f"[WARNING] Enhancement failed: {e}")
            return image


class Faceset:
    """A collection of faces from a person with different angles and expressions."""
    
    def __init__(self, name: str = "unnamed"):
        self.name = name
        self.faces: List[FaceData] = []
        self.created_at = datetime.now()
    
    def add_face(self, face_data: FaceData):
        """Add a face to the faceset."""
        self.faces.append(face_data)
    
    def get_best_match(self, target_pose: Tuple[float, float, float]) -> Optional[FaceData]:
        """
        Find the source face that best matches the target pose.
        Uses Euclidean distance between pose vectors.
        """
        if not self.faces:
            return None
        
        target_yaw, target_pitch, target_roll = target_pose
        
        best_face = None
        best_distance = float('inf')
        
        for face in self.faces:
            src_yaw, src_pitch, src_roll = face.pose
            
            # Calculate pose distance
            distance = np.sqrt(
                (target_yaw - src_yaw) ** 2 +
                (target_pitch - src_pitch) ** 2 +
                (target_roll - src_roll) ** 2
            )
            
            if distance < best_distance:
                best_distance = distance
                best_face = face
        
        return best_face
    
    def get_pose_coverage(self) -> Dict[str, int]:
        """Get coverage of different poses in the faceset (legacy 5-category)."""
        coverage = {
            'front': 0,      # yaw close to 0
            'left': 0,       # yaw < -20
            'right': 0,      # yaw > 20
            'up': 0,         # pitch > 15
            'down': 0,       # pitch < -15
        }
        
        for face in self.faces:
            yaw, pitch, roll = face.pose
            
            if abs(yaw) < 20:
                coverage['front'] += 1
            if yaw < -20:
                coverage['left'] += 1
            if yaw > 20:
                coverage['right'] += 1
            if pitch > 15:
                coverage['up'] += 1
            if pitch < -15:
                coverage['down'] += 1
        
        return coverage
    
    @staticmethod
    def get_angle_category(pose: Tuple[float, float, float]) -> str:
        """
        Categorize a pose into one of the 7 angle buckets for 3D face datasets.
        
        Categories:
        - front: Direct frontal view
        - left_45: 45-degree left turn
        - right_45: 45-degree right turn  
        - left_90: Full left profile
        - right_90: Full right profile
        - up: Looking up
        - down: Looking down
        """
        yaw, pitch, roll = pose
        
        # Vertical categories take priority for extreme pitch
        if pitch > 15:
            return 'up'
        elif pitch < -15:
            return 'down'
        
        # Horizontal categories based on yaw
        if abs(yaw) < 15:
            return 'front'
        elif -60 < yaw <= -30:
            return 'left_45'
        elif 30 <= yaw < 60:
            return 'right_45'
        elif yaw <= -60:
            return 'left_90'
        elif yaw >= 60:
            return 'right_90'
        elif -30 < yaw < 0:
            return 'left_45'
        elif 0 < yaw < 30:
            return 'right_45'
        
        return 'front'
    
    def get_detailed_coverage(self) -> Dict[str, Dict]:
        """
        Get detailed 7-point coverage with quality scores per angle.
        
        Returns dict with keys: front, left_45, right_45, left_90, right_90, up, down
        Each value contains: count, best_quality, required, faces (list of indices)
        """
        coverage = {
            'front': {'count': 0, 'best_quality': 0.0, 'required': True, 'priority': 'critical', 'faces': []},
            'left_45': {'count': 0, 'best_quality': 0.0, 'required': True, 'priority': 'important', 'faces': []},
            'right_45': {'count': 0, 'best_quality': 0.0, 'required': True, 'priority': 'important', 'faces': []},
            'left_90': {'count': 0, 'best_quality': 0.0, 'required': False, 'priority': 'optional', 'faces': []},
            'right_90': {'count': 0, 'best_quality': 0.0, 'required': False, 'priority': 'optional', 'faces': []},
            'up': {'count': 0, 'best_quality': 0.0, 'required': True, 'priority': 'important', 'faces': []},
            'down': {'count': 0, 'best_quality': 0.0, 'required': False, 'priority': 'optional', 'faces': []},
        }
        
        for idx, face in enumerate(self.faces):
            category = self.get_angle_category(face.pose)
            coverage[category]['count'] += 1
            coverage[category]['best_quality'] = max(
                coverage[category]['best_quality'], 
                face.quality
            )
            coverage[category]['faces'].append(idx)
        
        return coverage
    
    def get_missing_angles(self) -> List[str]:
        """Get list of required angles that are missing (most important first)."""
        coverage = self.get_detailed_coverage()
        missing = []
        priority_order = ['front', 'left_45', 'right_45', 'up', 'left_90', 'right_90', 'down']
        for angle in priority_order:
            if coverage[angle]['count'] == 0 and coverage[angle]['required']:
                missing.append(angle)
        return missing
    
    def get_all_missing_angles(self) -> List[str]:
        """Get all missing angles including optional ones."""
        coverage = self.get_detailed_coverage()
        priority_order = ['front', 'left_45', 'right_45', 'up', 'left_90', 'right_90', 'down']
        return [angle for angle in priority_order if coverage[angle]['count'] == 0]
    
    def get_quality_score(self) -> float:
        """
        Calculate overall faceset quality score (0-100).
        
        Weights:
        - Front: 30 points (most critical)
        - Left/Right 45: 15 points each
        - Up: 10 points
        - Left/Right 90: 10 points each
        - Down: 5 points
        """
        coverage = self.get_detailed_coverage()
        score = 0.0
        weights = {
            'front': 30, 'left_45': 15, 'right_45': 15,
            'up': 10, 'down': 5, 'left_90': 10, 'right_90': 10,
        }
        
        for angle, data in coverage.items():
            weight = weights.get(angle, 5)
            if data['count'] > 0:
                quality_factor = min(1.0, data['best_quality']) if data['best_quality'] > 0 else 0.7
                count_bonus = min(1.0, data['count'] / 5) * 0.2
                score += weight * (0.8 * quality_factor + count_bonus)
            elif not data['required']:
                score += weight * 0.3
        
        return min(100.0, score)
    
    def get_quality_grade(self) -> str:
        """Get letter grade for faceset quality."""
        score = self.get_quality_score()
        if score >= 90: return 'A+'
        elif score >= 80: return 'A'
        elif score >= 70: return 'B'
        elif score >= 60: return 'C'
        elif score >= 50: return 'D'
        else: return 'F'
    
    def get_suggestions(self) -> List[str]:
        """Get actionable suggestions to improve the faceset."""
        suggestions = []
        coverage = self.get_detailed_coverage()
        missing = self.get_missing_angles()
        
        if 'front' in missing:
            suggestions.append("🔴 CRITICAL: Add frontal face photos (looking directly at camera)")
        if 'left_45' in missing or 'right_45' in missing:
            suggestions.append("🟡 Add 45-degree angle shots (head turned slightly left/right)")
        if 'up' in missing:
            suggestions.append("🟡 Add upward-looking photos (chin tilted up)")
        
        for angle, data in coverage.items():
            if data['count'] > 0 and data['best_quality'] < 0.7:
                suggestions.append(f"⚠️ Low quality detected for {angle.replace('_', ' ')} - try better lighting")
        
        optional_missing = [a for a in self.get_all_missing_angles() if not coverage[a]['required']]
        if optional_missing and len(missing) == 0:
            angle_names = [a.replace('_', ' ') for a in optional_missing]
            suggestions.append(f"💡 For even better results, add: {', '.join(angle_names)}")
        
        if not suggestions:
            suggestions.append("✅ Great coverage! Your faceset is ready for professional results.")
        
        return suggestions



    def save(self, path: Path):
        """Save faceset data to disk."""
        import pickle
        # Convert FaceData objects to dicts to avoid pickling class identity issues
        faces_data = []
        for face in self.faces:
            faces_data.append({
                'image_path': face.image_path,
                'embedding': face.embedding,
                'pose': face.pose,
                'bbox': face.bbox,
                'quality': face.quality
            })
        
        data = {
            'name': self.name,
            'faces': faces_data,
            'created_at': self.created_at
        }
        with open(path, 'wb') as f:
            pickle.dump(data, f)
            
    @staticmethod
    def load(path: Path) -> 'Faceset':
        """Load faceset from disk."""
        import pickle
        with open(path, 'rb') as f:
            data = pickle.load(f)
            
        # Reconstruct object
        faceset = Faceset(name=data['name'])
        faceset.created_at = data.get('created_at', datetime.now())
        
        # Reconstruct FaceData objects from dicts
        for face_dict in data['faces']:
            faceset.faces.append(FaceData(
                image_path=face_dict['image_path'],
                embedding=face_dict['embedding'],
                pose=face_dict['pose'],
                bbox=face_dict['bbox'],
                quality=face_dict.get('quality', 0.0)
            ))
        
        return faceset


class RefaceEngine:
    """
    Face swapping engine using InsightFace.
    Supports faceset building and angle matching for better quality.
    """
    
    def __init__(self, output_dir: str = None, enable_enhancement: bool = True, upscale: int = 2):
        self.output_dir = Path(output_dir) if output_dir else Path(__file__).parent / "reface_output"
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # Faceset directory
        self.faceset_dir = Path(__file__).parent / "facesets"
        self.faceset_dir.mkdir(parents=True, exist_ok=True)
        
        # Initialize face analyzer
        print("[INFO] Initializing InsightFace...")
        
        # Define providers (Prioritize CUDA)
        self.providers = ['CUDAExecutionProvider', 'CPUExecutionProvider']
        
        self.app = FaceAnalysis(name='buffalo_l', providers=self.providers)
        self.app.prepare(ctx_id=0, det_size=(640, 640))
        
        # Load inswapper model
        self.swapper = None
        model_path = Path(__file__).parent / "models" / "inswapper_128.onnx"
        
        if model_path.exists():
            print(f"[INFO] Loading inswapper model from {model_path}")
            self.swapper = insightface.model_zoo.get_model(str(model_path), providers=self.providers)
        else:
            print("[INFO] Looking for inswapper model...")
            try:
                self.swapper = insightface.model_zoo.get_model('inswapper_128.onnx', providers=self.providers)
            except Exception as e:
                print(f"[WARNING] Could not load inswapper model: {e}")

        # Check for GPU
        import onnxruntime as ort
        providers = ort.get_available_providers()
        print(f"[INFO] Available ONNX Providers: {providers}")
        if 'CUDAExecutionProvider' in providers:
            print("🚀 GPU Accelaration Enabled (CUDA)")
        else:
            print("🐢 Running on CPU (install onnxruntime-gpu for speed)")
        
        # Initialize enhancer
        self.enhancer = None
        self.upscale = upscale
        if enable_enhancement:
            self.enhancer = FaceEnhancer(upscale_factor=upscale)
        
        print("[INFO] RefaceEngine initialized")
    
    
    def _apply_color_correction(self, source_img: np.ndarray, target_img: np.ndarray) -> np.ndarray:
        """
        Apply global color correction to match target image statistics.
        Uses simple channel-wise mean/std transfer in LAB color space.
        """
        try:
            # Convert to LAB color space
            s_lab = cv2.cvtColor(source_img, cv2.COLOR_BGR2LAB).astype("float32")
            t_lab = cv2.cvtColor(target_img, cv2.COLOR_BGR2LAB).astype("float32")
            
            # Compute statistics
            s_mean, s_std = cv2.meanStdDev(s_lab)
            t_mean, t_std = cv2.meanStdDev(t_lab)
            
            s_mean = s_mean.flatten()
            s_std = s_std.flatten()
            t_mean = t_mean.flatten()
            t_std = t_std.flatten()
            
            # Apply color transfer
            res_lab = s_lab.copy()
            for i in range(3):
                res_lab[:,:,i] = (s_lab[:,:,i] - s_mean[i]) * (t_std[i] / (s_std[i] + 1e-6)) + t_mean[i]
            
            # Clip and convert back
            res_lab = np.clip(res_lab, 0, 255).astype("uint8")
            result = cv2.cvtColor(res_lab, cv2.COLOR_LAB2BGR)
            return result
        except Exception as e:
            return source_img
            
    def _get_face_pose(self, face) -> Tuple[float, float, float]:
        """Extract yaw, pitch, roll from face landmarks."""
        try:
            if hasattr(face, 'pose'):
                return tuple(face.pose[:3])
            
            # Estimate from landmarks if pose not available
            if face.landmark_2d_106 is not None:
                landmarks = face.landmark_2d_106
                # Simple pose estimation from eye and nose positions
                left_eye = np.mean(landmarks[33:42], axis=0)
                right_eye = np.mean(landmarks[87:96], axis=0)
                nose = landmarks[86]
                
                # Yaw from eye positions
                eye_center = (left_eye + right_eye) / 2
                yaw = (nose[0] - eye_center[0]) / (right_eye[0] - left_eye[0] + 1e-6) * 45
                
                # Pitch from nose position relative to eyes
                pitch = (nose[1] - eye_center[1]) / (right_eye[0] - left_eye[0] + 1e-6) * 30
                
                return (float(yaw), float(pitch), 0.0)
            
            return (0.0, 0.0, 0.0)
        except:
            return (0.0, 0.0, 0.0)
    
    def build_faceset_from_media(
        self,
        media_paths: List[str],
        faceset_name: str = "custom",
        progress_callback=None
    ) -> Faceset:
        """
        Build a faceset from multiple media files.
        
        Args:
            media_paths: List of image/video paths
            faceset_name: Name for the faceset
            progress_callback: Optional callback(current, total)
            
        Returns:
            Faceset with extracted faces
        """
        faceset = Faceset(name=faceset_name)
        faceset_path = self.faceset_dir / faceset_name
        faceset_path.mkdir(parents=True, exist_ok=True)
        
        face_count = 0
        total_media = len(media_paths)
        
        for media_idx, media_path in enumerate(media_paths):
            print(f"[INFO] Processing {media_idx + 1}/{total_media}: {Path(media_path).name}")
            
            ext = Path(media_path).suffix.lower()
            is_video = ext in ['.mp4', '.avi', '.mkv', '.mov', '.wmv', '.webm']
            
            if is_video:
                # Extract frames from video
                cap = cv2.VideoCapture(media_path)
                fps = int(cap.get(cv2.CAP_PROP_FPS))
                total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
                
                # Sample every few frames
                frame_skip = max(1, fps // 3)  # ~3 faces per second
                
                frame_num = 0
                while True:
                    ret, frame = cap.read()
                    if not ret:
                        break
                    
                    if frame_num % frame_skip == 0:
                        faces = self.app.get(frame)
                        for i, face in enumerate(faces):
                            bbox = face.bbox.astype(int)
                            
                            # Save FULL FRAME (not cropped) so face can be detected later
                            frame_path = faceset_path / f"frame_{face_count:04d}.jpg"
                            cv2.imwrite(str(frame_path), frame)
                            
                            # Get pose
                            pose = self._get_face_pose(face)
                            
                            # Add to faceset - store full frame path
                            faceset.add_face(FaceData(
                                image_path=str(frame_path),
                                embedding=face.embedding,
                                pose=pose,
                                bbox=bbox.tolist(),
                                quality=getattr(face, 'det_score', 0.0)
                            ))
                            face_count += 1
                            
                            # Only capture first face per frame for efficiency
                            break
                    
                    frame_num += 1
                
                cap.release()
            else:
                # Process image - use original image path directly
                frame = cv2.imread(media_path)
                if frame is None:
                    continue
                
                faces = self.app.get(frame)
                if faces:
                    # Take first face from each image
                    face = faces[0]
                    bbox = face.bbox.astype(int)
                    pose = self._get_face_pose(face)
                    
                    faceset.add_face(FaceData(
                        image_path=media_path,  # Use original image path
                        embedding=face.embedding,
                        pose=pose,
                        bbox=bbox.tolist(),
                        quality=getattr(face, 'det_score', 0.0)
                    ))
                    face_count += 1
            
            if progress_callback:
                progress_callback(media_idx + 1, total_media)
        
        print(f"[INFO] Built faceset with {len(faceset.faces)} faces")
        coverage = faceset.get_pose_coverage()
        print(f"[INFO] Coverage: {coverage}")
        
        return faceset
    
    def list_facesets(self) -> List[str]:
        """List available faceset names."""
        if not self.faceset_dir.exists():
            return []
        return sorted([f.stem for f in self.faceset_dir.glob("*.pkl")])
        
    def load_faceset_by_name(self, name: str) -> Optional[Faceset]:
        """Load a faceset by its name."""
        path = self.faceset_dir / f"{name}.pkl"
        if path.exists():
            try:
                return Faceset.load(path)
            except Exception as e:
                print(f"[ERROR] Failed to load faceset {name}: {e}")
                return None
        return None
        
    def save_faceset(self, faceset: Faceset):
        """Save a faceset to the facesets directory."""
        path = self.faceset_dir / f"{faceset.name}.pkl"
        faceset.save(path)
        print(f"[INFO] Saved faceset '{faceset.name}' to {path}")

    def reface_with_faceset(
        self,
        target_image_path: str,
        faceset: Faceset,
        target_face_indices: Optional[List[int]] = None,
        use_angle_matching: bool = True
    ) -> RefaceResult:
        """
        Swap faces in an image using a faceset with angle matching.
        
        Args:
            target_image_path: Path to image to reface
            faceset: Faceset with source faces
            target_face_indices: List of face indices to replace. If None, swaps ALL faces.
            use_angle_matching: Whether to match source face angle to target
            
        Returns:
            RefaceResult with output path
        """
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        try:
            target_img = cv2.imread(target_image_path)
            if target_img is None:
                return RefaceResult(False, None, f"Could not load: {target_image_path}")
            
            target_faces = self.app.get(target_img)
            if not target_faces:
                return RefaceResult(False, None, "No faces detected in target")
            
            if self.swapper is None:
                return RefaceResult(False, None, "Inswapper model not loaded")
            
            if not faceset.faces:
                return RefaceResult(False, None, "Faceset is empty")
            
            result_img = target_img.copy()
            faces_swapped = 0
            
            # Pre-load all source faces from faceset
            source_face_cache = {}
            for i, fd in enumerate(faceset.faces):
                # Try to load and detect face from the stored image
                src_img = cv2.imread(fd.image_path)
                if src_img is None:
                    continue
                src_faces = self.app.get(src_img)
                if src_faces:
                    source_face_cache[i] = src_faces[0]
            
            if not source_face_cache:
                return RefaceResult(False, None, "Could not load any source faces from faceset")
            
            # Get a fallback source face (first available)
            fallback_source = list(source_face_cache.values())[0]
            
            # Determine which target faces to swap
            if target_face_indices is not None:
                # Swap only selected indices
                faces_to_swap = []
                for idx in target_face_indices:
                    if 0 <= idx < len(target_faces):
                        faces_to_swap.append((idx, target_faces[idx]))
            else:
                # Swap ALL faces
                faces_to_swap = list(enumerate(target_faces))
            
            for idx, target_face in faces_to_swap:
                source_face = None
                
                if use_angle_matching and len(source_face_cache) > 1:
                    # Get target pose and find best match
                    target_pose = self._get_face_pose(target_face)
                    source_data = faceset.get_best_match(target_pose)
                    
                    if source_data:
                        # Find the cached face for this source_data
                        for i, fd in enumerate(faceset.faces):
                            if fd.image_path == source_data.image_path and i in source_face_cache:
                                source_face = source_face_cache[i]
                                break
                
                # Fallback to first source face if angle matching failed
                if source_face is None:
                    source_face = fallback_source
                
                # Perform swap
                result_img = self.swapper.get(result_img, target_face, source_face, paste_back=True)
                faces_swapped += 1
            
            # Enhance
            if self.enhancer:
                result_img = self.enhancer.enhance(result_img)
            
            # Save result
            result_path = self.output_dir / f"refaced_{timestamp}.jpg"
            cv2.imwrite(str(result_path), result_img, [cv2.IMWRITE_JPEG_QUALITY, 95])
            
            return RefaceResult(
                success=True,
                output_path=str(result_path),
                message=f"Face swap completed ({faces_swapped} faces swapped)",
                faces_swapped=faces_swapped
            )
            
        except Exception as e:
            import traceback
            traceback.print_exc()
            return RefaceResult(False, None, f"Error: {str(e)}")
    
    def reface_video_with_faceset(
        self,
        target_video_path: str,
        faceset: Faceset,
        target_face_indices: Optional[List[int]] = None,
        use_angle_matching: bool = True,
        progress_callback=None,
        start_time: float = 0.0,
        end_time: Optional[float] = None
    ) -> RefaceResult:
        """
        Swap faces in a video using a faceset with angle matching.
        
        Args:
            target_video_path: Path to video to reface
            faceset: Faceset with source faces
            target_face_indices: List of face indices to replace. If None, swaps ALL faces.
            use_angle_matching: Whether to match source face angle to target
            progress_callback: Optional callback(current, total)
            start_time: Start time in seconds (default: 0.0)
            end_time: End time in seconds (default: None = end of video)
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
            
            out_width = width * self.upscale if self.enhancer else width
            out_height = height * self.upscale if self.enhancer else height
            
            # Use AVI with XVID codec for better compatibility
            result_path = self.output_dir / f"refaced_video_{timestamp}.avi"
            fourcc = cv2.VideoWriter_fourcc(*'XVID')
            out = cv2.VideoWriter(str(result_path), fourcc, fps, (out_width, out_height))
            
            # Pre-cache source faces for efficiency
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
            
            # Seek to start frame
            if start_frame > 0:
                cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
            
            frames_processed = 0
            total_swaps = 0
            current_frame = start_frame
            
            while current_frame < end_frame:
                ret, frame = cap.read()
                if not ret:
                    break
                
                target_faces = self.app.get(frame)

                
                if target_faces:
                    # Determine which faces to swap in this frame
                    faces_to_swap = []
                    if target_face_indices is not None:
                        # Only swap specific indices if they exist in this frame
                        # Note: Indices might not be stable across frames but this is best effort for video
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
                        
                        # Swap
                        frame = self.swapper.get(frame, target_face, source_face, paste_back=True)
                        total_swaps += 1
                        
                        # Post-swap Color Correction
                        try:
                            bbox = target_face.bbox.astype(int)
                            x1, y1, x2, y2 = bbox
                            x1, y1 = max(0, x1), max(0, y1)
                            x2, y2 = min(width, x2), min(height, y2)
                            
                            if x2 > x1 and y2 > y1:
                                # Need original frame crop ref? 
                                # Wait, 'frame' is already modified by swapper.
                                # To do this right, we needed a copy of original 'frame'.
                                # But copying every frame is expensive.
                                # Workaround: We can't easily get original pixels here efficiently without copying.
                                # Actually, for video, simple color correction might cause flickering if not stable.
                                # Let's skip it for video for performance, OR implement it carefully.
                                # To do it right:
                                # original_crop = frame_copy[y1:y2...]
                                pass
                        except:
                            pass
                
                if self.enhancer:
                    frame = self.enhancer.enhance(frame)
                
                out.write(frame)
                frames_processed += 1
                current_frame += 1
                
                if progress_callback and frames_processed % 5 == 0:
                    progress_callback(frames_processed, frames_to_process)
            
            cap.release()
            out.release()
            
            # Convert to browser-compatible MP4 using FFmpeg
            mp4_path = result_path.with_suffix('.mp4')
            try:
                import subprocess
                
                # Locate FFmpeg
                ffmpeg_exe = "ffmpeg"
                bundled_ffmpeg = Path("d:/AndroidScan/gallary/DeepFaceLab_NVIDIA_RTX3000_series/_internal/ffmpeg/ffmpeg.exe")
                if bundled_ffmpeg.exists():
                    ffmpeg_exe = str(bundled_ffmpeg)
                
                ffmpeg_cmd = [
                    ffmpeg_exe, '-y',
                    '-i', str(result_path),
                    '-c:v', 'libx264',
                    '-preset', 'fast',
                    '-crf', '23',
                    '-pix_fmt', 'yuv420p',
                    str(mp4_path)
                ]
                subprocess.run(ffmpeg_cmd, capture_output=True, check=True)
                
                # Delete AVI, use MP4
                result_path.unlink(missing_ok=True)
                result_path = mp4_path
                print(f"[INFO] Converted to browser-compatible MP4: {mp4_path}")
            except Exception as e:
                print(f"[WARNING] FFmpeg conversion failed: {e}")
                print("[INFO] Download the AVI file and convert manually, or install FFmpeg")
            
            if progress_callback:
                progress_callback(frames_to_process, frames_to_process)
            
            # Build result message with trim info
            trim_info = ""
            if start_time > 0 or end_time is not None:
                trim_info = f" (trimmed {start_time:.1f}s - {end_time:.1f}s)" if end_time else f" (from {start_time:.1f}s)"
            
            return RefaceResult(
                success=True,
                output_path=str(result_path),
                message=f"Video completed ({total_swaps} swaps in {frames_processed} frames){trim_info}",
                faces_swapped=total_swaps
            )
            
        except Exception as e:
            import traceback
            traceback.print_exc()
            return RefaceResult(False, None, f"Error: {str(e)}")
    
    # Keep old methods for backward compatibility
    def reface_image(
        self,
        target_image_path: str,
        source_person_faces: List[str],
        target_face_index: int = -1,
        enhance: bool = True
    ) -> RefaceResult:
        """Legacy method - builds quick faceset from provided faces."""
        faceset = Faceset(name="temp")
        
        for face_path in source_person_faces:
            img = cv2.imread(face_path)
            if img is None:
                continue
            faces = self.app.get(img)
            if faces:
                faceset.add_face(FaceData(
                    image_path=face_path,
                    embedding=faces[0].embedding,
                    pose=self._get_face_pose(faces[0]),
                    bbox=faces[0].bbox.astype(int).tolist()
                ))
        
        return self.reface_with_faceset(target_image_path, faceset, target_face_index, use_angle_matching=True)
    
    def reface_video(
        self,
        target_video_path: str,
        source_person_faces: List[str],
        target_face_index: int = -1,
        progress_callback=None,
        enhance: bool = True
    ) -> RefaceResult:
        """Legacy method - builds quick faceset from provided faces."""
        faceset = Faceset(name="temp")
        
        for face_path in source_person_faces:
            img = cv2.imread(face_path)
            if img is None:
                continue
            faces = self.app.get(img)
            if faces:
                faceset.add_face(FaceData(
                    image_path=face_path,
                    embedding=faces[0].embedding,
                    pose=self._get_face_pose(faces[0]),
                    bbox=faces[0].bbox.astype(int).tolist()
                ))
        
        return self.reface_video_with_faceset(target_video_path, faceset, target_face_index, True, progress_callback)


if __name__ == "__main__":
    print("Testing RefaceEngine...")
    
    try:
        engine = RefaceEngine()
        print("✅ RefaceEngine initialized!")
        
        if engine.swapper:
            print("✅ Inswapper model loaded")
        else:
            print("⚠️ Download inswapper_128.onnx to models/ folder")
        
        print(f"✅ {engine.upscale}x enhancement enabled")
        print(f"✅ Faceset directory: {engine.faceset_dir}")
    except Exception as e:
        print(f"❌ Error: {e}")
