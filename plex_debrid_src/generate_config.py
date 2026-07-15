#!/usr/bin/env python3
"""Generate /config/settings.json from PD_* environment variables.

This is used by non-interactive installers or automation. OAuth-based logins such
as Plex/Trakt users can still be completed later in the interactive menu.
"""
import json
import os
import sys

sys.argv = ["generate_config.py"]

# Import ui first so the original project import chain is initialized correctly.
import ui  # noqa: F401
from content import classes
import content.services as content_services
from content.services import jellyfin, overseerr, plex, textfile  # noqa: F401
import debrid.services as debrid_services
from debrid.services import realdebrid
import releases
import scraper.services as scraper_services
from settings import settings_list
from ui import ui_settings


def env(name, default=""):
    value = os.environ.get(name)
    return value if value not in (None, "") else default


def env_list(name, default):
    raw = os.environ.get(name, "")
    items = [item.strip() for item in raw.split(",") if item.strip()]
    return items if items else default


content_services.active = env_list("PD_CONTENT_SERVICES", ["Plex", "Trakt", "Overseerr"])
classes.library.active = env_list("PD_COLLECTION_SERVICE", ["Plex Library"])
classes.refresh.active = env_list("PD_UPDATE_SERVICES", ["Plex Libraries"])
classes.ignore.active = env_list("PD_IGNORE_SERVICES", ["Plex Discover Watch Status"])
scraper_services.active = env_list("PD_SOURCES", ["torrentio"])
debrid_services.active = env_list("PD_DEBRID_SERVICES", ["Real Debrid"])

realdebrid.api_key = env("PD_RD_API_KEY", env("RD_API_KEY", realdebrid.api_key))

if env("PD_PLEX_ADDRESS"):
    plex.library.url = env("PD_PLEX_ADDRESS")
if env("PD_JELLYFIN_ADDRESS"):
    jellyfin.library.url = env("PD_JELLYFIN_ADDRESS")
if env("PD_JELLYFIN_API_KEY"):
    jellyfin.api_key = env("PD_JELLYFIN_API_KEY")
if env("PD_OVERSEERR_URL"):
    overseerr.base_url = env("PD_OVERSEERR_URL")
if env("PD_OVERSEERR_API_KEY"):
    overseerr.api_key = env("PD_OVERSEERR_API_KEY")
if "Local Ignore List" in classes.ignore.active:
    textfile.library.ignore.path = env("PD_IGNORE_PATH", "/config")

if not getattr(releases.sort, "versions", None):
    releases.sort.versions = [
        [
            "Any",
            [["retries", "<=", "48"], ["media type", "all", ""]],
            "true",
            [["title", "requirement", "exclude", r"dolby.?vision|\b(dv)\b|dovi"]],
        ]
    ]

ui_settings.run_directly = "true"

save_settings = {}
for _, settings in settings_list:
    for setting in settings:
        save_settings[setting.name] = setting.get()

config_dir = env("PD_CONFIG_DIR", "/config")
os.makedirs(config_dir, exist_ok=True)
path = os.path.join(config_dir, "settings.json")
with open(path, "w", encoding="utf-8") as f:
    json.dump(save_settings, f, indent=4)

print("Wrote " + path)
print(" content services : " + ", ".join(content_services.active))
print(" collection       : " + ", ".join(classes.library.active))
print(" update services  : " + ", ".join(classes.refresh.active))
print(" sources          : " + ", ".join(scraper_services.active))
print(" debrid           : " + ", ".join(debrid_services.active))
