@echo off
cd /d "%~dp0"
echo Running Antigravity Icon Generator...
if exist "..\the app\venv\Scripts\python.exe" (
    "..\the app\venv\Scripts\python.exe" tools\generate_app_icons.py
) else (
    python tools\generate_app_icons.py
)
pause
