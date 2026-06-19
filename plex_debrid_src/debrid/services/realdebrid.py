#import modules
from base import *
from ui.ui_print import *
import releases

# (required) Name of the Debrid service
name = "Real Debrid"
short = "RD"
# (required) Authentification of the Debrid service, can be oauth aswell. Create a setting for the required variables in the ui.settings_list. For an oauth example check the trakt authentification.
api_key = ""
# Define Variables
session = requests.Session()
errors = [
    [202," action already done"],
    [400," bad Request (see error message)"],
    [403," permission denied (infringing torrent or account locked or not premium)"],
    [503," service unavailable (see error message)"],
    [404," wrong parameter (invalid file id(s)) / unknown ressource (invalid id)"],
    ]
def setup(cls, new=False):
    from debrid.services import setup
    setup(cls,new)

# Error Log
def logerror(response):
    if not response.status_code in [200,201,204]:
        desc = ""
        for error in errors:
            if response.status_code == error[0]:
                desc = error[1]
        ui_print("[realdebrid] error: (" + str(response.status_code) + desc + ") " + str(response.content), debug=ui_settings.debug)
    if response.status_code == 401:
        ui_print("[realdebrid] error: (401 unauthorized): realdebrid api key does not seem to work. check your realdebrid settings.")
    if response.status_code == 403:
        ui_print("[realdebrid] error: (403 unauthorized): You may have attempted to add an infringing torrent or your realdebrid account is locked or you dont have premium.")

# Get Function
def get(url):
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36','authorization': 'Bearer ' + api_key}
    response = None
    try:
        response = session.get(url, headers=headers)
        logerror(response)
        response = json.loads(response.content, object_hook=lambda d: SimpleNamespace(**d))
    except Exception as e:
        ui_print("[realdebrid] error: (json exception): " + str(e), debug=ui_settings.debug)
        response = None
    return response

# Post Function
def post(url, data):
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36','authorization': 'Bearer ' + api_key}
    response = None
    try:
        response = session.post(url, headers=headers, data=data)
        logerror(response)
        response = json.loads(response.content, object_hook=lambda d: SimpleNamespace(**d))
    except Exception as e:
        if hasattr(response,"status_code"):
            if response.status_code >= 300:
                ui_print("[realdebrid] error: (json exception): " + str(e), debug=ui_settings.debug)
        else:
            ui_print("[realdebrid] error: (json exception): " + str(e), debug=ui_settings.debug)
        response = None
    return response

# Delete Function
def delete(url):
    headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36','authorization': 'Bearer ' + api_key}
    try:
        requests.delete(url, headers=headers)
        # time.sleep(1)
    except Exception as e:
        ui_print("[realdebrid] error: (delete exception): " + str(e), debug=ui_settings.debug)
        None
    return None

# Object classes
class file:
    def __init__(self, id, name, size, wanted_list, unwanted_list):
        self.id = id
        self.name = name
        self.size = size / 1000000000
        self.match = ''
        wanted = False
        unwanted = False
        for key, wanted_pattern in wanted_list:
            if wanted_pattern.search(self.name):
                wanted = True
                self.match = key
                break

        if not wanted:
            for key, unwanted_pattern in unwanted_list:
                if unwanted_pattern.search(self.name) or self.name.endswith('.exe') or self.name.endswith('.txt'):
                    unwanted = True
                    break

        self.wanted = wanted
        self.unwanted = unwanted

    def __eq__(self, other):
        return self.id == other.id

class version:
    def __init__(self, files):
        self.files = files
        self.needed = 0
        self.wanted = 0
        self.unwanted = 0
        self.size = 0
        for file in self.files:
            self.size += file.size
            if file.wanted:
                self.wanted += 1
            if file.unwanted:
                self.unwanted += 1

