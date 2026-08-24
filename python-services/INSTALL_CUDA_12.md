# Install CUDA 12.x for onnxruntime-gpu 1.23.2

## Problem
You upgraded to `onnxruntime-gpu 1.23.2`, which requires **CUDA 12.x DLLs** (specifically `cublasLt64_12.dll`), but you only have **CUDA 13.1** installed, which has `cublasLt64_13.dll`.

**Error message:**
```
Error loading "onnxruntime_providers_cuda.dll" which depends on "cublasLt64_12.dll" which is missing.
```

## Solution: Install CUDA 12.6

You can have **multiple CUDA versions** installed simultaneously. Install CUDA 12.6 alongside CUDA 13.1:

### Step 1: Download CUDA 12.6
1. Go to: https://developer.nvidia.com/cuda-12-6-0-download-archive
2. Select:
   - **Operating System**: Windows
   - **Architecture**: x86_64
   - **Version**: Windows 10/11
   - **Installer Type**: exe (local)
3. Download the installer (~3GB)

### Step 2: Install CUDA 12.6
1. Run the installer
2. **Important**: During installation, check "Add to PATH" option
3. Complete the installation
4. **Restart your computer** (required!)

### Step 3: Verify Installation
```bash
nvcc --version
```
Should show CUDA 12.6 (or you'll see both versions in different paths)

### Step 4: Verify DLLs
```bash
python check_cuda_dlls.py
```
Should now find `cublasLt64_12.dll` and other CUDA 12.x DLLs.

### Step 5: Test Service
```bash
python main.py
```
Should now work! You should see:
- `[INFO] Using GPU (CUDA) for face detection`
- **No error messages** about missing DLLs

## Why This Works

- `onnxruntime-gpu 1.23.2` was built with CUDA 12.x
- It specifically needs `cublasLt64_12.dll`, `cudart64_12.dll`, etc.
- CUDA 13.1 has different DLL names (`*_13.dll`)
- The code in `main.py` will automatically find CUDA 12.6 and add it to PATH
- Windows can have multiple CUDA versions - they don't conflict

## After Installation

Once CUDA 12.6 is installed:
- ✅ onnxruntime-gpu 1.23.2 will use CUDA 12.6 DLLs
- ✅ CUDA 13.1 remains installed for other projects
- ✅ The code automatically prioritizes CUDA 12.x over 13.x
- ✅ GPU acceleration will work!

## Alternative: Use CPU Version

If you don't want to install CUDA 12.6:

```bash
pip uninstall onnxruntime-gpu
pip install onnxruntime==1.23.2
```

**Note**: This uses CPU instead of GPU (much slower, but works).

## Summary

**Current situation:**
- ✅ onnxruntime-gpu 1.23.2 installed (requires CUDA 12.x)
- ✅ CUDA 13.1 installed (has CUDA 13.x DLLs)
- ❌ Missing CUDA 12.x DLLs

**Solution:**
- Install CUDA 12.6 (works alongside CUDA 13.1)
- Restart computer
- Run `python main.py` - should work!
