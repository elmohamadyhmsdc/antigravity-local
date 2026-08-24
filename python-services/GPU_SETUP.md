# GPU Setup for DeepFaceLab

## Status

✅ **GPU Detected**: NVIDIA GeForce RTX 4050 (6GB VRAM)  
✅ **Driver Version**: 581.80  
✅ **CUDA Version**: 13.0 (driver support)  
✅ **DeepFaceLab CUDA DLLs**: Present  
✅ **TensorFlow GPU Support**: Enabled  

## Important: Environment Setup

DeepFaceLab requires CUDA DLLs to be in the PATH when TensorFlow loads. The `DeepFaceLabEnvironment` class in `services/deepfacelab_utils.py` handles this automatically.

### Key Points

1. **CUDA DLLs in PATH**: The CUDA DLLs from `DeepFaceLab_NVIDIA_RTX3000_series/_internal/CUDA/` must be in the PATH before TensorFlow imports.

2. **Environment Setup**: Always use `DeepFaceLabEnvironment.setup_environment()` to get the correct environment variables when calling DeepFaceLab.

3. **GPU Verification**: Use `check_gpu.py` or `check_gpu_with_env.py` to verify GPU detection.

## Verification

Run the GPU check script:

```bash
python python-services/check_gpu_with_env.py
```

Expected output:
```
[OK] GPU devices detected:
  - /physical_device:GPU:0
```

## Usage in Code

```python
from services.deepfacelab_utils import get_dfl_environment

# Get environment (auto-detects DeepFaceLab installation)
dfl_env = get_dfl_environment()

# Verify GPU is available
if dfl_env.verify_gpu_available():
    print("GPU is ready!")
else:
    print("GPU not detected - will use CPU (slower)")

# Get environment for subprocess calls
env = dfl_env.setup_environment()

# Use in subprocess
import subprocess
result = subprocess.run(
    dfl_env.get_python_command() + ["script.py"],
    env=env,
    cwd=str(dfl_env.dfl_root)
)
```

## Troubleshooting

### GPU Not Detected

If GPU is not detected:

1. **Check nvidia-smi**: Run `nvidia-smi` to verify GPU is visible to the system
2. **Check CUDA DLLs**: Verify DLLs exist in `_internal/CUDA/`
3. **Check Environment**: Ensure `setup_environment()` is called before TensorFlow imports
4. **Check TensorFlow**: Verify TensorFlow was built with GPU support (should show `True` for `is_built_with_cuda()`)

### Common Issues

- **CUDA DLLs not in PATH**: Use `DeepFaceLabEnvironment.setup_environment()` to fix
- **Version mismatch**: DeepFaceLab uses CUDA 10.1/11.0, but driver supports 13.0 (backward compatible, should work)
- **TensorFlow CPU-only**: DeepFaceLab's bundled TensorFlow should have GPU support

## Performance Notes

- **Training**: Can take hours depending on model and dataset size
- **Extraction**: Fast (seconds to minutes) with GPU
- **Merging**: Fast (seconds to minutes) with GPU
- **CPU Fallback**: Works but much slower (10-100x slower)

