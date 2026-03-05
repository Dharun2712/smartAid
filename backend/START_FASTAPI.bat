@echo off
REM Robust START script for Smart-Aid FastAPI backend
REM - Ensures venv, sets UTF-8 for Python, installs requirements if missing
REM - Starts uvicorn in a separate window and redirects logs to logs\uvicorn.log

cd /d "%~dp0"

echo ============================================
echo Smart-Aid FastAPI Backend (Robust Starter)
echo ============================================

REM Force Python produce UTF-8 output on Windows consoles
set "PYTHONUTF8=1"

REM Groq API key for AI Accident Image Analysis (set your own key here)
REM set "GROQ_API_KEY=your_groq_api_key_here"

REM Ensure PYTHONPATH includes current dir so imports work when invoked from elsewhere
set "PYTHONPATH=%CD%"

REM Check for Python
where python >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found in PATH. Please install Python 3.9+ and add to PATH.
    pause
    exit /b 1
)

REM Create virtual environment if missing
if not exist "venv\Scripts\activate.bat" (
    echo [INFO] Virtual environment not found. Creating venv...
    python -m venv venv
    if errorlevel 1 (
        echo [ERROR] Failed to create virtual environment
        pause
        exit /b 1
    )
)

REM Activate venv (for package install step)
call venv\Scripts\activate.bat
if errorlevel 1 (
    echo [ERROR] Failed to activate virtual environment
    pause
    exit /b 1
)

REM Upgrade pip (best-effort)
echo [INFO] Upgrading pip (best-effort)...
python -m pip install --upgrade pip setuptools wheel >nul 2>&1

REM Install requirements if present
if exist "requirements.txt" (
    echo [INFO] Installing/Updating Python requirements from requirements.txt...
    pip install -r requirements.txt
    if errorlevel 1 (
        echo [WARNING] Pip install returned non-zero exit code. Continuing anyway.
    )
) else (
    echo [WARNING] requirements.txt not found. Skipping pip install.
)

if exist "requirements_fastapi.txt" (
    echo [INFO] Installing/Updating FastAPI requirements...
    pip install -r requirements_fastapi.txt
    if errorlevel 1 (
        echo [WARNING] Pip install returned non-zero exit code. Continuing anyway.
    )
)

REM Ensure FastAPI and Uvicorn are installed
echo [INFO] Ensuring FastAPI and Uvicorn are installed (best-effort)...
pip install fastapi "uvicorn[standard]" >nul 2>&1 || echo [WARNING] Could not ensure FastAPI/uvicorn

REM Prepare logs directory
if not exist "logs" mkdir logs

echo.
echo Server will be available at:
echo   - API Docs: http://0.0.0.0:8000/docs
echo   - API Base:  http://<host-ip>:8000 (use your host IP on LAN)
echo Logs will be written to: %CD%\logs\uvicorn.log
echo Starting server in a new window...

REM Start uvicorn using PowerShell Start-Process in a minimized window with log redirection
powershell -NoProfile -Command "Start-Process -FilePath '%CD%\venv\Scripts\python.exe' -ArgumentList '-u', '-m', 'uvicorn', 'app_fastapi:socket_app', '--host', '0.0.0.0', '--port', '8000', '--log-level', 'info' -WindowStyle Minimized -RedirectStandardOutput '%CD%\logs\uvicorn.log' -RedirectStandardError '%CD%\logs\uvicorn_err.log'"

echo [INFO] Uvicorn starting in a separate window. Use the log file to monitor: %CD%\logs\uvicorn.log
echo.
exit /b 0
