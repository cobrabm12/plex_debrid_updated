#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")"

COMPOSE="docker compose"
if ! docker compose version >/dev/null 2>&1; then
  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
  else
    echo "Docker Compose is required. Install Docker Desktop or the docker compose plugin." >&2
    exit 1
  fi
fi

echo "Starting Docker containers..."
$COMPOSE up -d

cat <<'MSG'
Done.

Plex path note:
- Linux/macOS: mount Zurg WebDAV with rclone/fstab/systemd if Plex needs a local filesystem path.
- Windows: use start_server.bat if you want the bundled rclone.exe to mount Zurg to X:.
MSG
