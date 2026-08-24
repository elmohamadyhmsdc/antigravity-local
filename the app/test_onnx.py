import os
import sys

# Add ALL NVIDIA DLL paths for ONNX Runtime CUDA support
# This must happen BEFORE importing onnxruntime
if os.name == 'nt':
    _nvidia_base = os.path.join(sys.prefix, 'Lib', 'site-packages', 'nvidia')
    if os.path.isdir(_nvidia_base):
        for _pkg in os.listdir(_nvidia_base):
            _bin_dir = os.path.join(_nvidia_base, _pkg, 'bin')
            if os.path.isdir(_bin_dir):
                try:
                    os.add_dll_directory(_bin_dir)
                    os.environ['PATH'] = _bin_dir + os.pathsep + os.environ.get('PATH', '')
                    dlls = [f for f in os.listdir(_bin_dir) if f.endswith('.dll')]
                    print(f"Added DLL dir: {_bin_dir} ({len(dlls)} DLLs)")
                except Exception as e:
                    print(f"Failed: {_bin_dir}: {e}")

import onnxruntime
print("\nONNX Runtime available providers:", onnxruntime.get_available_providers())

from insightface.app import FaceAnalysis
app = FaceAnalysis(name='buffalo_l', providers=['CUDAExecutionProvider', 'CPUExecutionProvider'])
app.prepare(ctx_id=0, det_size=(640, 640))
print("\nPrepared successfully!")
print("CUDA working!" if any('CUDA' in str(m) for m in ['CUDAExecutionProvider']) else "CPU only")
