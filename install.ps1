# Interactive installer for the Plex Debrid + Zurg stack (Windows / PowerShell).
#
# Walks you through which services you want to use and starts everything with
# Docker Desktop. Run from PowerShell:
#
#     powershell -ExecutionPolicy Bypass -File .\install.ps1
#
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

function Title($t) { Write-Host "`n$t" -ForegroundColor Cyan }
function Ok($t)    { Write-Host "  [ok] $t" -ForegroundColor Green }
function Warn($t)  { Write-Host "  [!] $t" -ForegroundColor Yellow }
function Fail($t)  { Write-Host "  [x] $t" -ForegroundColor Red }

function Ask($Prompt, $Default = "") {
    if ($Default) {
        $a = Read-Host "$Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($a)) { return $Default } else { return $a }
    } else { return Read-Host $Prompt }
}
function AskSecret($Prompt) {
    $s = Read-Host $Prompt -AsSecureString
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringAuto($b) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}
function YesNo($Prompt, $Default = "Y") {
    $hint = if ($Default -eq "N") { "[y/N]" } else { "[Y/n]" }
    $a = Read-Host "$Prompt $hint"
    if ([string]::IsNullOrWhiteSpace($a)) { $a = $Default }
    return ($a -match '^[Yy]')
}

Title "Plex Debrid + Zurg - interactive installer (Windows)"
Write-Host "This will configure and start the stack with Docker Desktop. You can re-run it any time." -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# 1. Docker Desktop + Compose
# ---------------------------------------------------------------------------
Title "1) Checking Docker"
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Warn "Docker is not installed / not on PATH."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        if (YesNo "Install Docker Desktop via winget now?" "Y") {
            winget install -e --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements
            Warn "Docker Desktop installed. Start it, finish first-run setup, then re-run this script."
        }
    } else {
        Fail "Please install Docker Desktop from https://www.docker.com/products/docker-desktop/ and re-run."
    }
    exit 1
}
Ok ("Docker found: " + (docker --version))

docker compose version *> $null
if ($LASTEXITCODE -eq 0) {
    function Compose { docker compose @args }
} elseif (Get-Command docker-compose -ErrorAction SilentlyContinue) {
    function Compose { docker-compose @args }
} else {
    Fail "Docker Compose not found. Update Docker Desktop and re-run."; exit 1
}
docker info *> $null
if ($LASTEXITCODE -ne 0) { Fail "Cannot talk to Docker. Make sure Docker Desktop is running, then re-run."; exit 1 }
Ok "Docker is running"

# ---------------------------------------------------------------------------
# 2. Real-Debrid + timezone
# ---------------------------------------------------------------------------
Title "2) Real-Debrid"
Write-Host "Get your API token at: https://real-debrid.com/apitoken"
$RdToken = AskSecret "Real-Debrid API token"
while ([string]::IsNullOrWhiteSpace($RdToken)) {
    Warn "A Real-Debrid token is required (Zurg needs it)."
    $RdToken = AskSecret "Real-Debrid API token"
}
$TzValue = Ask "Timezone" "Europe/Bucharest"

# ---------------------------------------------------------------------------
# 3. Which services do you want to use?
# ---------------------------------------------------------------------------
Title "3) Content sources (what plex_debrid should watch for new content)"
$Content = @(); $Update = @()
$UseOverseerr = $false; $UsePlexSrv = $false; $UseJellyfin = $false
if (YesNo "Use your Plex Watchlist as a content source?" "Y") { $Content += "Plex" }
if (YesNo "Use Trakt lists as a content source?" "N")        { $Content += "Trakt" }
if (YesNo "Use Overseerr / Jellyseerr requests?" "N")        { $Content += "Overseerr"; $UseOverseerr = $true }
if ($Content.Count -eq 0) { Warn "No content source chosen; defaulting to Plex Watchlist."; $Content += "Plex" }

function Install-Winget($id, $name) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "  Installing $name via winget..."
        winget install -e --id $id --accept-source-agreements --accept-package-agreements
    } else {
        Warn "winget is not available; please install $name manually from its website."
    }
}

$Profiles = @()
$PlexAddress = ""; $JellyfinAddress = ""; $JellyfinApiKey = ""; $OverseerrUrl = ""; $OverseerrApiKey = ""
$NeedRclone = $false

Title "4) Media servers"
Write-Host "This installer can install Plex/Jellyfin for you (natively via winget) or connect to existing ones." -ForegroundColor DarkGray
Write-Host "On Windows the media servers run natively and read the rclone.exe drive (set up below)." -ForegroundColor DarkGray

