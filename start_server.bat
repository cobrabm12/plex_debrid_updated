@echo off
setlocal
cd /d "%~dp0"

where docker >nul 2>nul
if errorlevel 1 (
    echo Docker is required. Install Docker Desktop and try again.
    exit /b 1
)

echo Starting Docker containers...
docker compose up -d
if errorlevel 1 (
    echo docker compose failed. Make sure Docker Desktop is running.
    exit /b 1
)

if not exist "rclone.exe" (
    echo rclone.exe was not found. Docker was started, but Zurg was not mounted to X:.
    echo Download rclone for Windows or mount Zurg manually if Plex needs a local drive.
    exit /b 0
)

echo Mounting Zurg to X: drive...
:: Check if X: is already mounted
if exist X:\ (
    echo Drive X: is already mounted.
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%CD%\rclone.exe' -ArgumentList 'mount zurg: X: --no-checksum --no-modtime --ignore-size --vfs-cache-mode full --log-file rclone_mount.log --log-level INFO' -WindowStyle Hidden"
)

echo Done.
endlocal
