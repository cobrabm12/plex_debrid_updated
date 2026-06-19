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
    git clone https://github.com/cobrabm12/plex_debrid_updated.git
    cd plex_debrid_updated
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
        - `Plex server address`: Address of your Plex server (e.g., `http://host.docker.internal:32400`).

4.  **Run the stack:**
    ```bash
    docker-compose up -d
    ```

## Usage

- **Zurg** will mount your Real-Debrid torrents as a WebDAV directory.
- **Plex Debrid** will monitor your Plex Watchlist (or Trakt watchlist) and automatically add movies/shows to Real-Debrid via Zurg.
- **Rclone** (optional, if used) can mount the Zurg WebDAV to a local drive letter for Plex to read.

## Using Jellyfin (alongside or instead of Plex)

Jellyfin has **no built-in watchlist**, so it cannot be a *content source* (the
"what to download" list). For a Jellyfin-based or mixed Plex + Jellyfin setup,
configure plex_debrid like this (all options are in the in-app settings menu under
`Options/Settings`):

- **Content source** (what to download): use **Trakt** lists, and/or **Jellyseerr**
  /**Overseerr** requests (Jellyseerr is API-compatible — set it up as the "Overseerr"
  service). On a mixed setup you can also keep the **Plex** watchlist enabled.
- **Library collection service** (what you already own, to avoid re-downloading):
  choose **Jellyfin Library** *or* **Plex Library**. Because Plex and Jellyfin read
  the same Zurg/Real-Debrid mount, either one reflects the same content. `Jellyfin
  Library` reads your Jellyfin library via the Jellyfin API and matches items by their
  IMDb/TMDb/TVDb provider IDs.
- **Library update services** (refresh after a download): enable **Jellyfin Libraries**
  and/or **Plex Libraries** — you can enable both at once when running them in parallel.

To configure Jellyfin, set your **Jellyfin API Key** (Jellyfin Dashboard → API Keys)
and **Jellyfin server address** (e.g. `http://host.docker.internal:8096`) in the
settings menu.

## Notes

- The `plex_debrid_src` folder contains the source code for `plex_debrid`. It has been patched to fix User-Agent issues with Torrentio and to handle Real-Debrid API limitations.
- The core `plex_debrid_src/releases/` package was previously excluded from version control by a stray Visual Studio `.gitignore` rule (`[Rr]eleases/`). The `.gitignore` has been corrected and the package restored, otherwise the app fails to start with `ModuleNotFoundError: No module named 'releases'`.
- **Do not commit `zurg/config.yml` or `plex_debrid/config/settings.json` to a public repository as they contain your private API keys.**
- `check_watchlist.py` reads your Plex token from the `PLEX_TOKEN` environment variable (or the first CLI argument) — it is no longer hard-coded.
- **Credentials via environment variables:** the OAuth app credentials (`TRAKT_CLIENT_ID`,
  `TRAKT_CLIENT_SECRET`, `DEBRIDLINK_CLIENT_ID`, `ORIONOID_CLIENT_ID`) and `PLEX_TOKEN`
  can be supplied through environment variables instead of being hard-coded. Copy
  `.env.example` to `.env` (gitignored) and fill in only what you want to override; any
  value left empty falls back to the shared public plex_debrid defaults, so the stack
  still works out of the box. `docker-compose` automatically loads `.env`. Your personal
  Plex token, Real-Debrid key, etc. are still entered in the in-app settings menu and
  stored in the gitignored `plex_debrid/config/settings.json` — never in the source.
- **Plex API change (late 2025/2026):** Plex deprecated the `metadata.provider.plex.tv`
  endpoints for the watchlist. The Plex integration now uses `discover.provider.plex.tv`
  for the watchlist, add/remove-from-watchlist and search operations (matching the
  canonical `python-plexapi` library); metadata and watch-status (scrobble) calls still
  use `metadata.provider.plex.tv`, which remains active. If your Plex watchlist ever
  returns `404`, ensure you are on this updated version.
- **Real-Debrid API change (Nov 2024):** Real-Debrid disabled the data returned by the
  `/torrents/instantAvailability` endpoint, which plex_debrid relied on to detect cached
  torrents in a single batch call. The Real-Debrid integration now falls back to *probing*
  each release (add magnet → read `/torrents/info` → detect cached status → remove the
  probe torrent) when instant-availability data is missing. This is heavier than the old
  batch check (a few API calls per release, bounded by `MAX_CHECK` in
  `debrid/services/realdebrid.py`) and **should be tested against your own Real-Debrid
  account** — it could not be verified here without live credentials.
- The `rarbg` scraper (`scraper/services/rarbg.py`) targets `torrentapi.org`, which shut
  down in 2023; it is non-functional and not part of the default sources. Use `torrentio`.

## Credits

- **Original Project:** [plex_debrid](https://github.com/itsToggle/plex_debrid) by [itsToggle](https://github.com/itsToggle).
- **Adapted & Updated by:** [cobrabm12](https://github.com/cobrabm12) - Updated for Docker compatibility, fixed Torrentio scraping issues, and optimized for current Real-Debrid API requirements.

## Troubleshooting

- Check logs with: `docker-compose logs -f`
- If Torrentio scraping fails, ensure the User-Agent fix in `plex_debrid_src/scraper/services/torrentio.py` is active.
