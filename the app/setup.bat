@echo off
echo ========================================
echo  Antigravity Local - Setup Script
echo ========================================
echo.

REM Check if venv exists
if not exist "venv" (
    echo Creating virtual environment...
    python -m venv venv
    echo Virtual environment created.
)

echo Activating virtual environment...
call venv\Scripts\activate.bat

echo.
echo Installing dependencies...
pip install -r requirements.txt

echo.
echo Installing onnxruntime-gpu for GPU-accelerated face processing...
pip install onnxruntime-gpu

echo.
echo ========================================
echo  Setup complete!
echo ========================================
echo.
echo Next step:
echo   Run: streamlit run dashboard.py    (to start the UI)
echo   Or double-click run_dashboard.bat
echo.
pause
