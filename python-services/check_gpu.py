"""
GPU and CUDA Verification Script for DeepFaceLab
Checks if GPU is available and can be detected by TensorFlow
"""

import sys
import os
from pathlib import Path

def check_nvidia_smi():
    """Check if nvidia-smi is available"""
    import subprocess
    try:
        result = subprocess.run(['nvidia-smi'], capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            print("[OK] nvidia-smi is available")
            print("\nGPU Information:")
            print(result.stdout)
            return True
        else:
            print("[FAIL] nvidia-smi failed")
            return False
    except FileNotFoundError:
        print("[FAIL] nvidia-smi not found. NVIDIA drivers may not be installed.")
        return False
    except Exception as e:
        print(f"[FAIL] Error running nvidia-smi: {e}")
        return False

def check_deepfacelab_gpu():
    """Check if DeepFaceLab can detect GPU using its Python environment"""
    base_path = Path(__file__).parent.parent
    dfl_path = base_path / "DeepFaceLab_NVIDIA_RTX3000_series"
    python_exe = dfl_path / "_internal" / "python-3.6.8" / "python.exe"
    dfl_root = dfl_path / "_internal" / "DeepFaceLab"
    
    if not python_exe.exists():
        print(f"[FAIL] DeepFaceLab Python not found at: {python_exe}")
        return False
    
    if not dfl_root.exists():
        print(f"[FAIL] DeepFaceLab root not found at: {dfl_root}")
        return False
    
    # Create a test script to check GPU
    test_script = """
import sys
import os
sys.path.insert(0, r'{}')

# Set environment like DeepFaceLab does
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'
os.environ['CUDA_CACHE_MAXSIZE'] = '2147483647'

gpu_detected = False
try:
    import tensorflow as tf
    print(f"TensorFlow version: {{tf.__version__}}")
    
    # Check if TensorFlow was built with GPU support
    print(f"TensorFlow built with CUDA: {{tf.test.is_built_with_cuda()}}")
    print(f"TensorFlow built with GPU: {{tf.test.is_built_with_gpu_support()}}")
    
    # List physical devices
    physical_devices = tf.config.list_physical_devices()
    print(f"\\nPhysical devices found: {{len(physical_devices)}}")
    
    gpu_devices = [d for d in physical_devices if 'GPU' in d.name]
    if gpu_devices:
        print("\\n[OK] GPU devices detected:")
        gpu_detected = True
        for device in gpu_devices:
            print(f"  - {{device.name}}")
            try:
                details = tf.config.experimental.get_device_details(device)
                print(f"    Details: {{details}}")
            except:
                pass
    else:
        print("\\n[FAIL] No GPU devices detected")
        print("Available devices:")
        for device in physical_devices:
            print(f"  - {{device.name}}")
    
    # Try to get GPU memory info
    if gpu_devices:
        try:
            gpu_details = tf.config.experimental.get_device_details(gpu_devices[0])
            print(f"\\nGPU Details: {{gpu_details}}")
        except Exception as e:
            print(f"\\nCould not get GPU details: {{e}}")
    
    # Exit with code 0 if GPU detected, 1 if not
    sys.exit(0 if gpu_detected else 1)
    
except ImportError as e:
    print(f"[FAIL] Failed to import TensorFlow: {{e}}")
    sys.exit(1)
except Exception as e:
    print(f"[FAIL] Error checking GPU: {{e}}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
""".format(str(dfl_root))
    
    import subprocess
    import tempfile
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
        f.write(test_script)
        temp_script = f.name
    
    try:
        print("\n" + "="*60)
        print("Testing DeepFaceLab GPU Detection...")
        print("="*60)
        
        result = subprocess.run(
            [str(python_exe), temp_script],
            capture_output=True,
            text=True,
            timeout=30,
            cwd=str(dfl_root)
        )
        
        print(result.stdout)
        if result.stderr:
            print("Warnings/Errors:")
            print(result.stderr)
        
        # Return True only if GPU was actually detected (exit code 0)
        return result.returncode == 0
    except subprocess.TimeoutExpired:
        print("[FAIL] GPU check timed out")
        return False
    except Exception as e:
        print(f"[FAIL] Error running GPU check: {e}")
        return False
    finally:
        try:
            os.unlink(temp_script)
        except:
            pass

def check_cuda_dlls():
    """Check if CUDA DLLs are available"""
    base_path = Path(__file__).parent.parent
    cuda_path = base_path / "DeepFaceLab_NVIDIA_RTX3000_series" / "_internal" / "CUDA"
    
    if not cuda_path.exists():
        print(f"[FAIL] CUDA directory not found: {cuda_path}")
        return False
    
    dlls = list(cuda_path.glob("*.dll"))
    if dlls:
        print(f"\n[OK] Found {len(dlls)} CUDA DLLs:")
        for dll in sorted(dlls):
            print(f"  - {dll.name}")
        return True
    else:
        print("[FAIL] No CUDA DLLs found")
        return False

def main():
    print("="*60)
    print("DeepFaceLab GPU and CUDA Verification")
    print("="*60)
    
    results = {
        "nvidia-smi": False,
        "CUDA DLLs": False,
        "DeepFaceLab GPU": False
    }
    
    # Check 1: nvidia-smi
    print("\n[1/3] Checking NVIDIA drivers (nvidia-smi)...")
    results["nvidia-smi"] = check_nvidia_smi()
    
    # Check 2: CUDA DLLs
    print("\n[2/3] Checking CUDA DLLs...")
    results["CUDA DLLs"] = check_cuda_dlls()
    
    # Check 3: DeepFaceLab GPU detection
    print("\n[3/3] Checking DeepFaceLab GPU detection...")
    results["DeepFaceLab GPU"] = check_deepfacelab_gpu()
    
    # Summary
    print("\n" + "="*60)
    print("SUMMARY")
    print("="*60)
    for check, passed in results.items():
        status = "[PASS]" if passed else "[FAIL]"
        print(f"{check:.<40} {status}")
    
    all_passed = all(results.values())
    if all_passed:
        print("\n[OK] All checks passed! GPU is ready for DeepFaceLab.")
    else:
        print("\n[FAIL] Some checks failed. Please review the output above.")
        if not results["nvidia-smi"]:
            print("\n  -> Install or update NVIDIA drivers")
        if not results["CUDA DLLs"]:
            print("\n  -> CUDA DLLs missing from DeepFaceLab installation")
        if not results["DeepFaceLab GPU"]:
            print("\n  -> DeepFaceLab cannot detect GPU. Check TensorFlow/CUDA compatibility")
            print("     This may be due to CUDA DLLs not being in PATH when TensorFlow loads.")
            print("     DeepFaceLab's setenv.bat sets up the PATH correctly.")
    
    return 0 if all_passed else 1

if __name__ == "__main__":
    sys.exit(main())