# (required) Download Function.
def download(element, stream=True, query='', force=False):
    cached = element.Releases
    if query == '':
        query = element.deviation()
    wanted = [query]
    if not isinstance(element, releases.release):
        wanted = element.files()
    for release in cached[:]:
        # if release matches query
        if regex.match(query, release.title,regex.I) or force:
            if stream:
                release.size = 0
                for version in release.files:
                    if hasattr(version, 'files'):
                        if len(version.files) > 0 and version.wanted > len(wanted) / 2 or force:
                            cached_ids = []
                            for file in version.files:
                                cached_ids += [file.id]
                            # post magnet to real debrid
                            try:
                                response = post('https://api.real-debrid.com/rest/1.0/torrents/addMagnet',{'magnet': str(release.download[0])})
                                torrent_id = str(response.id)
                            except:
                                ui_print('[realdebrid] error: could not add magnet for release: ' + release.title, ui_settings.debug)
                                continue
                            response = post('https://api.real-debrid.com/rest/1.0/torrents/selectFiles/' + torrent_id,{'files': str(','.join(cached_ids))})
                            response = get('https://api.real-debrid.com/rest/1.0/torrents/info/' + torrent_id)
                            actual_title = ""
                            if len(response.links) == len(cached_ids):
                                actual_title = response.filename
                                release.download = response.links
                            else:
                                if response.status in ["queued","magnet_convesion","downloading","uploading"]:
                                    if hasattr(element,"version"):
                                        debrid_uncached = True
                                        for i,rule in enumerate(element.version.rules):
                                            if (rule[0] == "cache status") and (rule[1] == 'requirement' or rule[1] == 'preference') and (rule[2] == "cached"):
                                                debrid_uncached = False
                                        if debrid_uncached:
                                            import debrid as db
                                            release.files = version.files
                                            db.downloading += [element.query() + ' [' + element.version.name + ']']
                                            ui_print('[realdebrid] adding uncached release: ' + release.title)
                                            return True
                                else:
                                    ui_print('[realdebrid] error: selecting this cached file combination returned a .rar archive - trying a different file combination.', ui_settings.debug)
                                    delete('https://api.real-debrid.com/rest/1.0/torrents/delete/' + torrent_id)
                                    continue
                            if len(release.download) > 0:
                                for link in release.download:
                                    try:
                                        response = post('https://api.real-debrid.com/rest/1.0/unrestrict/link',{'link': link})
                                    except:
                                        break
                                release.files = version.files
                                ui_print('[realdebrid] adding cached release: ' + release.title)
                                if not actual_title == "":
                                    release.title = actual_title
                                return True
                ui_print('[realdebrid] error: no streamable version could be selected for release: ' + release.title)
                return False
            else:
                try:
                    response = post('https://api.real-debrid.com/rest/1.0/torrents/addMagnet',{'magnet': release.download[0]})
                    time.sleep(0.1)
                    post('https://api.real-debrid.com/rest/1.0/torrents/selectFiles/' + str(response.id),{'files': 'all'})
                    ui_print('[realdebrid] adding uncached release: ' + release.title)
                    return True
                except:
                    continue
        else:
            ui_print('[realdebrid] error: rejecting release: "' + release.title + '" because it doesnt match the allowed deviation', ui_settings.debug)
    return False

# (required) Check Function
#
# Real-Debrid disabled the data returned by /torrents/instantAvailability around
# November 2024, so cached availability can no longer be discovered in a single
# batch call. This function therefore works in two steps:
#   1. It still queries instantAvailability first (cheap) in case Real-Debrid ever
#      returns data again for some hashes.
#   2. For every hash that instantAvailability does not cover, it "probes" the
#      torrent: it adds the magnet, reads the real file list from /torrents/info,
#      selects the wanted files to detect instant (cached) availability, and then
#      removes the probe torrent so check() leaves no residue. The actual download
#      is still performed by download().
# NOTE: step 2 is heavier than the old batch check (a few API calls per release);
# MAX_CHECK bounds how many uncovered releases are probed per call.
MAX_CHECK = 50

