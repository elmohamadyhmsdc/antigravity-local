"""
GPU Check with DeepFaceLab Environment Setup
This version sets up the environment like setenv.bat does
"""

import sys
import os
import subprocess
from pathlib import Path

def setup_dfl_environment():
    """Set up environment variables like DeepFaceLab's setenv.bat"""
    base_path = Path(__file__).parent.parent
    internal = base_path / "DeepFaceLab_NVIDIA_RTX3000_series" / "_internal"
    
    # Set CUDA paths
    cuda_path = internal / "CUDA"
    cudnn_path = internal / "CUDNN"
    
    # Add CUDA and cuDNN to PATH
    current_path = os.environ.get('PATH', '')
    new_path = f"{cuda_path};{cudnn_path};{current_path}"
    os.environ['PATH'] = new_path
    
    # Set CUDA cache path (Windows)
    if sys.platform == 'win32':
        compute_cache_path = Path(os.environ.get('APPDATA', '')) / 'NVIDIA' / 'ComputeCache_ALL'
        os.environ['CUDA_CACHE_PATH'] = str(compute_cache_path)
        if not compute_cache_path.exists():
            compute_cache_path.mkdir(parents=True, exist_ok=True)
    
    return internal

def check_gpu_with_env():
    """Check GPU with proper environment setup"""
    internal = setup_dfl_environment()
    dfl_root = internal / "DeepFaceLab"
    python_exe = internal / "python-3.6.8" / "python.exe"
    
    test_script = """
import sys
import os

# Set TensorFlow logging
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'
os.environ['CUDA_CACHE_MAXSIZE'] = '2147483647'

gpu_detected = False
try:
    import tensorflow as tf
    print(f"TensorFlow version: {tf.__version__}")
    print(f"TensorFlow built with CUDA: {tf.test.is_built_with_cuda()}")
    print(f"TensorFlow built with GPU: {tf.test.is_built_with_gpu_support()}")
    
    # List physical devices
    physical_devices = tf.config.list_physical_devices()
    print(f"\\nPhysical devices found: {len(physical_devices)}")
    
    gpu_devices = [d for d in physical_devices if 'GPU' in d.name]
    if gpu_devices:
        print("\\n[OK] GPU devices detected:")
        gpu_detected = True
        for device in gpu_devices:
            print(f"  - {device.name}")
            try:
                # Try to get memory info
                tf.config.experimental.set_memory_growth(device, True)
                print(f"    Memory growth enabled")
            except Exception as e:
                print(f"    Note: {e}")
    else:
        print("\\n[FAIL] No GPU devices detected")
        print("Available devices:")
        for device in physical_devices:
            print(f"  - {device.name}")
        
        # Check for common issues
        print("\\nTroubleshooting:")
        print(f"  PATH contains CUDA: {'CUDA' in os.environ.get('PATH', '')}")
        print(f"  CUDA_CACHE_PATH: {os.environ.get('CUDA_CACHE_PATH', 'Not set')}")
    
    sys.exit(0 if gpu_detected else 1)
    
except ImportError as e:
    print(f"[FAIL] Failed to import TensorFlow: {e}")
    sys.exit(1)
except Exception as e:
    print(f"[FAIL] Error checking GPU: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
"""
    
    import tempfile
    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
        f.write(test_script)
        temp_script = f.name
    
    try:
        print("="*60)
        print("Testing GPU Detection with Environment Setup")
        print("="*60)
        print(f"CUDA Path: {internal / 'CUDA'}")
        print(f"cuDNN Path: {internal / 'CUDNN'}")
        print(f"PATH updated: {'CUDA' in os.environ.get('PATH', '')}")
        print()
        
        # Run with environment
        env = os.environ.copy()
        env['PATH'] = f"{internal / 'CUDA'};{internal / 'CUDNN'};{env.get('PATH', '')}"
        
        result = subprocess.run(
            [str(python_exe), temp_script],
            capture_output=True,
            text=True,
            timeout=30,
            cwd=str(dfl_root),
            env=env
        )
        
        print(result.stdout)
        if result.stderr:
            print("Warnings/Errors:")
            print(result.stderr)
        
        return result.returncode == 0
    except Exception as e:
        print(f"[FAIL] Error: {e}")
        return False
    finally:
        try:
            os.unlink(temp_script)
        except:
            pass

if __name__ == "__main__":
    success = check_gpu_with_env()
    sys.exit(0 if success else 1)

