"""Make the pip-installed NVIDIA DLLs (venv/Lib/site-packages/nvidia/*/bin)
visible to onnxruntime-gpu and torch — once per process.

Every os.add_dll_directory() call adds a new entry to the process's DLL search
list, even for a directory that is already there, and the handles are never
released. Streamlit re-executes dashboard.py on every rerun, so registering
unconditionally there leaked 3 entries per click; after ~150 reruns Windows
refused new ones with "[WinError 206] The filename or extension is too long",
which surfaced as `import torch` failing inside torch's own add_dll_directory.
"""
import os
import sys

# bin dir -> handle from os.add_dll_directory (kept so it is never closed)
_registered = {}


def add_nvidia_dll_dirs() -> None:
    if os.name != "nt":
        return
    nvidia_base = os.path.join(sys.prefix, "Lib", "site-packages", "nvidia")
    if not os.path.isdir(nvidia_base):
        return
    for pkg in os.listdir(nvidia_base):
        bin_dir = os.path.join(nvidia_base, pkg, "bin")
        if bin_dir in _registered or not os.path.isdir(bin_dir):
            continue
        try:
            _registered[bin_dir] = os.add_dll_directory(bin_dir)
        except OSError:
            continue
        if bin_dir not in os.environ.get("PATH", "").split(os.pathsep):
            os.environ["PATH"] = bin_dir + os.pathsep + os.environ.get("PATH", "")
