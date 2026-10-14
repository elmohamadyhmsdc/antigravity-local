@echo off
REM Antigravity Mobile API - the GPU server the phone app talks to (HTTPS, same Wi-Fi only).
REM Opens the pairing page (http://127.0.0.1:8444/pair, reachable from this PC only).
REM
REM First run: Windows asks whether python.exe may accept connections - allow "Private networks"
REM so your phone can reach it. This script never changes firewall rules. If the phone cannot
REM connect, run this once in an ADMIN prompt (it is your decision, not done for you):
REM   netsh advfirewall firewall add rule name="Antigravity Mobile API" dir=in action=allow protocol=TCP localport=8443 profile=private
REM
REM Options (--name, --port, --no-mdns, ...): venv\Scripts\python -m mobile_api --help
echo Starting Antigravity Mobile API...
echo.

call venv\Scripts\activate.bat

if not exist logs mkdir logs

REM Same logging approach as run_dashboard.bat: tee into logs\ so a closed console keeps its trace.
powershell -NoProfile -Command "python -m mobile_api | Tee-Object -FilePath logs\mobile_api.log"

pause