if (YesNo "Use Plex?" "Y") {
    $UsePlexSrv = $true; $Update += "Plex Libraries"
    if (YesNo "  Install Plex Media Server here (winget)?" "Y") {
        Install-Winget "Plex.PlexMediaServer" "Plex Media Server"
        $NeedRclone = $true
        Warn "When you add Plex libraries, point them at the rclone drive set up below."
    }
    $PlexAddress = Ask "  Plex server address" "http://host.docker.internal:32400"
}

if (YesNo "Use Jellyfin?" "N") {
    $UseJellyfin = $true; $Update += "Jellyfin Libraries"
    if (YesNo "  Install Jellyfin here (winget)?" "Y") {
        Install-Winget "Jellyfin.Server" "Jellyfin"
        $NeedRclone = $true
        Warn "When you add Jellyfin libraries, point them at the rclone drive set up below."
    }
    $JellyfinAddress = Ask "  Jellyfin server address" "http://host.docker.internal:8096"
    $JellyfinApiKey  = Ask "  Jellyfin API key (blank to set later)" ""
}

if ($UseOverseerr) {
    Title "Overseerr / Jellyseerr (request manager)"
    if (YesNo "  Install Jellyseerr here in Docker?" "Y") {
        $Profiles += "jellyseerr"; $OverseerrUrl = "http://jellyseerr:5055"
        Ok "Jellyseerr will be installed in Docker ($OverseerrUrl)"
    } else {
        $OverseerrUrl = Ask "  Existing Overseerr/Jellyseerr base URL" "http://host.docker.internal:5055"
    }
    $OverseerrApiKey = Ask "  Overseerr/Jellyseerr API key (blank to set later)" ""
    $Update += "Overseerr Requests"
}

if ($Update.Count -eq 0) { Warn "No refresh target chosen; defaulting to Plex Libraries."; $Update += "Plex Libraries"; $UsePlexSrv = $true; $PlexAddress = "http://host.docker.internal:32400" }

Title "5) Library collection service (used to skip content you already own)"
Write-Host "  1) Plex Library      (recommended if you use Plex)"
Write-Host "  2) Jellyfin Library  (reads your Jellyfin library)"
Write-Host "  3) Trakt Collection"
switch (Ask "Choose 1/2/3" "1") {
    "2" { $Collection = "Jellyfin Library" }
    "3" { $Collection = "Trakt Collection" }
    default { $Collection = "Plex Library" }
}
if ($Collection -eq "Plex Library") { $Ignore = "Plex Discover Watch Status"; $IgnorePath = "" }
else { $Ignore = "Local Ignore List"; $IgnorePath = "/config" }

Title "Local Stremio addon (optional)"
Write-Host "A Torrentio-style addon you install in Stremio; resolves streams on demand via Real-Debrid." -ForegroundColor DarkGray
if (YesNo "Enable the local Stremio addon (port 7000)?" "N") { $Profiles += "addon" }

# ---------------------------------------------------------------------------
# 6. Write configs
# ---------------------------------------------------------------------------
Title "6) Writing configuration files"
New-Item -ItemType Directory -Force -Path "zurg/data" | Out-Null
if ((Test-Path "zurg/config.yml") -and -not (YesNo "zurg/config.yml exists - overwrite?" "N")) {
    Ok "Keeping existing zurg/config.yml"
} else {
    (Get-Content "zurg/config.example.yml" -Raw) -replace 'YOUR_REAL_DEBRID_API_TOKEN_HERE', $RdToken |
        Set-Content -NoNewline "zurg/config.yml"
    Ok "Wrote zurg/config.yml"
}

if ($Profiles -contains "jellyseerr") { New-Item -ItemType Directory -Force -Path "jellyseerr/config" | Out-Null }
$ProfilesCsv = ($Profiles -join ",")
@(
    "TZ=$TzValue"
    "COMPOSE_PROFILES=$ProfilesCsv"
    "PUID=1000"
    "PGID=1000"
    "PLEX_CLAIM="
    "PLEX_TOKEN="
    "TRAKT_CLIENT_ID="
    "TRAKT_CLIENT_SECRET="
    "DEBRIDLINK_CLIENT_ID="
    "ORIONOID_CLIENT_ID="
) | Set-Content ".env"
Ok "Wrote .env (TZ=$TzValue, profiles='$ProfilesCsv')"

# ---------------------------------------------------------------------------
# 7. Build image + generate settings.json
# ---------------------------------------------------------------------------
Title "7) Building the plex_debrid image"
Compose build

