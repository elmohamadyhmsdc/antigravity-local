# DeepFaceLab Integration Guide

## Overview

Your DeepFaceLab installation in `DeepFaceLab_NVIDIA_RTX3000_series/` is now integrated with the Python services for face handling operations.

## GPU Status

✅ **GPU Ready**: NVIDIA GeForce RTX 4050 (6GB) is detected and ready for use.

## Key Components

### 1. `services/deepfacelab_utils.py`
Utility module that handles:
- DeepFaceLab environment setup (CUDA paths, TensorFlow config)
- GPU availability verification
- Path management for DeepFaceLab installation

### 2. `services/face_swap.py`
Updated face swap service that:
- Auto-detects DeepFaceLab installation
- Properly sets up environment for GPU usage
- Implements face extraction workflow
- Ready for full face swap implementation (requires model training)

### 3. GPU Verification Scripts
- `check_gpu.py`: Basic GPU check
- `check_gpu_with_env.py`: GPU check with proper environment setup (recommended)

## Usage

### Verify GPU Setup

```bash
python python-services/check_gpu_with_env.py
```

### Use Face Swap Service

```python
from services.face_swap import FaceSwapService

# Initialize (auto-detects DeepFaceLab)
service = FaceSwapService()

# Check GPU status
if service.gpu_available:
    print("GPU is ready!")

# Perform face swap
result_path = await service.swap_faces(
    source_image_path="path/to/source.jpg",
    target_image_path="path/to/target.jpg",
    bbox={"x": 0, "y": 0, "width": 100, "height": 100}
)
```

### Direct DeepFaceLab Environment Access

```python
from services.deepfacelab_utils import get_dfl_environment

# Get environment
dfl_env = get_dfl_environment()

# Setup environment for subprocess calls
env = dfl_env.setup_environment()

# Get Python command
python_cmd = dfl_env.get_python_command()  # Returns [path/to/python.exe]

# Get main script path
main_script = dfl_env.get_main_script()  # Returns path/to/main.py
```

## Important Notes

### Environment Setup
**Critical**: CUDA DLLs must be in PATH before TensorFlow loads. The `DeepFaceLabEnvironment.setup_environment()` method handles this automatically. Always use it when calling DeepFaceLab subprocesses.

### Face Swap Workflow
Full face swapping requires:
1. ✅ Face extraction (implemented)
2. ⏳ Model training (can take hours - not yet implemented)
3. ⏳ Face merging (requires trained model - not yet implemented)

Current implementation extracts faces but doesn't perform full swap yet. For production, you'll need to:
- Train a model or use pre-trained models
- Implement the merge step
- Consider using Quick96 model for faster training

### Performance
- **GPU Available**: Fast extraction (seconds), training (hours)
- **CPU Only**: Much slower (10-100x slower)

## File Structure

```
DeepFaceLab_NVIDIA_RTX3000_series/
├── _internal/
│   ├── CUDA/              # CUDA DLLs (required for GPU)
│   ├── CUDNN/             # cuDNN libraries
│   ├── DeepFaceLab/       # Main DeepFaceLab code
│   └── python-3.6.8/      # Bundled Python
└── workspace/             # Default workspace for operations

python-services/
├── services/
│   ├── deepfacelab_utils.py  # Environment management
│   └── face_swap.py          # Face swap service
├── check_gpu.py              # Basic GPU check
├── check_gpu_with_env.py     # GPU check with env setup
└── GPU_SETUP.md              # GPU setup documentation
```

## Next Steps

1. **Test Face Extraction**: Try extracting faces from images using the service
2. **Model Training**: Implement model training workflow (or use pre-trained)
3. **Face Merging**: Implement merge step for complete face swap
4. **Background Jobs**: Integrate with Hangfire for async processing

## Troubleshooting

See `GPU_SETUP.md` for detailed troubleshooting guide.

## References

- DeepFaceLab Documentation: Check `DeepFaceLab_NVIDIA_RTX3000_series/changelog.html`
- Batch Files: Reference `DeepFaceLab_NVIDIA_RTX3000_series/*.bat` for command examples

