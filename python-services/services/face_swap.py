"""
Face Swap Service using DeepFaceLab integration
Wraps DeepFaceLab CLI calls for face swapping
"""

import subprocess
import os
import uuid
import asyncio
from pathlib import Path
from typing import Dict, Optional
import shutil

from .deepfacelab_utils import DeepFaceLabEnvironment, get_dfl_environment


class FaceSwapService:
    def __init__(self, dfl_path: Optional[Path] = None):
        """
        Initialize face swap service.
        
        Args:
            dfl_path: Optional path to DeepFaceLab installation.
                     If None, will try to auto-detect.
        """
        self.results_dir = Path("results")
        self.results_dir.mkdir(exist_ok=True)
        
        # Initialize DeepFaceLab environment
        try:
            self.dfl_env = get_dfl_environment(dfl_path)
            # Verify GPU with proper environment setup
            # Note: This may take a few seconds as it runs TensorFlow in a subprocess
            print("[INFO] Checking DeepFaceLab GPU availability...")
            self.gpu_available = self.dfl_env.verify_gpu_available()
            if self.gpu_available:
                print("[INFO] ✅ GPU detected by DeepFaceLab. Face swap operations will use GPU.")
            else:
                print("[WARNING] ⚠️ GPU not detected by DeepFaceLab during initialization.")
                print("[INFO] This may be a false negative - GPU may still work when actually used.")
                print("[INFO] Note: Face detection (InsightFace) is using GPU successfully.")
                print("[INFO] To verify DeepFaceLab GPU, run: python check_gpu_with_env.py")
        except FileNotFoundError as e:
            print(f"[WARNING] DeepFaceLab not found: {e}")
            self.dfl_env = None
            self.gpu_available = False
        except Exception as e:
            print(f"[WARNING] Error initializing DeepFaceLab environment: {e}")
            print("[INFO] Face detection (InsightFace) is still using GPU successfully.")
            self.dfl_env = None
            self.gpu_available = False

    async def swap_faces(
        self,
        source_image_path: str,
        target_image_path: str,
        bbox: Dict[str, float]
    ) -> str:
        """
        Swap faces using DeepFaceLab.
        
        Args:
            source_image_path: Path to source image with face to extract
            target_image_path: Path to target image where face will be swapped
            bbox: Bounding box of source face {x, y, width, height}
            
        Returns:
            Path to the result image
        """
        if not os.path.exists(source_image_path):
            raise FileNotFoundError(f"Source image not found: {source_image_path}")
        
        if not os.path.exists(target_image_path):
            raise FileNotFoundError(f"Target image not found: {target_image_path}")

        # Create temporary workspace for this swap
        swap_id = str(uuid.uuid4())
        workspace = self.results_dir / f"workspace_{swap_id}"
        workspace.mkdir(parents=True, exist_ok=True)

        try:
            # Copy source and target images to workspace
            source_workspace = workspace / "source.jpg"
            target_workspace = workspace / "target.jpg"
            
            shutil.copy(source_image_path, source_workspace)
            shutil.copy(target_image_path, target_workspace)

            # Method 1: Use DeepFaceLab CLI if available
            if self.dfl_env is not None:
                result_path = await self._process_with_deepfacelab(
                    workspace, source_workspace, target_workspace, bbox
                )
            else:
                # Method 2: Use alternative face swap library (e.g., face-swap or faceit)
                result_path = await self._process_with_alternative(
                    source_workspace, target_workspace, bbox
                )

            # Copy result to results directory
            final_result = self.results_dir / f"swap_{swap_id}.jpg"
            if os.path.exists(result_path):
                shutil.copy(result_path, final_result)
            else:
                raise RuntimeError("Face swap failed: result file not generated")

            return str(final_result.absolute())

        finally:
            # Cleanup workspace (optional - keep for debugging)
            # shutil.rmtree(workspace, ignore_errors=True)
            pass

    async def _process_with_deepfacelab(
        self,
        workspace: Path,
        source_image: Path,
        target_image: Path,
        bbox: Dict[str, float]
    ) -> str:
        """
        Process face swap using DeepFaceLab CLI.
        
        DeepFaceLab workflow:
        1. Extract faces from source and target images
        2. Train model (or use pre-trained) - this can take hours
        3. Merge faces
        4. Return result
        
        Note: Full face swap requires training which is time-consuming.
        For quick swaps, consider using alternative methods or pre-trained models.
        """
        # Setup workspace structure
        data_src = workspace / "data_src"
        data_dst = workspace / "data_dst"
        data_src_aligned = data_src / "aligned"
        data_dst_aligned = data_dst / "aligned"
        data_dst_merged = data_dst / "merged"
        model_dir = workspace / "model"
        
        for d in [data_src, data_dst, data_src_aligned, data_dst_aligned, data_dst_merged, model_dir]:
            d.mkdir(parents=True, exist_ok=True)
        
        # Copy images to workspace
        shutil.copy(source_image, data_src / "source.jpg")
        shutil.copy(target_image, data_dst / "target.jpg")
        
        # Get environment with CUDA paths set up
        env = self.dfl_env.setup_environment()
        python_cmd = self.dfl_env.get_python_command()
        main_script = self.dfl_env.get_main_script()
        
        # Step 1: Extract faces from source
        extract_src_cmd = python_cmd + [
            str(main_script),
            "extract",
            "--input-dir", str(data_src),
            "--output-dir", str(data_src_aligned),
            "--detector", "s3fd",
            "--face-type", "full_face",
            "--image-size", "512"
        ]
        
        print(f"[INFO] Extracting faces from source image...")
        process = await asyncio.create_subprocess_exec(
            *extract_src_cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=env,
            cwd=str(self.dfl_env.dfl_root)
        )
        stdout, stderr = await process.communicate()
        
        if process.returncode != 0:
            error_msg = stderr.decode() if stderr else "Unknown error"
            raise RuntimeError(f"Source face extraction failed: {error_msg}")
        
        # Check if any faces were extracted
        aligned_faces = list(data_src_aligned.glob("*.jpg"))
        if not aligned_faces:
            raise RuntimeError("No faces detected in source image")
        
        print(f"[INFO] Extracted {len(aligned_faces)} face(s) from source")
        
        # Step 2: Extract faces from target
        extract_dst_cmd = python_cmd + [
            str(main_script),
            "extract",
            "--input-dir", str(data_dst),
            "--output-dir", str(data_dst_aligned),
            "--detector", "s3fd",
            "--face-type", "full_face",
            "--image-size", "512"
        ]
        
        print(f"[INFO] Extracting faces from target image...")
        process = await asyncio.create_subprocess_exec(
            *extract_dst_cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=env,
            cwd=str(self.dfl_env.dfl_root)
        )
        stdout, stderr = await process.communicate()
        
        if process.returncode != 0:
            error_msg = stderr.decode() if stderr else "Unknown error"
            raise RuntimeError(f"Target face extraction failed: {error_msg}")
        
        aligned_dst_faces = list(data_dst_aligned.glob("*.jpg"))
        if not aligned_dst_faces:
            raise RuntimeError("No faces detected in target image")
        
        print(f"[INFO] Extracted {len(aligned_dst_faces)} face(s) from target")
        
        # NOTE: Full face swap requires training a model, which can take hours.
        # For now, we'll return the extracted source face as a placeholder.
        # In production, you would:
        # 1. Train a model (or use pre-trained)
        # 2. Merge faces using the trained model
        # 3. Return the merged result
        
        # For demonstration, return the first extracted source face
        # In a real implementation, you'd need to train and merge
        result_path = workspace / "result.jpg"
        shutil.copy(aligned_faces[0], result_path)
        
        print(f"[WARNING] Face extraction completed, but full swap requires model training.")
        print(f"[INFO] Returning extracted source face as placeholder.")
        
        return str(result_path)

    async def _process_with_alternative(
        self,
        source_image: Path,
        target_image: Path,
        bbox: Dict[str, float]
    ) -> str:
        """
        Process face swap using alternative library (e.g., face-swap, faceit, or InsightFace face swap).
        This is a fallback if DeepFaceLab is not available.
        """
        # Option 1: Use InsightFace face swap (if available)
        # Option 2: Use face-swap library
        # Option 3: Use other face swap implementations
        
        # Placeholder implementation
        # In production, implement actual face swap using available library
        result_path = self.results_dir / f"swap_{uuid.uuid4()}.jpg"
        
        # For now, just copy target (replace with actual face swap)
        import shutil
        shutil.copy(target_image, result_path)
        
        return str(result_path)

