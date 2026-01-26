@echo off
REM AWS IoT Pub/Sub GUI - Windows Launcher
REM Double-click this file to run the application

echo ========================================
echo AWS IoT Pub/Sub GUI - Feasibility Demo
echo ========================================
echo.

REM Check if Python is installed
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python is not installed or not in PATH
    echo Please install Python 3.8 or higher from https://www.python.org/
    pause
    exit /b 1
)

echo Checking Python installation...
python --version
echo.

REM Check if required packages are installed
echo Checking required packages...
python -c "import PyQt6" >nul 2>&1
if errorlevel 1 (
    echo PyQt6 not found. Installing...
    python -m pip install PyQt6
    if errorlevel 1 (
        echo ERROR: Failed to install PyQt6
        pause
        exit /b 1
    )
)

python -c "import awsiot" >nul 2>&1
if errorlevel 1 (
    echo awsiotsdk not found. Installing...
    python -m pip install awsiotsdk
    if errorlevel 1 (
        echo ERROR: Failed to install awsiotsdk
        pause
        exit /b 1
    )
)

echo All dependencies are installed.
echo.
echo Starting application...
echo.

REM Run the application
python iot_pubsub_gui.py

REM If the application exits, pause to see any error messages
if errorlevel 1 (
    echo.
    echo Application exited with an error.
    pause
)

