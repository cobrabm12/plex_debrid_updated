#import modules
from base import *
#import parent modules
from content import classes
from ui.ui_print import *

name = 'Jellyfin'
session = requests.Session()
api_key = ''

def logerror(response):
    if not response.status_code == 200 and hasattr(response,"content") and len(str(response.content)) > 0:
        ui_print("jellyfin error: " + str(response.content), debug=ui_settings.debug)
    if response.status_code == 401:
        ui_print("jellyfin error: (401 unauthorized): api token does not seem to work. check your jellyfin settings.")

def get(url, timeout=30):
    try:
        headers = {"X-MediaBrowser-Token": api_key}
        response = session.get(url, timeout=timeout, headers=headers)
        logerror(response)
        response = json.loads(response.content, object_hook=lambda d: SimpleNamespace(**d))
        return response
    except Exception as e:
        ui_print("jellyfin error: (json exception): " + str(e), debug=ui_settings.debug)
        return None

def post(url, data):
    try:
        headers = {"X-MediaBrowser-Token": api_key}
        response = session.post(url, data=data, headers=headers)
        logerror(response)
        response = json.loads(response.content, object_hook=lambda d: SimpleNamespace(**d))
        return response
    except Exception as e:
        ui_print("jellyfin error: (json exception): " + str(e), debug=ui_settings.debug)
        return None

def provider_eids(item):
    # Build plex-style external IDs (imdb://, tmdb://, tvdb://) from a Jellyfin item's ProviderIds.
    EID = []
    provider_ids = getattr(item, 'ProviderIds', None)
    if provider_ids is not None:
        for key, value in vars(provider_ids).items():
            if value in (None, ""):
                continue
            key_l = str(key).lower()
            if key_l == 'imdb':
                EID += ['imdb://' + str(value)]
            elif key_l == 'tmdb':
                EID += ['tmdb://' + str(value)]
            elif key_l == 'tvdb':
                EID += ['tvdb://' + str(value)]
    return EID

def make_media(**attrs):
    return classes.media(SimpleNamespace(**attrs))

def build_show(user_id, series_id, series_item):
    # Build a 'show' media object (with Seasons/Episodes) from a Jellyfin series.
    show_eid = provider_eids(series_item)
    show_guid = show_eid[0] if len(show_eid) > 0 else 'jellyfin://' + str(series_id)
    seasons_map = {}
    leaf_count = 0
    try:
        url = library.url + '/Shows/' + str(series_id) + '/Episodes?userId=' + str(user_id) + '&Fields=ProviderIds'
        response = get(url)
        if response is not None and hasattr(response, 'Items'):
            for ep in response.Items:
                season_index = getattr(ep, 'ParentIndexNumber', None)
                episode_index = getattr(ep, 'IndexNumber', None)
                # Skip specials (season 0) and items without proper numbering, to match plex behaviour.
                if season_index in (None, 0) or episode_index is None:
                    continue
                episode_obj = make_media(type='episode', index=episode_index, parentIndex=season_index,
                                         grandparentEID=show_eid, title=getattr(ep, 'Name', ''))
                seasons_map.setdefault(season_index, []).append(episode_obj)
                leaf_count += 1
    except Exception as e:
        ui_print("[jellyfin] error: couldnt read episodes for series '" + str(getattr(series_item, 'Name', series_id)) + "': " + str(e), debug=ui_settings.debug)
    seasons = []
    for season_index, episodes in seasons_map.items():
        seasons += [make_media(type='season', index=season_index, parentEID=show_eid,
                               leafCount=len(episodes), Episodes=episodes)]
    return make_media(type='show', title=getattr(series_item, 'Name', ''),
                      year=getattr(series_item, 'ProductionYear', None), EID=show_eid,
                      guid=show_guid, leafCount=leaf_count, Seasons=seasons)

