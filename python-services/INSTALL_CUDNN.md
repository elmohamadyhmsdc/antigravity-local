# Install cuDNN 9.x for CUDA 12.6

## Problem
You installed CUDA 12.6, but now you're getting:
```
Error loading "onnxruntime_providers_cuda.dll" which depends on "cudnn64_9.dll" which is missing.
```

**cuDNN** (CUDA Deep Neural Network library) is a **separate component** from CUDA Toolkit. onnxruntime-gpu 1.23.2 requires cuDNN 9.x.

## Solution: Install cuDNN 9.x

### Step 1: Download cuDNN

1. Go to: https://developer.nvidia.com/cudnn
2. **You need to create a free NVIDIA Developer account** (if you don't have one)
3. After logging in, go to: https://developer.nvidia.com/cudnn
4. Download **cuDNN for CUDA 12.x**
   - Look for version **9.x** (e.g., 9.3.0, 9.4.0, 9.5.0)
   - Make sure it's for **CUDA 12.x** (not 11.x or 13.x)
   - Download the **Windows zip file** (not the installer)

### Step 2: Extract and Install cuDNN

1. Extract the downloaded zip file (e.g., `cudnn-windows-x86_64-9.x.x.x_cuda12-archive.zip`)
2. You'll see folders: `bin`, `include`, `lib`
3. Copy files to your CUDA 12.6 installation:

   **Copy these files:**
   - From `bin/` → To `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin\`
     - Copy all `.dll` files (especially `cudnn64_9.dll`)
   
   - From `include/` → To `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\include\`
     - Copy `cudnn.h` and other header files
   
   - From `lib/` → To `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\lib\x64\`
     - Copy all `.lib` files (especially `cudnn.lib`)

### Step 3: Verify Installation

Check if `cudnn64_9.dll` exists:
```bash
dir "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin\cudnn64_9.dll"
```

Should show the file.

### Step 4: Restart and Test

1. **Restart your computer** (important for PATH changes)
2. Test the service:
   ```bash
   python main.py
   ```

Should now work! You should see:
- `[INFO] Using GPU (CUDA) for face detection`
- **No error messages** about missing DLLs

## Quick Copy Commands (PowerShell as Administrator)

If you extracted cuDNN to `C:\Downloads\cudnn\`:

```powershell
# Copy DLLs
Copy-Item "C:\Downloads\cudnn\bin\*" -Destination "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin\" -Force

# Copy headers
Copy-Item "C:\Downloads\cudnn\include\*" -Destination "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\include\" -Force

# Copy libraries
Copy-Item "C:\Downloads\cudnn\lib\*" -Destination "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\lib\x64\" -Force
```

**Note**: Run PowerShell as Administrator to copy to Program Files.

## Alternative: Add cuDNN to PATH

If you don't want to copy files, you can add cuDNN's bin directory to PATH:

1. Extract cuDNN to a location like `C:\cudnn\`
2. Add `C:\cudnn\bin` to your system PATH
3. Restart computer

However, copying to CUDA directory is the recommended approach.

## What is cuDNN?

**cuDNN** (CUDA Deep Neural Network library) is NVIDIA's GPU-accelerated library for deep neural networks. It's required by:
- TensorFlow
- PyTorch
- ONNX Runtime GPU
- Other deep learning frameworks

It's a **separate download** from CUDA Toolkit.

## Summary

**Current status:**
- ✅ CUDA 12.6 installed
- ✅ onnxruntime-gpu 1.23.2 installed
- ❌ cuDNN 9.x missing

**Next step:**
- Download and install cuDNN 9.x for CUDA 12.x
- Copy files to CUDA 12.6 directory
- Restart computer
- Run `python main.py` - should work!