def probe_files(release, wanted_patterns, unwanted_patterns):
    # Add the magnet, read its real file list, and detect cached status, then clean up.
    torrent_id = None
    try:
        response = post('https://api.real-debrid.com/rest/1.0/torrents/addMagnet', {'magnet': str(release.download[0])})
        torrent_id = str(response.id)
        info = get('https://api.real-debrid.com/rest/1.0/torrents/info/' + torrent_id)
        # the file list can be empty for a few moments while the magnet is converted
        if info is not None and getattr(info, "status", "") in ["magnet_conversion", "queued"] and not getattr(info, "files", None):
            time.sleep(1)
            info = get('https://api.real-debrid.com/rest/1.0/torrents/info/' + torrent_id)
        if info is None or not hasattr(info, "files") or not info.files:
            return
        version_files = []
        for f in info.files:
            version_files.append(file(str(f.id), f.path, f.bytes, wanted_patterns, unwanted_patterns))
        if len(version_files) == 0:
            return
        release.files = [version(version_files)]
        release.wanted = release.files[0].wanted
        release.unwanted = release.files[0].unwanted
        release.size = release.files[0].size
        # detect cached status: select the wanted files and check whether Real-Debrid
        # reports the torrent as already 'downloaded' (i.e. instantly available).
        wanted_ids = [vf.id for vf in version_files if vf.wanted]
        if len(wanted_ids) == 0:
            wanted_ids = [vf.id for vf in version_files]
        post('https://api.real-debrid.com/rest/1.0/torrents/selectFiles/' + torrent_id, {'files': ','.join(wanted_ids)})
        info = get('https://api.real-debrid.com/rest/1.0/torrents/info/' + torrent_id)
        if info is not None and getattr(info, "status", "") == "downloaded":
            if 'RD' not in release.cached:
                release.cached += ['RD']
        release.checked = True
    except Exception as e:
        ui_print("[realdebrid] error: (probe exception) " + str(e), debug=ui_settings.debug)
    finally:
        # remove the probe torrent so check() does not leave residue or running downloads
        if torrent_id is not None:
            delete('https://api.real-debrid.com/rest/1.0/torrents/delete/' + torrent_id)

def check(element, force=False):
    if force:
        wanted = ['.*']
    else:
        wanted = element.files()
    unwanted = releases.sort.unwanted
    wanted_patterns = list(zip(wanted, [regex.compile(r'(' + key + ')', regex.IGNORECASE) for key in wanted]))
    unwanted_patterns = list(zip(unwanted, [regex.compile(r'(' + key + ')', regex.IGNORECASE) for key in unwanted]))

    hashes = []
    for release in element.Releases[:]:
        if len(release.hash) == 40:
            hashes += [release.hash]
        else:
            ui_print("[realdebrid] error (missing torrent hash): ignoring release '" + release.title + "' ",ui_settings.debug)
            element.Releases.remove(release)
    if len(hashes) == 0:
        return
    # step 1: legacy batch availability lookup (kept as a best-effort fast path)
    response = get('https://api.real-debrid.com/rest/1.0/torrents/instantAvailability/' + '/'.join(hashes))
    ui_print("[realdebrid] checking and sorting all release files ...", ui_settings.debug)
    probed = 0
    for release in element.Releases:
        if getattr(release, "checked", False) and len(release.files) > 0:
            continue
        release.files = []
        release_hash = release.hash.lower()
        # step 1 result, if Real-Debrid still returns availability data for this hash
        if response is not None and hasattr(response, release_hash):
            response_attr = getattr(response, release_hash)
            if hasattr(response_attr, 'rd') and len(response_attr.rd) > 0:
                for cashed_version in response_attr.rd:
                    version_files = []
                    for file_ in cashed_version.__dict__:
                        file_attr = getattr(cashed_version, file_)
                        debrid_file = file(file_, file_attr.filename, file_attr.filesize, wanted_patterns, unwanted_patterns)
                        version_files.append(debrid_file)
                    release.files += [version(version_files), ]
                # select cached version that has the most needed, most wanted, least unwanted files and most files overall
                release.files.sort(key=lambda x: len(x.files), reverse=True)
                release.files.sort(key=lambda x: x.wanted, reverse=True)
                release.files.sort(key=lambda x: x.unwanted, reverse=False)
                release.wanted = release.files[0].wanted
                release.unwanted = release.files[0].unwanted
                release.size = release.files[0].size
                release.cached += ['RD']
                release.checked = True
                continue
        # step 2: instantAvailability returned nothing for this hash -> probe it directly
        if probed < MAX_CHECK:
            probed += 1
            probe_files(release, wanted_patterns, unwanted_patterns)
    ui_print("done",ui_settings.debug)
