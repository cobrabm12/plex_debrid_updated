#!/usr/bin/env python3
"""A local, Torrentio-style Stremio addon powered by plex_debrid.

It reuses plex_debrid's scrapers to find torrents and Real-Debrid to turn them
into instantly-playable links, exposing the Stremio addon protocol so you can
install it in Stremio (Desktop / Web / Android / TV).

Install URL (in Stremio):  http://<host>:7000/manifest.json

Because Real-Debrid disabled batch instant-availability lookups, links are
resolved on click: each stream points back at this addon's /playback endpoint,
which adds the magnet to Real-Debrid, picks the right file, unrestricts it and
redirects the player to the direct link.

Config (env vars):
  ADDON_PORT        listen port (default 7000)
  RD_API_KEY        Real-Debrid API key (else read from <PD_CONFIG_DIR>/settings.json)
  PD_CONFIG_DIR     config dir to read settings.json from (default /config)
  ADDON_SOURCES     comma-separated scrapers to use (default: torrentio)
"""
import os
import re
import sys
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.argv = ["stremio_addon.py"]
# importing ui first resolves plex_debrid's package import order
import ui  # noqa: F401
import scraper.services as scraper_services
from scraper.services import torrentio
from debrid.services import realdebrid

RD = "https://api.real-debrid.com/rest/1.0"
VIDEO_EXT = (".mkv", ".mp4", ".avi", ".m4v", ".ts", ".mov", ".wmv", ".webm", ".mpg", ".mpeg")
PORT = int(os.environ.get("ADDON_PORT", "7000"))


def load_rd_key():
    key = os.environ.get("RD_API_KEY", "")
    if key:
        return key
    cfg = os.environ.get("PD_CONFIG_DIR", "/config")
    try:
        with open(os.path.join(cfg, "settings.json")) as f:
            return json.load(f).get("Real Debrid API Key", "") or ""
    except Exception:
        return ""


realdebrid.api_key = load_rd_key()
scraper_services.active = [s.strip() for s in os.environ.get("ADDON_SOURCES", "torrentio").split(",") if s.strip()]

MANIFEST = {
    "id": "community.plexdebrid.local",
    "version": "1.0.0",
    "name": "Plex Debrid (local)",
    "description": "Local Torrentio-style addon: plex_debrid scrapers + Real-Debrid, resolved on click.",
    "logo": "https://dl.strem.io/addon-logo.png",
    "resources": ["stream"],
    "types": ["movie", "series"],
    "idPrefixes": ["tt"],
    "catalogs": [],
    "behaviorHints": {"configurable": False},
}


def scrape(type_, imdb, season=0, episode=0):
    if type_ == "series":
        altquery = "%s S%02dE%02d" % (imdb, int(season), int(episode))
    else:
        altquery = imdb
    results = []
    for name in scraper_services.active:
        module = sys.modules.get("scraper.services." + name)
        if module is None or not hasattr(module, "scrape"):
            continue
        try:
            results += module.scrape(imdb, altquery)
        except Exception as e:
            print("[addon] scraper '%s' error: %s" % (name, e))
    return results


def build_streams(type_, imdb, season, episode, base_url):
    releases = scrape(type_, imdb, season, episode)
    seen = set()
    items = []
    for r in releases:
        h = getattr(r, "hash", "")
        if not h or h in seen:
            continue
        seen.add(h)
        res = getattr(r, "resolution", "0")
        size = getattr(r, "size", 0) or 0
        seeders = getattr(r, "seeders", 0)
        label = "[RD] %sp" % res if res not in ("0", 0) else "[RD]"
        size_str = ("%.2f GB" % size) if size else "?"
        title = "%s\n\U0001F4BE %s  \U0001F465 %s" % (getattr(r, "title", ""), size_str, seeders)
        items.append({
            "_res": int(res) if str(res).isdigit() else 0,
            "_seed": seeders if isinstance(seeders, int) else 0,
            "name": label,
            "title": title,
            "url": "%s/playback/%s/%d/%d" % (base_url, h, int(season), int(episode)),
        })
    items.sort(key=lambda x: (x["_res"], x["_seed"]), reverse=True)
    for it in items:
        it.pop("_res", None)
        it.pop("_seed", None)
    return {"streams": items}


