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

IS_LINUX=false; [ "$(uname -s)" = "Linux" ] && IS_LINUX=true
NEED_RCLONE=false

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
CONTENT=(); UPDATE=(); PROFILES=()
USE_OVERSEERR=false
yesno "Use your Plex Watchlist as a content source?" "Y" && CONTENT+=("Plex")
yesno "Use Trakt lists as a content source?" "N"        && CONTENT+=("Trakt")
yesno "Use Overseerr / Jellyseerr requests?" "N"        && { CONTENT+=("Overseerr"); USE_OVERSEERR=true; }
if [ "${#CONTENT[@]}" -eq 0 ]; then warn "No content source chosen; defaulting to Plex Watchlist."; CONTENT+=("Plex"); fi

# Ask whether to deploy a server here in Docker or connect to an existing one.
# Echoes "docker" or "external". In-Docker servers need the Linux FUSE mount.
where_server() {
  local nm="$1"
  if [ "$IS_LINUX" = "true" ]; then
    if yesno "  Install $nm here in Docker?" "Y"; then echo "docker"; else echo "external"; fi
  else
    warn "Running $nm in Docker with the debrid mount needs a Linux host; using an existing/native $nm instead." >&2
    echo "external"
  fi
}

PLEX_ADDRESS=""; JELLYFIN_ADDRESS=""; JELLYFIN_API_KEY=""; OVERSEERR_URL=""; OVERSEERR_API_KEY=""; PLEX_CLAIM=""
USE_PLEX_SRV=false; USE_JELLYFIN=false

title "4) Media servers"
echo "${DIM}This installer can deploy Plex/Jellyfin for you (Linux) or connect to ones you already run.${RST}"

if yesno "Use Plex?" "Y"; then
  USE_PLEX_SRV=true; UPDATE+=("Plex Libraries")
  if [ "$(where_server "Plex")" = "docker" ]; then
    PROFILES+=("plex"); NEED_RCLONE=true; PLEX_ADDRESS="http://plex:32400"
    echo "  ${DIM}Optional: a claim token from https://plex.tv/claim auto-links this server to your account.${RST}"
    PLEX_CLAIM="$(ask "  Plex claim token (optional, expires in ~4 min)" "")"
    ok "Plex will be installed in Docker ($PLEX_ADDRESS)"
  else
    PLEX_ADDRESS="$(ask "  Existing Plex server address" "http://host.docker.internal:32400")"
  fi
fi

if yesno "Use Jellyfin?" "N"; then
  USE_JELLYFIN=true; UPDATE+=("Jellyfin Libraries")
  if [ "$(where_server "Jellyfin")" = "docker" ]; then
    PROFILES+=("jellyfin"); NEED_RCLONE=true; JELLYFIN_ADDRESS="http://jellyfin:8096"
    ok "Jellyfin will be installed in Docker ($JELLYFIN_ADDRESS)"
    warn "After first launch create a Jellyfin API key (Dashboard -> API Keys) and add it via the plex_debrid menu."
  else
    JELLYFIN_ADDRESS="$(ask "  Existing Jellyfin server address" "http://host.docker.internal:8096")"
  fi
  JELLYFIN_API_KEY="$(ask "  Jellyfin API key (blank to set later)" "")"
fi

if $USE_OVERSEERR; then
  title "Overseerr / Jellyseerr (request manager)"
  if [ "$IS_LINUX" = "true" ] && yesno "  Install Jellyseerr here in Docker?" "Y"; then
    PROFILES+=("jellyseerr"); OVERSEERR_URL="http://jellyseerr:5055"
    ok "Jellyseerr will be installed in Docker ($OVERSEERR_URL)"
    warn "After first launch create an API key in Jellyseerr and add it via the plex_debrid menu."
  else
    OVERSEERR_URL="$(ask "  Existing Overseerr/Jellyseerr base URL" "http://host.docker.internal:5055")"
  fi
  OVERSEERR_API_KEY="$(ask "  Overseerr/Jellyseerr API key (blank to set later)" "")"
  UPDATE+=("Overseerr Requests")
fi

if [ "${#UPDATE[@]}" -eq 0 ]; then
  warn "No refresh target chosen; defaulting to Plex Libraries."
  UPDATE+=("Plex Libraries"); USE_PLEX_SRV=true; PLEX_ADDRESS="${PLEX_ADDRESS:-http://host.docker.internal:32400}"
fi

title "5) Library collection service (used to skip content you already own)"
echo "  1) Plex Library      (recommended if you use Plex)"
echo "  2) Jellyfin Library  (reads your Jellyfin library)"
echo "  3) Trakt Collection"
case "$(ask "Choose 1/2/3" "1")" in
  2) COLLECTION="Jellyfin Library" ;;
  3) COLLECTION="Trakt Collection" ;;
  *) COLLECTION="Plex Library" ;;
esac

# ignore service: Plex watch-status only makes sense with Plex collection
if [ "$COLLECTION" = "Plex Library" ]; then IGNORE="Plex Discover Watch Status"; IGNORE_PATH=""
else IGNORE="Local Ignore List"; IGNORE_PATH="/config"; fi
$NEED_RCLONE && PROFILES+=("rclone")

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

# rclone config + shared data dir for in-Docker media servers
if $NEED_RCLONE; then
  mkdir -p data rclone
  if [ ! -f rclone/rclone.conf ]; then cp rclone/rclone.example.conf rclone/rclone.conf; ok "Wrote rclone/rclone.conf"; fi
fi
case " ${PROFILES[*]} " in *" plex "*)       mkdir -p plex/config ;; esac
case " ${PROFILES[*]} " in *" jellyfin "*)   mkdir -p jellyfin/config ;; esac
case " ${PROFILES[*]} " in *" jellyseerr "*) mkdir -p jellyseerr/config ;; esac

PROFILES_CSV="$( [ "${#PROFILES[@]}" -gt 0 ] && (IFS=,; echo "${PROFILES[*]}") || echo "" )"
PUID_VAL="$( $IS_LINUX && id -u 2>/dev/null || echo 1000 )"
PGID_VAL="$( $IS_LINUX && id -g 2>/dev/null || echo 1000 )"

# .env
{
  echo "TZ=$TZ_VALUE"
  echo "COMPOSE_PROFILES=$PROFILES_CSV"
  echo "PUID=$PUID_VAL"
  echo "PGID=$PGID_VAL"
  echo "PLEX_CLAIM=$PLEX_CLAIM"
  echo "PLEX_TOKEN="
  echo "TRAKT_CLIENT_ID="
  echo "TRAKT_CLIENT_SECRET="
  echo "DEBRIDLINK_CLIENT_ID="
  echo "ORIONOID_CLIENT_ID="
} > .env
ok "Wrote .env (TZ=$TZ_VALUE, profiles='${PROFILES_CSV:-none}')"

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
if [ "${#PROFILES[@]}" -gt 0 ]; then
  echo "${BOLD}Services deployed by this installer:${RST}"
  case " ${PROFILES[*]} " in *" plex "*)       echo "  • Plex:       http://localhost:32400/web  — add a library pointing at /data";; esac
  case " ${PROFILES[*]} " in *" jellyfin "*)   echo "  • Jellyfin:   http://localhost:8096        — add a library pointing at /data";; esac
  case " ${PROFILES[*]} " in *" jellyseerr "*) echo "  • Jellyseerr: http://localhost:5055";; esac
  case " ${PROFILES[*]} " in *" rclone "*)     echo "  • Debrid mount is shared with the servers at /data (host folder: ./data)";; esac
  echo ""
fi
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