class library(classes.library):
    name = 'Jellyfin Library'
    url = 'http://localhost:8096'

    def setup(cls, new=False):
        from settings import settings_list
        if new:
            print()
            settings = []
            for category, allsettings in settings_list:
                for setting in allsettings:
                    settings += [setting]
            if len(api_key) == 0:
                print('Please specify your jellyfin api key:')
                print()
                for setting in settings:
                    if setting.name == 'Jellyfin API Key':
                        setting.setup()
                print()
            for setting in settings:
                if setting.name == 'Jellyfin server address':
                    setting.setup()
                    print()
            classes.library.active = [library.name]
        else:
            classes.library.setup(library)

    class refresh(classes.refresh):

        name = 'Jellyfin Libraries'

        def setup(cls, new=False):
            ui_cls("Options/Settings/Library Services/Library update services")
            from settings import settings_list
            settings = []
            for category, allsettings in settings_list:
                for setting in allsettings:
                    settings += [setting]
            if len(api_key) == 0:
                print("It looks like you havent setup a jellyfin api key. Please set up a jellyfin api key first.")
                print()
                for setting in settings:
                    if setting.name == "Jellyfin API Key":
                        setting.setup()
            working = False
            while not working:
                try:
                    headers = {"X-MediaBrowser-Token": api_key}
                    response = session.get(library.url  + '/System/Info',headers=headers)
                    while response.status_code == 401:
                        print("It looks like your jellyfin api key did not work.")
                        print()
                        for setting in settings:
                            if setting.name == "Jellyfin API Key":
                                setting.setup()
                        headers = {"X-MediaBrowser-Token": api_key}
                        response = session.get(library.url  + '/System/Info',headers=headers)
                    working = True
                except:
                    print("It looks like your jellyfin server could not be reached at '" + library.url + "'")
                    print()
                    for setting in settings:
                        if setting.name == "Jellyfin server address":
                            setting.setup()
                    print()
            if not new:
                back = False
                jellysettings = []
                for setting in settings:
                    if setting.name == "Jellyfin API Key" or setting.name == "Jellyfin server address":
                        jellysettings += [setting]
                while not back:
                    print("0) Back")
                    indices = []
                    for i,setting in enumerate(jellysettings):
                        print(str(i+1) + ") " + setting.name)
                        indices += str(i+1)
                    print()
                    choice2 = input("Choose an action")
                    if choice2 == '0':
                        back = True
                    elif choice2 in indices:
                        jellysettings[int(choice2)-1].setup()
            else:
                back = False
                while not back:
                    if not library.refresh.name in classes.refresh.active:
                        classes.refresh.active += [library.refresh.name]
                        print()
                        print("Successfully added jellyfin!")
                        print()
                        time.sleep(3)
                    return

        def __new__(cls, element):
            try:
                ui_print('[jellyfin] refreshing all libraries')
                url = library.url + '/Library/Refresh'
                response = post(url,"")
            except:
                print("[jellyfin] error: couldnt refresh libraries")

    def __new__(self, silent=False):
        list_ = []
        if not silent:
            ui_print('[jellyfin] getting jellyfin library ...')
        users_response = get(library.url + '/Users')
        if users_response is None or not isinstance(users_response, list):
            ui_print("[jellyfin error]: couldnt reach local jellyfin server at server address: " + library.url + " - check your jellyfin server address and api key.")
            return list_
        seen_movies = []
        seen_series = {}
        try:
            for user in users_response:
                user_id = getattr(user, 'Id', None)
                if user_id is None:
                    continue
                start = 0
                total = 1
                while start < total:
                    url = (library.url + '/Users/' + str(user_id) + '/Items'
                           '?Recursive=true&IncludeItemTypes=Movie,Series'
                           '&Fields=ProviderIds,ProductionYear'
                           '&StartIndex=' + str(start) + '&Limit=200')
                    response = get(url)
                    if response is None or not hasattr(response, 'Items'):
                        break
                    items = response.Items
                    total = getattr(response, 'TotalRecordCount', len(items))
                    if len(items) == 0:
                        break
                    start += len(items)
                    for item in items:
                        item_type = getattr(item, 'Type', '')
                        if item_type == 'Movie':
                            eids = provider_eids(item)
                            key = tuple(sorted(eids)) if len(eids) > 0 else ('jellyfin', getattr(item, 'Id', ''))
                            if key in seen_movies:
                                continue
                            seen_movies += [key]
                            guid = eids[0] if len(eids) > 0 else 'jellyfin://' + str(getattr(item, 'Id', ''))
                            list_ += [make_media(type='movie', title=getattr(item, 'Name', ''),
                                                 year=getattr(item, 'ProductionYear', None),
                                                 EID=eids, guid=guid)]
                        elif item_type == 'Series':
                            series_id = getattr(item, 'Id', None)
                            if series_id is None or series_id in seen_series:
                                continue
                            seen_series[series_id] = (user_id, item)
            # build the show hierarchy once per unique series
            for series_id, (user_id, series_item) in seen_series.items():
                list_ += [build_show(user_id, series_id, series_item)]
        except Exception as e:
            ui_print("[jellyfin error]: (library exception): " + str(e), debug=ui_settings.debug)
        if len(list_) == 0:
            ui_print("[jellyfin warning]: Your jellyfin library seems empty. If this is unexpected, check your jellyfin server address and api key.", debug=ui_settings.debug)
        elif not silent:
            ui_print('done')
        return list_

# Multiprocessing watchlist method
def multi_init(cls, obj, result, index):
    result[index] = cls(obj)