New-Item -ItemType Directory -Force -Path "plex_debrid/config" | Out-Null
$Generate = $true
if ((Test-Path "plex_debrid/config/settings.json") -and -not (YesNo "settings.json exists - regenerate from your answers?" "N")) {
    $Generate = $false
}
if ($Generate) {
    Write-Host "  Generating settings.json from your choices..."
    $env:PD_RD_API_KEY       = $RdToken
    $env:PD_CONTENT_SERVICES = ($Content -join ",")
    $env:PD_UPDATE_SERVICES  = ($Update -join ",")
    $env:PD_COLLECTION_SERVICE = $Collection
    $env:PD_IGNORE_SERVICES  = $Ignore
    $env:PD_IGNORE_PATH      = $IgnorePath
    $env:PD_SOURCES          = "torrentio"
    $env:PD_DEBRID_SERVICES  = "Real Debrid"
    $env:PD_PLEX_ADDRESS     = $PlexAddress
    $env:PD_JELLYFIN_ADDRESS = $JellyfinAddress
    $env:PD_JELLYFIN_API_KEY = $JellyfinApiKey
    $env:PD_OVERSEERR_URL    = $OverseerrUrl
    $env:PD_OVERSEERR_API_KEY = $OverseerrApiKey
    Compose run --rm `
        -e PD_RD_API_KEY -e PD_CONTENT_SERVICES -e PD_UPDATE_SERVICES -e PD_COLLECTION_SERVICE `
        -e PD_IGNORE_SERVICES -e PD_IGNORE_PATH -e PD_SOURCES -e PD_DEBRID_SERVICES `
        -e PD_PLEX_ADDRESS -e PD_JELLYFIN_ADDRESS -e PD_JELLYFIN_API_KEY `
        -e PD_OVERSEERR_URL -e PD_OVERSEERR_API_KEY `
        plex_debrid python generate_config.py
    Ok "settings.json generated"
}

# ---------------------------------------------------------------------------
# 8. Start the stack
# ---------------------------------------------------------------------------
Title "8) Starting the stack"
Compose up -d
Ok "Containers started"

# ---------------------------------------------------------------------------
# 9. Optional rclone mount (uses the bundled rclone.exe)
# ---------------------------------------------------------------------------
Title "9) rclone mount (optional)"
Write-Host "This mounts the Zurg WebDAV to a drive letter so Plex/Jellyfin can read it." -ForegroundColor DarkGray
Write-Host "Requires WinFsp (https://winfsp.dev) to be installed." -ForegroundColor DarkGray
$rcloneDefault = if ($NeedRclone) { "Y" } else { "N" }
if (YesNo "Set up an rclone mount now?" $rcloneDefault) {
    $rclone = Join-Path $ScriptDir "rclone.exe"
    if (-not (Test-Path $rclone)) { $rclone = "rclone" }
    $drive = Ask "Drive letter to mount to" "X"
    $confDir = Join-Path $env:APPDATA "rclone"
    New-Item -ItemType Directory -Force -Path $confDir | Out-Null
    $conf = Join-Path $confDir "rclone.conf"
    if (-not (Test-Path $conf) -or -not (Select-String -Path $conf -Pattern '^\[zurg\]' -Quiet)) {
        Add-Content $conf "`n[zurg]`ntype = webdav`nurl = http://localhost:9999/dav/`nvendor = other`npacer_min_sleep = 0"
        Ok "Added [zurg] remote to $conf"
    }
    $mountArgs = "mount zurg: ${drive}: --vfs-cache-mode full --no-modtime --dir-cache-time 10s"
    Start-Process -FilePath $rclone -ArgumentList $mountArgs -WindowStyle Hidden
    Ok "Started rclone mount on ${drive}: (running in background)"
}

# ---------------------------------------------------------------------------
# done
# ---------------------------------------------------------------------------
Title "Done! Next steps"
if ($Profiles -contains "jellyseerr") { Write-Host "  Jellyseerr:     http://localhost:5055" -ForegroundColor Green }
if ($Profiles -contains "addon")      { Write-Host "  Stremio addon:  add http://localhost:7000/manifest.json in Stremio" -ForegroundColor Green }
Write-Host @"
The stack is running.

 1. Finish logging in to any OAuth account (Plex / Trakt) via the interactive setup:

        docker compose exec plex_debrid python main.py --config-dir /config

    (or: docker attach plex_debrid  - detach with Ctrl-p Ctrl-q)

 2. Logs:         docker compose logs -f plex_debrid
 3. Zurg WebDAV:  http://localhost:9999
 4. Stop / start: docker compose down  /  docker compose up -d

Your secrets live in .env, zurg/config.yml and plex_debrid/config/settings.json
(all gitignored). Re-run this script any time to reconfigure.
"@ -ForegroundColor Green
