# Upgrade onnxruntime-gpu for CUDA 13.1 Support

## Current Situation
- ✅ CUDA Toolkit 13.1 is installed
- ⚠️ onnxruntime-gpu 1.16.3 doesn't officially support CUDA 13.1
- ⚠️ CUDA 13.1 DLLs not being found (might be in lib/x64 instead of bin)

## Solution: Upgrade onnxruntime-gpu

### Option 1: Upgrade to Latest Version (Recommended)

The latest onnxruntime-gpu versions (1.19+) support CUDA 12.x, which might work with CUDA 13.1 due to backward compatibility:

```bash
pip uninstall onnxruntime-gpu
pip install onnxruntime-gpu --upgrade
```

Or install a specific newer version:
```bash
pip install onnxruntime-gpu==1.20.0
```

**Benefits:**
- Better CUDA 12.x support (might work with 13.1)
- More recent bug fixes
- Better performance

**After upgrading:**
1. Restart Python service: `python main.py`
2. Check if CUDA provider works
3. If still fails, see Option 2

### Option 2: Install CUDA 12.x (Most Reliable)

If upgrading onnxruntime-gpu doesn't work, install CUDA 12.x alongside CUDA 13.1:

1. Download CUDA 12.6: https://developer.nvidia.com/cuda-12-6-0-download-archive
2. Install it (you can have multiple CUDA versions)
3. The code will automatically use CUDA 12.6
4. Restart computer

**Why this works:**
- onnxruntime-gpu 1.19+ officially supports CUDA 12.x
- Guaranteed compatibility
- You can keep CUDA 13.1 for other projects

### Option 3: Use Current Version with CUDA 12.x

Keep onnxruntime-gpu 1.16.3 but install CUDA 12.x:

```bash
# Install CUDA 12.6
# Then restart Python service
python main.py
```

## Verification Steps

After upgrading/installing:

1. **Check version:**
   ```bash
   pip show onnxruntime-gpu
   ```

2. **Test CUDA:**
   ```bash
   python test_cuda_13.py
   ```

3. **Run service:**
   ```bash
   python main.py
   ```

   Should see: `[INFO] Using GPU (CUDA) for face detection` without errors

## Recommendation

**Best approach:**
1. First try: `pip install onnxruntime-gpu --upgrade`
2. If that doesn't work: Install CUDA 12.6
3. Keep CUDA 13.1 for future use (when onnxruntime adds support)

## Why CUDA 13.1 DLLs Aren't Found

CUDA 13.1 might store DLLs in `lib/x64` instead of `bin`. The updated code now checks both locations. However, the main issue is compatibility - onnxruntime-gpu 1.16.3 was built for CUDA 11.8, not 13.1.
