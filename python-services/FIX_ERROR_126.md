# Fix Error 126: LoadLibrary failed for onnxruntime_providers_cuda.dll

## Problem
When starting the Python service, you see:
```
[ONNXRuntimeError] : 1 : FAIL : LoadLibrary failed with error 126 "" when trying to load "onnxruntime_providers_cuda.dll"
```

## Root Cause
`onnxruntime-gpu` requires CUDA Toolkit to be installed separately. The CUDA runtime DLLs (`cudart64_*.dll`, `cublas64_*.dll`, etc.) are **not bundled** with onnxruntime-gpu - they must come from a CUDA Toolkit installation.

## Solution: Install CUDA Toolkit

### Step 1: Download CUDA Toolkit
1. Go to: https://developer.nvidia.com/cuda-downloads
2. Select:
   - **Operating System**: Windows
   - **Architecture**: x86_64
   - **Version**: Windows 10/11
   - **Installer Type**: exe (local)
3. Download the installer (about 3GB)

### Step 2: Install CUDA Toolkit
1. Run the installer
2. **Important**: During installation, check "Add to PATH" option
3. Complete the installation
4. **Restart your computer** (required!)

### Step 3: Verify Installation
```bash
nvcc --version
```
Should show something like:
```
nvcc: NVIDIA (R) Cuda compiler driver
Copyright (c) 2005-2024 NVIDIA Corporation
Built on ...
Cuda compilation tools, release 12.x, V12.x.x
```

### Step 4: Verify DLLs are Found
```bash
python check_cuda_dlls.py
```
Should now show DLLs found instead of missing.

### Step 5: Restart Python Service
```bash
python main.py
```
Should now work without error 126!

## Alternative: Use CPU Version (If GPU Not Critical)

If you don't want to install CUDA Toolkit (it's large, ~3GB), you can use the CPU version:

```bash
pip uninstall onnxruntime-gpu
pip install onnxruntime==1.16.3
```

**Note**: This will use CPU instead of GPU (much slower for face detection, but works).

## CUDA Version Compatibility

For `onnxruntime-gpu==1.16.3`:
- **CUDA 11.x**: ✅ Fully supported (built with CUDA 11.8)
- **CUDA 12.x**: ✅ Should work (backward compatible)
- **CUDA 13.x**: ⚠️ **May not work** - Major version jump, compatibility not guaranteed

**If you have CUDA 13.1 installed:**
1. Run: `python test_cuda_13.py` to test compatibility
2. If it fails, install CUDA 11.8 or 12.x alongside (you can have multiple versions)
3. See `CUDA_VERSION_WARNING.md` for details

## Why This Happens

Modern NVIDIA drivers (like 591.44) include CUDA runtime, but `onnxruntime-gpu` specifically looks for CUDA Toolkit DLLs in standard locations. The drivers' CUDA runtime may not be in the expected path or may have different DLL names.

## After Installation

Once CUDA Toolkit is installed:
- The code in `main.py` will automatically find and add CUDA paths to PATH
- GPU should work automatically
- Face detection will be 5-10x faster

## Still Having Issues?

1. **Run diagnostic**: `python check_cuda_dlls.py`
2. **Check NVIDIA Control Panel**: Ensure Python is set to use GPU
3. **Restart computer**: Required after CUDA installation
4. **Check PATH**: Ensure CUDA bin directory is in system PATH

