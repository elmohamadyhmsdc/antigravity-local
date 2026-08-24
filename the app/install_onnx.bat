@echo off
echo Installing ONNX Runtime and cuDNN 9...
call venv\Scripts\activate.bat
pip install onnxruntime-gpu nvidia-cudnn-cu12 > pip_install_log.txt 2>&1
echo Done!
