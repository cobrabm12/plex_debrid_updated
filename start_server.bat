@echo off
cd /d "%~dp0"

echo Starting Docker containers...
docker compose up -d

echo Mounting Zurg to X: drive...
:: Check if X: is already mounted
if exist X:\ (
    echo Drive X: is already mounted.
) else (
    powershell -Command "Start-Process -FilePath 'rclone.exe' -ArgumentList 'mount zurg: X: --no-checksum --no-modtime --ignore-size --vfs-cache-mode full --log-file rclone_mount.log --log-level INFO' -WindowStyle Hidden"
)

echo Done.
