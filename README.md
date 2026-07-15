# Plex Debrid & Zurg Setup

This repository contains a complete setup for streaming content using Plex, Real-Debrid, Zurg, and Plex Debrid.

## Prerequisites

- [Docker](https://www.docker.com/) and [Docker Compose](https://docs.docker.com/compose/)
- A [Real-Debrid](https://real-debrid.com/) account (Premium required)
- A [Plex](https://www.plex.tv/) server
- [Trakt.tv](https://trakt.tv/) account (optional but recommended)

## Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/cobrabm12/plex_debrid_trakt.git
    cd plex_debrid_trakt
    ```

2.  **Configure Zurg:**
    - Copy `zurg/config.example.yml` to `zurg/config.yml`.
    - Edit `zurg/config.yml` and add your Real-Debrid API Token.
    ```yaml
    zurg: v1
    token: YOUR_REAL_DEBRID_API_TOKEN
    ```

3.  **Configure Plex Debrid:**
    - Copy `plex_debrid/config/settings.example.json` to `plex_debrid/config/settings.json`.
    - Edit `plex_debrid/config/settings.json` and fill in the required fields:
        - `Plex users`: Your Plex username and token.
        - `Trakt users`: Your Trakt client ID and secret (if using Trakt).
        - `Real Debrid API Key`: Your Real-Debrid API Key.
        - `Plex server address`: Address of your Plex server. Use `http://host.docker.internal:32400` when Plex runs on the Docker host (Windows, macOS, and Linux with this compose file). Use your LAN URL such as `http://192.168.1.10:32400` when Plex runs on another machine.

4.  **Run the stack:**
    ```bash
    docker-compose up -d
    ```


## Operating system compatibility

- **Docker stack:** The compose setup is the recommended cross-platform path and works on Linux, macOS, and Windows with Docker Compose.
- **Plex host access:** The compose file maps `host.docker.internal` to the Docker host, including Linux via `host-gateway`, so `plex_debrid` can reach a Plex server running on the same machine.
- **Windows helper:** Run `start_server.bat` to start Docker and mount Zurg to `X:` with the bundled `rclone.exe`.
- **Linux/macOS helper:** Run `./start_stack.sh` to start the Docker stack. Mount Zurg separately with your system rclone/WebDAV setup if Plex needs filesystem access outside Docker.
- **Remote Plex server:** Set `Plex server address` to the remote LAN address, for example `http://192.168.1.10:32400`, and make sure the Plex token in `settings.json` belongs to a user allowed to access that server.

## Plex compatibility notes

- Plex watchlist monitoring uses the Plex metadata/discover endpoints with your Plex token.
- Plex library refresh uses the local Plex server URL from `Plex server address`; partial scans require Plex to see the same media paths that Zurg/rclone exposes.
- If Plex runs outside Docker, keep the Plex library path and rclone mount path consistent for the operating system running Plex. For example, Windows Plex can scan `X:\`, while Linux Plex usually needs a mounted directory such as `/mnt/zurg`.

## Usage

- **Zurg** will mount your Real-Debrid torrents as a WebDAV directory.
- **Plex Debrid** will monitor your Plex Watchlist (or Trakt watchlist) and automatically add movies/shows to Real-Debrid via Zurg.
- **Rclone** (optional, if used) can mount the Zurg WebDAV to a local drive letter for Plex to read.

## Notes

- The `plex_debrid_src` folder contains the source code for `plex_debrid`. It has been patched to fix User-Agent issues with Torrentio and to handle Real-Debrid API limitations.
- **Do not commit `zurg/config.yml` or `plex_debrid/config/settings.json` to a public repository as they contain your private API keys.**

## Credits

- **Original Project:** [plex_debrid](https://github.com/itsToggle/plex_debrid) by [itsToggle](https://github.com/itsToggle).
- **Adapted & Updated by:** [cobrabm12](https://github.com/cobrabm12) - Updated for Docker compatibility, fixed Torrentio scraping issues, and optimized for current Real-Debrid API requirements.

## Troubleshooting

- Check logs with: `docker-compose logs -f`
- If Torrentio scraping fails, ensure the User-Agent fix in `plex_debrid_src/scraper/services/torrentio.py` is active.
