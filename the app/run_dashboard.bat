@echo off
echo Starting Antigravity Local Dashboard...
echo.

REM Activate virtual environment
call venv\Scripts\activate.bat

if not exist logs mkdir logs

REM Run Streamlit dashboard - tee output to logs\dashboard.log so a frozen
REM or closed console doesn't lose the trace of what happened.
REM NOTE: no 2>&1 here on purpose - redirecting a native command's stderr
REM inside PowerShell 5.1 wraps each line as a fake NativeCommandError.
REM stderr still prints straight to the console either way, it's just not
REM captured into the log file.
powershell -NoProfile -Command "streamlit run dashboard.py --logger.level=debug | Tee-Object -FilePath logs\dashboard.log"

pause
