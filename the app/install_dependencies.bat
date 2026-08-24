@echo off
echo Installing PyTorch with CUDA 12.1 support...
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
if %errorlevel% neq 0 (
    echo PyTorch installation failed!
    exit /b %errorlevel%
)

echo Installing other dependencies...
pip install -r requirements.txt
if %errorlevel% neq 0 (
    echo Dependencies installation failed!
    exit /b %errorlevel%
)

echo Installation complete.
pause
