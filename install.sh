#!/usr/bin/env bash
#
# Interactive installer for the Plex Debrid + Zurg stack (Linux / macOS).
# Works on any distribution: it auto-detects your package manager / OS and can
# install Docker for you, then walks you through which services you want to use
# and starts everything with docker compose.
#
# Usage:   ./install.sh
#
set -euo pipefail

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  BOLD="$(printf '\033[1m')"; DIM="$(printf '\033[2m')"; RED="$(printf '\033[31m')"
  GRN="$(printf '\033[32m')"; YEL="$(printf '\033[33m')"; BLU="$(printf '\033[36m')"; RST="$(printf '\033[0m')"
else
  BOLD=""; DIM=""; RED=""; GRN=""; YEL=""; BLU=""; RST=""
fi
info()  { printf '%s\n' "${BLU}==>${RST} $*"; }
ok()    { printf '%s\n' "${GRN}  ✓${RST} $*"; }
warn()  { printf '%s\n' "${YEL}  ! ${RST}$*"; }
err()   { printf '%s\n' "${RED}  ✗ ${RST}$*" >&2; }
title() { printf '\n%s\n' "${BOLD}$*${RST}"; }

# ask "Prompt" "default" -> echoes answer
ask() {
  local prompt="$1" def="${2:-}" ans
  if [ -n "$def" ]; then read -r -p "$prompt [$def]: " ans || true; echo "${ans:-$def}";
  else read -r -p "$prompt: " ans || true; echo "$ans"; fi
}
ask_secret() {
  local prompt="$1" ans
  read -r -s -p "$prompt: " ans || true; echo >&2; echo "$ans"
}
# yesno "Prompt" "Y|N" -> returns 0 for yes
yesno() {
  local prompt="$1" def="${2:-Y}" ans
  local hint="[Y/n]"; [ "$def" = "N" ] && hint="[y/N]"
  read -r -p "$prompt $hint: " ans || true
  ans="${ans:-$def}"
  case "$ans" in [Yy]*) return 0;; *) return 1;; esac
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

title "Plex Debrid + Zurg — interactive installer"
echo "${DIM}This will configure and start the stack with Docker. You can re-run it any time.${RST}"

# ---------------------------------------------------------------------------
# 1. Docker + Docker Compose
# ---------------------------------------------------------------------------
title "1) Checking Docker"

detect_pkg_mgr() {
  for m in apt-get dnf yum pacman zypper apk emerge; do
    if command -v "$m" >/dev/null 2>&1; then echo "$m"; return; fi
  done
  echo ""
}

install_docker() {
  local os; os="$(uname -s)"
  if [ "$os" = "Darwin" ]; then
    err "Docker Desktop for Mac is required. Install it from https://www.docker.com/products/docker-desktop/ and re-run."
    exit 1
  fi
  local pm; pm="$(detect_pkg_mgr)"
  info "Installing Docker (detected package manager: ${pm:-unknown})"
  case "$pm" in
    pacman)
      sudo pacman -Sy --noconfirm docker docker-compose ;;
    apk)
      sudo apk add --no-cache docker docker-cli-compose && sudo rc-update add docker boot || true ;;
    *)
      # Official convenience script — supports Debian/Ubuntu/Fedora/CentOS/openSUSE/etc.
      if command -v curl >/dev/null 2>&1; then curl -fsSL https://get.docker.com | sudo sh
      elif command -v wget >/dev/null 2>&1; then wget -qO- https://get.docker.com | sudo sh
      else err "Need curl or wget to install Docker. Please install Docker manually."; exit 1; fi ;;
  esac
  sudo systemctl enable --now docker 2>/dev/null || sudo service docker start 2>/dev/null || true
  if command -v usermod >/dev/null 2>&1 && [ -n "${USER:-}" ]; then
    sudo usermod -aG docker "$USER" 2>/dev/null || true
    warn "Added '$USER' to the 'docker' group. You may need to log out/in for it to take effect."
  fi
}

if ! command -v docker >/dev/null 2>&1; then
  warn "Docker is not installed."
  if yesno "Install Docker now?" "Y"; then install_docker; else err "Docker is required. Aborting."; exit 1; fi
else
  ok "Docker found: $(docker --version 2>/dev/null | head -1)"
fi

# choose compose command (v2 plugin preferred)
if docker compose version >/dev/null 2>&1; then DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then DC="docker-compose"
else
  warn "Docker Compose not found; the official script normally installs the v2 plugin."
  err "Please install the Docker Compose plugin and re-run."; exit 1
fi
ok "Using compose command: ${BOLD}$DC${RST}"

# verify the docker daemon is reachable
if ! docker info >/dev/null 2>&1; then
  err "Cannot talk to the Docker daemon. Start Docker (or re-login for group changes) and re-run."
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Real-Debrid + timezone
# ---------------------------------------------------------------------------
title "2) Real-Debrid"
echo "Get your API token at: ${BOLD}https://real-debrid.com/apitoken${RST}"
RD_TOKEN="$(ask_secret "Real-Debrid API token")"
while [ -z "$RD_TOKEN" ]; do
  warn "A Real-Debrid token is required (Zurg needs it)."
  RD_TOKEN="$(ask_secret "Real-Debrid API token")"
