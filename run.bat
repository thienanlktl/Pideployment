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

REM Pull latest code from git if in a git repository
if exist ".git" (
    echo Pulling latest code from git...
    set GIT_BRANCH=main
    
    REM Check git remote configuration
    git remote get-url origin >nul 2>&1
    if %errorlevel% equ 0 (
        echo Git remote found
        
        REM Ensure we're on the correct branch
        for /f "tokens=*" %%b in ('git branch --show-current 2^>nul') do set CURRENT_BRANCH=%%b
        if not "%CURRENT_BRANCH%"=="%GIT_BRANCH%" (
            echo Switching to %GIT_BRANCH% branch...
            git checkout %GIT_BRANCH% >nul 2>&1
        )
        
        REM Pull latest code
        git pull origin %GIT_BRANCH% >nul 2>&1
        if %errorlevel% equ 0 (
            echo Successfully pulled latest code from git
        ) else (
            echo Warning: Failed to pull latest code from git, continuing with current code...
        )
    ) else (
        echo Warning: No git remote found, skipping git pull
    )
) else (
    echo Not a git repository, skipping git pull
)

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

