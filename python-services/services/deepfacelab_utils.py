"""
DeepFaceLab Integration Utilities
Handles environment setup and path configuration for DeepFaceLab
"""

import os
import sys
from pathlib import Path
from typing import Optional, Dict


class DeepFaceLabEnvironment:
    """Manages DeepFaceLab environment setup"""
    
    def __init__(self, dfl_base_path: Optional[Path] = None):
        """
        Initialize DeepFaceLab environment.
        
        Args:
            dfl_base_path: Path to DeepFaceLab_NVIDIA_RTX3000_series folder.
                          If None, will try to find it relative to this file.
        """
        if dfl_base_path is None:
            # Try to find DeepFaceLab relative to this file
            base_path = Path(__file__).parent.parent.parent
            dfl_base_path = base_path / "DeepFaceLab_NVIDIA_RTX3000_series"
        
        self.dfl_base_path = Path(dfl_base_path).resolve()
        self.internal = self.dfl_base_path / "_internal"
        self.dfl_root = self.internal / "DeepFaceLab"
        self.python_exe = self.internal / "python-3.6.8" / "python.exe"
        self.workspace = self.dfl_base_path / "workspace"
        self.cuda_path = self.internal / "CUDA"
        self.cudnn_path = self.internal / "CUDNN"
        
        # Verify paths exist
        if not self.python_exe.exists():
            raise FileNotFoundError(
                f"DeepFaceLab Python not found at: {self.python_exe}\n"
                f"Please verify DeepFaceLab installation at: {self.dfl_base_path}"
            )
        
        if not self.dfl_root.exists():
            raise FileNotFoundError(
                f"DeepFaceLab root not found at: {self.dfl_root}"
            )
    
    def setup_environment(self) -> Dict[str, str]:
        """
        Set up environment variables for DeepFaceLab (like setenv.bat does).
        
        Returns:
            Dictionary of environment variables to use when calling DeepFaceLab
        """
        env = os.environ.copy()
        
        # Add CUDA and cuDNN to PATH (must be first for DLL loading)
        cuda_path_str = str(self.cuda_path)
        cudnn_path_str = str(self.cudnn_path)
        
        # Add Windows-specific cuDNN path based on Windows version
        if sys.platform == 'win32':
            # Try to detect Windows version (simplified - assumes Windows 10+)
            # DeepFaceLab checks for Win10.0 vs Win6.x
            # For simplicity, we'll add both potential paths
            cudnn_win10 = self.cudnn_path / "Win10.0"
            cudnn_win6 = self.cudnn_path / "Win6.x"
            
            path_parts = [cuda_path_str, cudnn_path_str]
            if cudnn_win10.exists():
                path_parts.append(str(cudnn_win10))
            elif cudnn_win6.exists():
                path_parts.append(str(cudnn_win6))
            
            # Prepend to PATH so CUDA DLLs are found first
            current_path = env.get('PATH', '')
            env['PATH'] = ';'.join(path_parts) + ';' + current_path
        
        # Set CUDA cache path (Windows)
        if sys.platform == 'win32':
            compute_cache_path = Path(env.get('APPDATA', '')) / 'NVIDIA' / 'ComputeCache_ALL'
            env['CUDA_CACHE_PATH'] = str(compute_cache_path)
            if not compute_cache_path.exists():
                compute_cache_path.mkdir(parents=True, exist_ok=True)
        
        # TensorFlow environment variables
        env['TF_CPP_MIN_LOG_LEVEL'] = '3'  # Suppress TensorFlow warnings
        env['CUDA_CACHE_MAXSIZE'] = '2147483647'
        env['TF_MIN_GPU_MULTIPROCESSOR_COUNT'] = '2'
        
        # DeepFaceLab specific
        env['DFL_ROOT'] = str(self.dfl_root)
        env['WORKSPACE'] = str(self.workspace)
        
        return env
    
    def verify_gpu_available(self) -> bool:
        """
        Verify that GPU is available and can be detected by TensorFlow.
        
        Returns:
            True if GPU is detected, False otherwise
        """
        import subprocess
        import tempfile
        
        test_script = """
import sys
import os
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'
os.environ['CUDA_CACHE_MAXSIZE'] = '2147483647'

try:
    import tensorflow as tf
    gpu_devices = [d for d in tf.config.list_physical_devices() if 'GPU' in d.name]
    sys.exit(0 if gpu_devices else 1)
except Exception as e:
    # Print error for debugging
    print(f"TensorFlow GPU check error: {e}", file=sys.stderr)
    sys.exit(1)
"""
        
        env = self.setup_environment()
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
            f.write(test_script)
            temp_script = f.name
        
        try:
            result = subprocess.run(
                [str(self.python_exe), temp_script],
                env=env,
                capture_output=True,
                text=True,
                timeout=15,  # Increased timeout
                cwd=str(self.dfl_root)
            )
            
            # Log if there are errors for debugging
            if result.returncode != 0 and result.stderr:
                # Only log if it's not just "no GPU found"
                if "error" in result.stderr.lower() or "exception" in result.stderr.lower():
                    print(f"[DEBUG] DeepFaceLab GPU check stderr: {result.stderr}")
            
            return result.returncode == 0
        except subprocess.TimeoutExpired:
            print("[WARNING] DeepFaceLab GPU check timed out")
            return False
        except Exception as e:
            print(f"[DEBUG] DeepFaceLab GPU check exception: {e}")
            return False
        finally:
            try:
                os.unlink(temp_script)
            except:
                pass
    
    def get_python_command(self) -> list:
        """Get the Python command to use for DeepFaceLab"""
        return [str(self.python_exe)]
    
    def get_main_script(self) -> Path:
        """Get the path to DeepFaceLab's main.py"""
        return self.dfl_root / "main.py"


def get_dfl_environment(dfl_path: Optional[Path] = None) -> DeepFaceLabEnvironment:
    """
    Convenience function to get a configured DeepFaceLab environment.
    
    Args:
        dfl_path: Optional path to DeepFaceLab installation
        
    Returns:
        Configured DeepFaceLabEnvironment instance
    """
    return DeepFaceLabEnvironment(dfl_path)

