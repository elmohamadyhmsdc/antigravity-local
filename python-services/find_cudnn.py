"""
Script to find where cuDNN was installed
"""

import os
from pathlib import Path

print("=" * 60)
print("Finding cuDNN Installation")
print("=" * 60)

# Common installation locations
search_paths = [
    Path(r"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin"),
    Path(r"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\lib\x64"),
    Path(r"C:\Program Files\NVIDIA"),
    Path(r"C:\Program Files (x86)\NVIDIA"),
    Path(r"C:\cudnn"),
    Path(r"C:\Program Files\cudnn"),
    Path(os.path.expanduser(r"~\AppData\Local\NVIDIA")),
    Path(os.path.expanduser(r"~\Downloads")),
]

# Also check PATH
path_dirs = os.environ.get('PATH', '').split(';')
for path_dir in path_dirs:
    if path_dir and Path(path_dir).exists():
        search_paths.append(Path(path_dir))

print("\n[1] Searching for cudnn64_9.dll...")
found_locations = []

for search_path in search_paths:
    if not search_path.exists():
        continue
    
    # Search recursively for cuDNN DLLs
    try:
        for dll_file in search_path.rglob("cudnn*.dll"):
            if "cudnn64_9" in dll_file.name.lower() or "cudnn" in dll_file.name.lower():
                found_locations.append(dll_file)
                print(f"[FOUND] {dll_file}")
    except (PermissionError, OSError):
        pass

if not found_locations:
    print("[NOT FOUND] cuDNN DLLs not found in common locations")
    print("\n[2] Checking if cuDNN installer created a directory...")
    
    # Check if installer extracted to a temp location
    temp_dirs = [
        Path(os.environ.get('TEMP', '')),
        Path(os.environ.get('TMP', '')),
        Path(r"C:\Users") / os.environ.get('USERNAME', '') / "Downloads",
    ]
    
    for temp_dir in temp_dirs:
        if temp_dir.exists():
            try:
                for item in temp_dir.iterdir():
                    if 'cudnn' in item.name.lower() and item.is_dir():
                        print(f"[FOUND] Possible cuDNN directory: {item}")
                        # Check for DLLs inside
                        for dll in item.rglob("cudnn*.dll"):
                            print(f"  -> {dll}")
            except (PermissionError, OSError):
                pass

if found_locations:
    print("\n[3] Recommendations:")
    print("   cuDNN DLLs found, but they need to be in CUDA 12.6 directory.")
    print("   Copy them to: C:\\Program Files\\NVIDIA GPU Computing Toolkit\\CUDA\\v12.6\\bin\\")
    print("\n   PowerShell command (run as Administrator):")
    for loc in found_locations[:1]:  # Show first location
        print(f'   Copy-Item "{loc}" -Destination "C:\\Program Files\\NVIDIA GPU Computing Toolkit\\CUDA\\v12.6\\bin\\" -Force')
else:
    print("\n[3] cuDNN not found. The installer might have:")
    print("   1. Installed to a custom location")
    print("   2. Not completed installation")
    print("   3. Extracted to a temporary folder")
    print("\n   Try:")
    print("   - Check the installer's default installation directory")
    print("   - Re-run the installer and note the installation path")
    print("   - Or manually download the zip version and extract it")

print("\n" + "=" * 60)

