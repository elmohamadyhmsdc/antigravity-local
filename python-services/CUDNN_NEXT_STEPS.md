# Next Steps After Installing cuDNN 9.17.0

## What the Installer Did

The cuDNN `.exe` installer typically **extracts files** to a location, but doesn't automatically copy them to your CUDA directory. You need to **manually copy** the files.

## Step 1: Find Where cuDNN Was Installed

Run this script to find cuDNN:
```bash
python find_cudnn.py
```

Or check these common locations:
- `C:\Program Files\NVIDIA\cudnn\`
- `C:\cudnn\`
- `C:\Users\<YourUsername>\Downloads\cudnn-windows-x86_64-9.17.0_cuda12-archive\`
- The directory where you ran the installer

## Step 2: Copy Files to CUDA 12.6 Directory

Once you find the cuDNN files, copy them to your CUDA 12.6 installation:

### If cuDNN is in `C:\cudnn\` (or similar):

**PowerShell (Run as Administrator):**

```powershell
# Copy DLLs
Copy-Item "C:\cudnn\bin\*" -Destination "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin\" -Force

# Copy headers
Copy-Item "C:\cudnn\include\*" -Destination "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\include\" -Force

# Copy libraries
Copy-Item "C:\cudnn\lib\x64\*" -Destination "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\lib\x64\" -Force
```

**Or manually:**
1. Open File Explorer
2. Navigate to where cuDNN was extracted (e.g., `C:\cudnn\`)
3. Copy files from:
   - `bin\` → `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin\`
   - `include\` → `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\include\`
   - `lib\x64\` → `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\lib\x64\`

## Step 3: Verify Installation

Check if `cudnn64_9.dll` exists:
```bash
dir "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin\cudnn64_9.dll"
```

Should show the file.

## Step 4: Restart and Test

1. **Restart your computer** (important!)
2. Test the service:
   ```bash
   python main.py
   ```

Should now work! You should see:
- `[INFO] Using GPU (CUDA) for face detection`
- **No error messages** about missing `cudnn64_9.dll`

## If You Can't Find cuDNN

If the installer didn't extract files or you can't find them:

1. **Re-download as ZIP** (recommended):
   - Go to: https://developer.nvidia.com/cudnn
   - Download the **ZIP version** (not .exe)
   - Extract it manually
   - Copy files as described above

2. **Or re-run the installer**:
   - Note the installation/extraction directory
   - Copy files from there

## Quick Check

After copying files, verify:
```bash
python -c "from pathlib import Path; dll = Path(r'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin\cudnn64_9.dll'); print('Found!' if dll.exists() else 'Not found!')"
```

## Summary

**What you need to do:**
1. ✅ cuDNN 9.17.0 installer downloaded and run
2. ⏳ **Find where it extracted files** (run `python find_cudnn.py`)
3. ⏳ **Copy files to CUDA 12.6 directory**
4. ⏳ **Restart computer**
5. ⏳ **Test with `python main.py`**

The installer likely just extracted files - you need to copy them to the CUDA directory manually!

