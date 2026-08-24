@echo off
echo Fixing ONNX Runtime CUDA Environment...
call venv\Scripts\activate.bat
pip uninstall -y onnxruntime onnxruntime-gpu
pip install onnxruntime-gpu==1.18.1
echo Done!