def choose_file(files, season, episode):
    videos = [f for f in files if str(getattr(f, "path", "")).lower().endswith(VIDEO_EXT)]
    if not videos:
        videos = list(files)
    if not videos:
        return None
    if int(season) > 0:
        pat = re.compile(r"s0*%d[ ._-]*e0*%d" % (int(season), int(episode)), re.I)
        for f in videos:
            if pat.search(str(getattr(f, "path", ""))):
                return f
    return max(videos, key=lambda f: getattr(f, "bytes", 0))


def resolve_playback(infohash, season, episode):
    """Add the magnet to Real-Debrid, pick the file, return a direct link or None."""
    if not realdebrid.api_key:
        print("[addon] no Real-Debrid API key configured")
        return None
    magnet = "magnet:?xt=urn:btih:" + infohash
    torrent_id = None
    try:
        added = realdebrid.post(RD + "/torrents/addMagnet", {"magnet": magnet})
        torrent_id = str(added.id)
        info = realdebrid.get(RD + "/torrents/info/" + torrent_id)
        if info is None or not getattr(info, "files", None):
            time.sleep(1)
            info = realdebrid.get(RD + "/torrents/info/" + torrent_id)
        if info is None or not getattr(info, "files", None):
            return None
        target = choose_file(info.files, season, episode)
        if target is None:
            return None
        realdebrid.post(RD + "/torrents/selectFiles/" + torrent_id, {"files": str(target.id)})
        link = None
        for _ in range(15):
            info = realdebrid.get(RD + "/torrents/info/" + torrent_id)
            status = getattr(info, "status", "")
            if status == "downloaded" and getattr(info, "links", None):
                link = info.links[0]
                break
            if status in ("magnet_error", "error", "virus", "dead"):
                break
            time.sleep(1)
        if not link:
            print("[addon] '%s' is not cached on Real-Debrid yet (queued for download)" % infohash)
            return None
        unrestricted = realdebrid.post(RD + "/unrestrict/link", {"link": link})
        return getattr(unrestricted, "download", None)
    except Exception as e:
        print("[addon] playback resolve error: %s" % e)
        return None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # quiet default logging

    def _send_json(self, obj, code=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        parts = [p for p in path.split("/") if p != ""]
        try:
            if path == "/" or path == "/manifest.json":
                self._send_json(MANIFEST)
                return
            # /stream/{type}/{id}.json
            if len(parts) == 3 and parts[0] == "stream" and parts[2].endswith(".json"):
                type_ = parts[1]
                ident = parts[2][:-len(".json")]
                bits = ident.split(":")
                imdb = bits[0]
                season = bits[1] if len(bits) > 1 else 0
                episode = bits[2] if len(bits) > 2 else 0
                host = self.headers.get("Host", "127.0.0.1:%d" % PORT)
                base_url = "http://" + host
                self._send_json(build_streams(type_, imdb, season, episode, base_url))
                return
            # /playback/{infohash}/{season}/{episode}
            if len(parts) == 4 and parts[0] == "playback":
                link = resolve_playback(parts[1], parts[2], parts[3])
                if link:
                    self.send_response(302)
                    self.send_header("Location", link)
                    self.end_headers()
                else:
                    self.send_response(404)
                    self.end_headers()
                return
            self.send_response(404)
            self.end_headers()
        except Exception as e:
            print("[addon] request error: %s" % e)
            try:
                self.send_response(500)
                self.end_headers()
            except Exception:
                pass


def main():
    print("[addon] Plex Debrid Stremio addon listening on :%d" % PORT)
    print("[addon] sources: %s | Real-Debrid key: %s" % (
        ", ".join(scraper_services.active), "set" if realdebrid.api_key else "MISSING"))
    print("[addon] install URL: http://<this-host>:%d/manifest.json" % PORT)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
