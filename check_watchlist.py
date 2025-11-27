import requests
import json

token = "PH8sc9XUFZjxcxGD1gzi"
headers = {'Accept': 'application/json'}

print("--- Testing Standard API ---")
url_standard = f'https://metadata.provider.plex.tv/library/sections/watchlist/all?X-Plex-Token={token}'
try:
    resp = requests.get(url_standard, headers=headers)
    print(f"Status: {resp.status_code}")
    if resp.status_code == 200:
        data = resp.json()
        if 'MediaContainer' in data and 'Metadata' in data['MediaContainer']:
            print(f"Found {len(data['MediaContainer']['Metadata'])} items.")
            for item in data['MediaContainer']['Metadata']:
                print(f" - {item.get('title')} ({item.get('year')})")
        else:
            print("No Metadata in response.")
    else:
        print(resp.text)
except Exception as e:
    print(f"Error: {e}")

print("\n--- Testing Discover API ---")
url_discover = f'https://discover.provider.plex.tv/library/sections/watchlist/all?X-Plex-Token={token}'
try:
    resp = requests.get(url_discover, headers=headers)
    print(f"Status: {resp.status_code}")
    if resp.status_code == 200:
        data = resp.json()
        if 'MediaContainer' in data and 'Metadata' in data['MediaContainer']:
            print(f"Found {len(data['MediaContainer']['Metadata'])} items.")
            for item in data['MediaContainer']['Metadata']:
                print(f" - {item.get('title')} ({item.get('year')})")
        else:
            print("No Metadata in response.")
    else:
        print(resp.text)
except Exception as e:
    print(f"Error: {e}")
