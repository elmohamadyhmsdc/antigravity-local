@echo off
REM One-time setup for venv_lora (LoRA training via kohya-ss/sd-scripts).
REM Run this yourself from "the app" directory: setup_venv_lora.bat
REM Isolated from venv_ai on purpose: sd-scripts pins its own torch/diffusers/
REM transformers versions that could otherwise conflict with Magic Undress.

py -3.10 -m venv venv_lora
call venv_lora\Scripts\activate.bat

pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121

if not exist sd-scripts (
    git clone https://github.com/kohya-ss/sd-scripts.git
)
cd sd-scripts
pip install -r requirements.txt
cd ..

echo.
echo Done. Verify with: venv_lora\Scripts\python.exe sd-scripts\train_network.py --help
