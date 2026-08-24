"""
Diagnostic script to check CUDA DLL availability for onnxruntime-gpu
Helps identify missing dependencies that cause error 126
"""

import os
import sys
from pathlib import Path

def check_dll_in_path(dll_name):
    """Check if a DLL can be found in PATH"""
    path_dirs = os.environ.get('PATH', '').split(';')
    for path_dir in path_dirs:
        if not path_dir:
            continue
        dll_path = Path(path_dir) / dll_name
        if dll_path.exists():
            return str(dll_path)
    return None

def check_cuda_dlls():
    """Check for required CUDA runtime DLLs"""
    print("=" * 60)
    print("CUDA DLL Availability Check for onnxruntime-gpu")
    print("=" * 60)
    
    # Common CUDA runtime DLLs that onnxruntime-gpu needs
    required_dlls = [
        'cudart64_*.dll',  # CUDA runtime
        'cublas64_*.dll',   # cuBLAS
        'cublasLt64_*.dll', # cuBLASLt
        'curand64_*.dll',   # cuRAND
        'cusolver64_*.dll', # cuSOLVER
        'cusparse64_*.dll', # cuSPARSE
        'cufft64_*.dll',    # cuFFT
    ]
    
    print("\n[1] Checking for CUDA runtime DLLs in PATH...")
    found_dlls = []
    missing_dlls = []
    
    # Check common locations
    check_paths = [
        Path(r"C:\Windows\System32"),
        Path(r"C:\Program Files\NVIDIA Corporation\NVSMI"),
    ]
    
    # Check NVIDIA driver installation paths
    nvidia_paths = [
        Path(r"C:\Program Files\NVIDIA Corporation"),
        Path(r"C:\Program Files (x86)\NVIDIA Corporation"),
    ]
    for nv_path in nvidia_paths:
        if nv_path.exists():
            # Look for CUDA runtime in NVIDIA directories
            for subdir in nv_path.iterdir():
                if subdir.is_dir() and 'cuda' in subdir.name.lower():
                    bin_path = subdir / "bin"
                    if bin_path.exists():
                        check_paths.append(bin_path)
                        print(f"[OK] Found NVIDIA CUDA path: {bin_path}")
    
    # Add CUDA Toolkit paths (most common solution)
    # Check both Program Files and Program Files (x86)
    cuda_toolkit_found = False
    base_paths = [
        Path(r"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA"),
        Path(r"C:\Program Files (x86)\NVIDIA GPU Computing Toolkit\CUDA"),
    ]
    
    # Check all versions (including 13.x)
    versions = ['13.1', '13.0', '12.6', '12.5', '12.4', '12.3', '12.2', '12.1', '12.0', '11.8', '11.7', '11.6', '11.4', '11.2', '11.0']
    
    for base_path in base_paths:
        if base_path.exists():
            for version in versions:
                # Check both bin and lib/x64 (CUDA 13.x might use lib/x64)
                bin_path = base_path / f"v{version}" / "bin"
                lib_path = base_path / f"v{version}" / "lib" / "x64"
                
                if bin_path.exists():
                    check_paths.append(bin_path)
                    print(f"[OK] Found CUDA Toolkit bin: {bin_path}")
                    cuda_toolkit_found = True
                    # Check if DLLs actually exist
                    dlls = list(bin_path.glob("cudart*.dll"))
                    if dlls:
                        print(f"     Found {len(dlls)} CUDA runtime DLL(s) in bin")
                    else:
                        print(f"     [WARNING] No cudart DLLs found in bin directory")
                
                if lib_path.exists():
                    check_paths.append(lib_path)
                    print(f"[OK] Found CUDA Toolkit lib/x64: {lib_path}")
                    # Check if DLLs actually exist
                    dlls = list(lib_path.glob("cudart*.dll"))
                    if dlls:
                        print(f"     Found {len(dlls)} CUDA runtime DLL(s) in lib/x64")
                        cuda_toolkit_found = True
                
                if cuda_toolkit_found:
                    break
            if cuda_toolkit_found:
                break
    
    # Check onnxruntime-gpu installation
    try:
        import site
        site_packages = site.getsitepackages()
        for site_pkg in site_packages:
            ort_path = Path(site_pkg) / "onnxruntime" / "capi"
            if ort_path.exists():
                check_paths.append(ort_path)
                print(f"[OK] Found onnxruntime-gpu: {ort_path}")
    except:
        pass
    
    # Search for DLLs
    import glob
    for dll_pattern in required_dlls:
        found = False
        for check_path in check_paths:
            matches = list(check_path.glob(dll_pattern))
            if matches:
                found_dlls.append((dll_pattern, str(matches[0])))
                found = True
                break
        if not found:
            missing_dlls.append(dll_pattern)
    
    print(f"\n[2] Results:")
    print(f"  Found: {len(found_dlls)} DLLs")
    print(f"  Missing: {len(missing_dlls)} DLLs")
    
    if found_dlls:
        print("\n[OK] Found DLLs:")
        for dll_pattern, dll_path in found_dlls[:10]:  # Show first 10
            print(f"  {dll_pattern}: {Path(dll_path).name}")
    
    if missing_dlls:
        print("\n[FAIL] Missing DLLs:")
        for dll_pattern in missing_dlls:
            print(f"  {dll_pattern}")
    
    # Check nvidia-smi
    print("\n[3] Checking NVIDIA drivers...")
    try:
        import subprocess
        result = subprocess.run(['nvidia-smi', '--version'], 
                              capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            print("[OK] nvidia-smi works - NVIDIA drivers are installed")
            print(f"     {result.stdout.split(chr(10))[0]}")
        else:
            print("[FAIL] nvidia-smi failed - NVIDIA drivers may not be installed")
    except FileNotFoundError:
        print("[FAIL] nvidia-smi not found - NVIDIA drivers may not be installed")
    except Exception as e:
        print(f"[WARNING] Could not check nvidia-smi: {e}")
    
    # Recommendations
    print("\n[4] Recommendations:")
    if missing_dlls:
        print("  [ACTION REQUIRED] Missing CUDA DLLs detected!")
        print("  onnxruntime-gpu requires CUDA Toolkit to be installed separately.")
        print("\n  Solutions (in order of preference):")
        print("\n  [OPTION 1] Install CUDA Toolkit (Recommended):")
        print("    1. Download CUDA Toolkit from: https://developer.nvidia.com/cuda-downloads")
        print("    2. For onnxruntime-gpu 1.16.3, use CUDA 11.x or 12.x")
        print("    3. During installation, ensure 'Add to PATH' is checked")
        print("    4. Restart your computer after installation")
        print("    5. Verify: nvcc --version")
        print("\n  [OPTION 2] Use CPU version (if GPU not critical):")
        print("    pip uninstall onnxruntime-gpu")
        print("    pip install onnxruntime==1.16.3")
        print("    Note: This will use CPU instead of GPU (slower but works)")
        print("\n  [OPTION 3] Try different onnxruntime-gpu version:")
        print("    Some versions bundle CUDA runtime differently")
        print("    pip uninstall onnxruntime-gpu")
        print("    pip install onnxruntime-gpu==1.15.1  # Try older version")
        print("\n  Additional steps:")
        print("  - Ensure NVIDIA Control Panel is configured to use GPU for Python")
        print("  - Restart computer after any driver/CUDA installation")
    else:
        print("  [OK] All required DLLs appear to be available")
        print("  If you still get error 126, try:")
        print("  1. Restart your computer")
        print("  2. Configure NVIDIA Control Panel to use GPU for Python")
        print("  3. Check if Advanced Optimus is interfering")
    
    return len(missing_dlls) == 0

if __name__ == "__main__":
    success = check_cuda_dlls()
    sys.exit(0 if success else 1)
