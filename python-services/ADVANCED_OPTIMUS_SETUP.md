# Advanced Optimus / MUX Switch GPU Setup

## Problem
On ASUS TUF F15 and similar laptops with NVIDIA Advanced Optimus and MUX switch, the dedicated NVIDIA GPU may not be detected by Python applications. This is because the system dynamically switches between integrated GPU (Intel) and dedicated GPU (NVIDIA) for power saving.

## Solutions

### 1. NVIDIA Control Panel Configuration (Recommended)

**Force Python to use NVIDIA GPU:**

1. Open **NVIDIA Control Panel**
2. Go to **Manage 3D Settings**
3. Click **Program Settings** tab
4. Click **Add** and browse to your Python executable:
   - Usually: `C:\Users\<YourUsername>\AppData\Local\Programs\Python\Python3XX\python.exe`
   - Or: `C:\Python3XX\python.exe`
   - Or find it with: `where python` in Command Prompt
5. Set **Preferred graphics processor** to **High-performance NVIDIA processor**
6. Click **Apply**

**Alternative - Global Settings:**
1. In **Manage 3D Settings**, go to **Global Settings** tab
2. Set **Preferred graphics processor** to **High-performance NVIDIA processor**
3. Click **Apply**

### 2. Code-Level Fixes (Already Implemented)

The code has been updated to:
- Set `NvOptimusEnablement=1` environment variable
- Initialize CUDA context early to force GPU activation
- Configure ONNX Runtime CUDA provider with Optimus-compatible settings

### 3. Verify GPU Detection

**Check if GPU is detected:**

```bash
# Check NVIDIA GPU status
nvidia-smi

# Check Python can see GPU
python -c "import onnxruntime as ort; print(ort.get_available_providers())"
```

You should see `CUDAExecutionProvider` in the list.

**Test with the service:**
```bash
cd python-services
python main.py
```

Look for: `[INFO] Using GPU (CUDA) for face detection`

### 4. Install Required Packages

Make sure you have the GPU version:
```bash
pip uninstall onnxruntime
pip install onnxruntime-gpu==1.16.3
```

### 5. Optional: Install pycuda for Better GPU Activation

**Note**: `pycuda` is **optional** and **not required**. The code works fine without it.

If you want to try installing it (requires CUDA Toolkit):
```bash
pip install pycuda
```

**However**, if installation fails (common on Windows), you can safely skip it. The code will:
- Use environment variables (`NvOptimusEnablement=1`) to force GPU
- Use `onnxruntime-gpu` to detect and use GPU
- Fall back gracefully if GPU isn't available

**Recommended**: Skip `pycuda` and just use NVIDIA Control Panel configuration (Step 1) - that's usually sufficient.

## Troubleshooting

### GPU Still Not Detected?

1. **Check NVIDIA drivers:**
   ```bash
   nvidia-smi
   ```
   If this fails, update your NVIDIA drivers.

2. **Check if GPU is in power-saving mode:**
   - Open **NVIDIA Control Panel** → **System Information**
   - Check if GPU is listed and active

3. **Disable Hybrid Graphics (if possible):**
   - Some laptops allow disabling Optimus in BIOS
   - This forces dedicated GPU to always be active
   - Check your laptop's BIOS settings

4. **Check Windows Graphics Settings:**
   - Windows Settings → System → Display → Graphics settings
   - Add Python executable
   - Set to "High performance"

5. **Fix Error 126 (LoadLibrary failed):**
   
   If you see `LoadLibrary failed with error 126` when starting the service, it means CUDA DLLs are missing.
   
   **Run diagnostic:**
   ```bash
   python python-services/check_cuda_dlls.py
   ```
   
   **Solutions:**
   - Update NVIDIA GPU drivers: https://www.nvidia.com/drivers
   - The code now automatically adds CUDA paths to PATH, but you may need to:
     - Restart your computer after updating drivers
     - Ensure NVIDIA Control Panel is configured (Step 1)
     - Try reinstalling onnxruntime-gpu:
       ```bash
       pip uninstall onnxruntime-gpu
       pip install onnxruntime-gpu==1.16.3
       ```

6. **Verify CUDA Installation:**
   ```bash
   nvidia-smi  # Should show your GPU
   ```
   Note: You don't need CUDA Toolkit installed - onnxruntime-gpu bundles its own CUDA runtime, but it needs NVIDIA drivers to be up to date.

## Performance Notes

- **With GPU**: Face detection is 5-10x faster
- **Without GPU**: Still works, but slower on CPU
- **Optimus Impact**: May cause slight delay on first GPU call as it switches from iGPU to dGPU

## ASUS TUF F15 Specific Notes

- Your laptop likely has NVIDIA RTX 3050/3050 Ti/3060
- Advanced Optimus allows dynamic switching without reboot
- MUX switch may be available in BIOS to disable Optimus entirely
- Check ASUS Armoury Crate for GPU mode settings
