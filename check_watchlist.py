import os
import sys
import requests

# Provide your Plex token via the PLEX_TOKEN environment variable or as the
# first command-line argument. Never hard-code tokens in source files.
token = os.environ.get("PLEX_TOKEN") or (sys.argv[1] if len(sys.argv) > 1 else "")
if not token:
    print("Usage: PLEX_TOKEN=<your_token> python check_watchlist.py")
    print("   or: python check_watchlist.py <your_token>")
    sys.exit(1)

headers = {'Accept': 'application/json'}


def check(label, base_url):
    print(f"--- Testing {label} ---")
    url = f'{base_url}?X-Plex-Token={token}'

import requests


def get_token():
    token = os.environ.get("PLEX_TOKEN") or (sys.argv[1] if len(sys.argv) > 1 else "")
    if not token:
        print("Usage: PLEX_TOKEN=<token> python check_watchlist.py")
        print("   or: python check_watchlist.py <token>")
        sys.exit(1)
    return token


def check(label, base_url, token):
    print(f"--- Testing {label} ---")
    url = f"{base_url}?X-Plex-Token={token}"
    headers = {"Accept": "application/json"}
    try:
        resp = requests.get(url, headers=headers, timeout=30)
        print(f"Status: {resp.status_code}")
        if resp.status_code == 200:
            data = resp.json()
            if 'MediaContainer' in data and 'Metadata' in data['MediaContainer']:
                items = data['MediaContainer']['Metadata']
            items = data.get("MediaContainer", {}).get("Metadata", [])
            if items:
                print(f"Found {len(items)} items.")
                for item in items:
                    print(f" - {item.get('title')} ({item.get('year')})")
            else:
                print("No Metadata in response.")
        else:
            print(resp.text)
    except Exception as e:
        print(f"Error: {e}")


check("Standard API", "https://metadata.provider.plex.tv/library/sections/watchlist/all")
print()
check("Discover API", "https://discover.provider.plex.tv/library/sections/watchlist/all")
def main():
    token = get_token()
    check("Standard API", "https://metadata.provider.plex.tv/library/sections/watchlist/all", token)
    print()
    check("Discover API", "https://discover.provider.plex.tv/library/sections/watchlist/all", token)


if __name__ == "__main__":
    main()
