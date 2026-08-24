import os
import urllib.request
import zipfile
import io
import subprocess
import shutil

print("[INFO] Downloading latest BasicSR from GitHub...")
url = "https://github.com/xinntao/BasicSR/archive/refs/heads/master.zip"
response = urllib.request.urlopen(url)
zip_data = response.read()

print("[INFO] Extracting...")
if os.path.exists("temp_basicsr"):
    shutil.rmtree("temp_basicsr")

with zipfile.ZipFile(io.BytesIO(zip_data)) as z:
    z.extractall("temp_basicsr")

print("[INFO] Installing modified BasicSR natively...")
# Change directory explicitly to resolve relative path issues
os.chdir("temp_basicsr/BasicSR-master")

# Install using pip in editable mode, which often bypasses the strict PEP517 build
subprocess.run([r"..\..\venv\Scripts\python.exe", "-m", "pip", "install", "-e", "."])

print("[INFO] Going back to root and installing gfpgan...")
os.chdir("../..")
subprocess.run([r"venv\Scripts\python.exe", "-m", "pip", "install", "gfpgan"])

print("[DONE] Installation complete. Feel free to delete the temp_basicsr folder.")