done

DEF_TZ="Europe/Bucharest"
if command -v timedatectl >/dev/null 2>&1; then DEF_TZ="$(timedatectl show -p Timezone --value 2>/dev/null || echo "$DEF_TZ")"; fi
[ -f /etc/timezone ] && DEF_TZ="$(cat /etc/timezone 2>/dev/null || echo "$DEF_TZ")"
TZ_VALUE="$(ask "Timezone" "$DEF_TZ")"

# ---------------------------------------------------------------------------
# 3. Which services do you want to use?
# ---------------------------------------------------------------------------
title "3) Content sources (what plex_debrid should watch for new content)"
CONTENT=(); UPDATE=();
USE_PLEX_WL=false; USE_TRAKT=false; USE_OVERSEERR=false
yesno "Use your Plex Watchlist as a content source?" "Y" && { CONTENT+=("Plex"); USE_PLEX_WL=true; }
yesno "Use Trakt lists as a content source?" "N"        && { CONTENT+=("Trakt"); USE_TRAKT=true; }
yesno "Use Overseerr / Jellyseerr requests?" "N"        && { CONTENT+=("Overseerr"); USE_OVERSEERR=true; }
if [ "${#CONTENT[@]}" -eq 0 ]; then warn "No content source chosen; defaulting to Plex Watchlist."; CONTENT+=("Plex"); USE_PLEX_WL=true; fi

title "4) Media server(s) to refresh after a download"
USE_PLEX_SRV=false; USE_JELLYFIN=false
yesno "Refresh a Plex server?" "Y"     && { UPDATE+=("Plex Libraries"); USE_PLEX_SRV=true; }
yesno "Refresh a Jellyfin server?" "N" && { UPDATE+=("Jellyfin Libraries"); USE_JELLYFIN=true; }
$USE_OVERSEERR && UPDATE+=("Overseerr Requests")
if [ "${#UPDATE[@]}" -eq 0 ]; then warn "No refresh target chosen; defaulting to Plex Libraries."; UPDATE+=("Plex Libraries"); USE_PLEX_SRV=true; fi

title "5) Library collection service (used to skip content you already own)"
echo "  1) Plex Library      (recommended if you use Plex)"
echo "  2) Jellyfin Library  (reads your Jellyfin library)"
echo "  3) Trakt Collection"
COL_CHOICE="$(ask "Choose 1/2/3" "1")"
case "$COL_CHOICE" in
  2) COLLECTION="Jellyfin Library"; USE_JELLYFIN=true ;;
  3) COLLECTION="Trakt Collection"; USE_TRAKT=true ;;
  *) COLLECTION="Plex Library"; USE_PLEX_SRV=true ;;
esac

# ignore service: Plex watch-status only makes sense with Plex collection
if [ "$COLLECTION" = "Plex Library" ]; then IGNORE="Plex Discover Watch Status"; IGNORE_PATH=""
else IGNORE="Local Ignore List"; IGNORE_PATH="/config"; fi

# addresses / keys
PLEX_ADDRESS=""; JELLYFIN_ADDRESS=""; JELLYFIN_API_KEY=""; OVERSEERR_URL=""; OVERSEERR_API_KEY=""
if $USE_PLEX_SRV; then
  title "Plex server"
  echo "${DIM}Inside Docker, your host is reachable as host.docker.internal.${RST}"
  PLEX_ADDRESS="$(ask "Plex server address" "http://host.docker.internal:32400")"
fi
if $USE_JELLYFIN; then
  title "Jellyfin server"
  JELLYFIN_ADDRESS="$(ask "Jellyfin server address" "http://host.docker.internal:8096")"
  JELLYFIN_API_KEY="$(ask "Jellyfin API key (Dashboard -> API Keys, leave blank to set later)" "")"
fi
if $USE_OVERSEERR; then
  title "Overseerr / Jellyseerr"
  OVERSEERR_URL="$(ask "Overseerr/Jellyseerr base URL" "http://host.docker.internal:5055")"
  OVERSEERR_API_KEY="$(ask "Overseerr/Jellyseerr API key (leave blank to set later)" "")"
fi

# ---------------------------------------------------------------------------
# 6. Write configs
# ---------------------------------------------------------------------------
title "6) Writing configuration files"

# zurg/config.yml
mkdir -p zurg/data
if [ -f zurg/config.yml ] && ! yesno "zurg/config.yml exists — overwrite?" "N"; then
  ok "Keeping existing zurg/config.yml"
else
  sed "s|YOUR_REAL_DEBRID_API_TOKEN_HERE|$RD_TOKEN|" zurg/config.example.yml > zurg/config.yml
  ok "Wrote zurg/config.yml"
fi

# .env
{
  echo "TZ=$TZ_VALUE"
  echo "PLEX_TOKEN="
  echo "TRAKT_CLIENT_ID="
  echo "TRAKT_CLIENT_SECRET="
  echo "DEBRIDLINK_CLIENT_ID="
  echo "ORIONOID_CLIENT_ID="
} > .env
ok "Wrote .env (TZ=$TZ_VALUE)"

# ---------------------------------------------------------------------------
# 7. Build image + generate settings.json
# ---------------------------------------------------------------------------
title "7) Building the plex_debrid image"
$DC build

mkdir -p plex_debrid/config
GEN=true
if [ -f plex_debrid/config/settings.json ]; then
  yesno "plex_debrid/config/settings.json exists — regenerate from your answers?" "N" || GEN=false
fi
if $GEN; then
  info "Generating settings.json from your choices"
  export PD_RD_API_KEY="$RD_TOKEN"
  export PD_CONTENT_SERVICES; PD_CONTENT_SERVICES="$(IFS=,; echo "${CONTENT[*]}")"
  export PD_UPDATE_SERVICES;  PD_UPDATE_SERVICES="$(IFS=,; echo "${UPDATE[*]}")"
  export PD_COLLECTION_SERVICE="$COLLECTION"
  export PD_IGNORE_SERVICES="$IGNORE"
  export PD_IGNORE_PATH="$IGNORE_PATH"
  export PD_SOURCES="torrentio"
  export PD_DEBRID_SERVICES="Real Debrid"
  export PD_PLEX_ADDRESS="$PLEX_ADDRESS"
  export PD_JELLYFIN_ADDRESS="$JELLYFIN_ADDRESS"
  export PD_JELLYFIN_API_KEY="$JELLYFIN_API_KEY"
  export PD_OVERSEERR_URL="$OVERSEERR_URL"
  export PD_OVERSEERR_API_KEY="$OVERSEERR_API_KEY"
  $DC run --rm \
    -e PD_RD_API_KEY -e PD_CONTENT_SERVICES -e PD_UPDATE_SERVICES -e PD_COLLECTION_SERVICE \
    -e PD_IGNORE_SERVICES -e PD_IGNORE_PATH -e PD_SOURCES -e PD_DEBRID_SERVICES \
    -e PD_PLEX_ADDRESS -e PD_JELLYFIN_ADDRESS -e PD_JELLYFIN_API_KEY \
    -e PD_OVERSEERR_URL -e PD_OVERSEERR_API_KEY \
    plex_debrid python generate_config.py
  ok "settings.json generated"
fi

# ---------------------------------------------------------------------------
# 8. Start the stack
# ---------------------------------------------------------------------------
title "8) Starting the stack"
$DC up -d
ok "Containers started"

# ---------------------------------------------------------------------------
# 9. Optional rclone mount
# ---------------------------------------------------------------------------
title "9) rclone mount (optional)"
echo "${DIM}This mounts the Zurg WebDAV so Plex/Jellyfin can read the files as a folder.${RST}"
if yesno "Set up an rclone mount now?" "N"; then
  if ! command -v rclone >/dev/null 2>&1; then
    if yesno "rclone is not installed — install it?" "Y"; then
      curl -fsSL https://rclone.org/install.sh | sudo bash || warn "rclone install failed; install it manually from https://rclone.org"
    fi
  fi
  if command -v rclone >/dev/null 2>&1; then
    MP="$(ask "Mount point" "$HOME/zurg")"
    mkdir -p "$MP"
    RCONF="$HOME/.config/rclone/rclone.conf"; mkdir -p "$(dirname "$RCONF")"
    if ! grep -q "^\[zurg\]" "$RCONF" 2>/dev/null; then
      { echo "[zurg]"; echo "type = webdav"; echo "url = http://localhost:9999/dav/"; echo "vendor = other"; echo "pacer_min_sleep = 0"; } >> "$RCONF"
      ok "Added [zurg] remote to $RCONF"
    fi
    info "Mounting zurg: -> $MP (background)"
    rclone mount zurg: "$MP" --dir-cache-time 10s --vfs-cache-mode full --no-modtime --daemon \
      && ok "Mounted at $MP" || warn "Mount failed; check 'rclone mount' manually."
  fi
fi

# ---------------------------------------------------------------------------
# done
# ---------------------------------------------------------------------------
title "Done! Next steps"
cat <<EOF
${GRN}The stack is running.${RST}

 1. Finish logging in to any account that uses OAuth (Plex / Trakt) by attaching
    to the interactive setup:

        ${BOLD}$DC exec plex_debrid python main.py --config-dir /config${RST}

    (or open the menu with: ${BOLD}docker attach plex_debrid${RST} — detach with Ctrl-p Ctrl-q)

 2. Logs:            ${BOLD}$DC logs -f plex_debrid${RST}
 3. Zurg WebDAV:     ${BOLD}http://localhost:9999${RST}
 4. Stop / start:    ${BOLD}$DC down${RST}  /  ${BOLD}$DC up -d${RST}

Your secrets live in ${BOLD}.env${RST}, ${BOLD}zurg/config.yml${RST} and ${BOLD}plex_debrid/config/settings.json${RST}
(all gitignored). Re-run ${BOLD}./install.sh${RST} any time to reconfigure.
EOF
