from base import *


def _ui_print(message, debug=False):
    try:
        from ui.ui_print import ui_print
        ui_print(message, debug=debug)
    except Exception:
        print(message)


def _as_text(value):
    return '' if value is None else str(value)


class rename:
    replaceChars = []

    def __new__(cls, title):
        text = _as_text(title).lower()
        for old, new in cls.replaceChars:
            if str(old).startswith('{{regex}}'):
                text = regex.sub(str(old).replace('{{regex}}', '', 1), str(new), text, flags=regex.I)
            else:
                text = text.replace(str(old), str(new))
        text = regex.sub(r"['’`´]", '', text)
        text = regex.sub(r'&', ' and ', text)
        text = regex.sub(r'[^a-z0-9]+', '.', text)
        text = regex.sub(r'\.+', '.', text).strip('.')
        return text


class release:
    def __init__(self, source, type, title, files, size, download, seeders=0):
        self.source = source
        self.type = type
        self.title = _as_text(title)
        self.files = files if files is not None else []
        self.size = float(size or 0)
        self.download = download if download is not None else []
        self.seeders = int(seeders or 0)
        self.cached = []
        self.checked = False
        self.hash = self._hash()
        self.resolution = self._resolution()
        self.wanted = 0
        self.unwanted = 0

    def _hash(self):
        candidates = [self.title] + [str(item) for item in self.download]
        for candidate in candidates:
            match = regex.search(r'btih:([A-Fa-f0-9]{40})', candidate)
            if match:
                return match.group(1).lower()
            match = regex.search(r'urn:btih:([A-Fa-f0-9]{40})', candidate)
            if match:
                return match.group(1).lower()
            match = regex.search(r'(?<![A-Fa-f0-9])([A-Fa-f0-9]{40})(?![A-Fa-f0-9])', candidate)
            if match:
                return match.group(1).lower()
        return ''

    def _resolution(self):
        match = regex.search(r'(2160|1080|720|480)(?=p|i)', self.title, regex.I)
        return int(match.group(1)) if match else 0

    def __eq__(self, other):
        return isinstance(other, release) and self.title == other.title and self.source == other.source


class sort:
    unwanted = [
        r'\.exe$', r'\.txt$', r'\.nfo$', r'\.url$', r'sample', r'trailer',
    ]
    versions = [
        ['Any', [['media type', 'all', '']], 'true', []],
    ]

    def __new__(cls, releases, version=None, apply=True):
        if not releases:
            return releases
        if version is not None:
            cls._filter_by_version(releases, version)
        releases.sort(key=lambda item: getattr(item, 'seeders', 0), reverse=True)
        releases.sort(key=lambda item: getattr(item, 'size', 0), reverse=True)
        releases.sort(key=lambda item: getattr(item, 'resolution', 0), reverse=True)
        releases.sort(key=lambda item: len(getattr(item, 'cached', [])), reverse=True)
        return releases

    @staticmethod
    def _filter_by_version(releases, version):
        if not getattr(version, 'rules', None):
            return
        for item in releases[:]:
            if not version.accepts(item):
                releases.remove(item)

    class version:
        def __init__(self, name, triggers=None, lang='true', rules=None):
            self.name = name
            self.triggers = triggers if triggers is not None else []
            self.lang = lang
            self.rules = rules if rules is not None else []

        def applies(self, media):
            if not self.triggers:
                return True
            media_type = getattr(media, 'type', '')
            for trigger in self.triggers:
                if len(trigger) < 3:
                    continue
                field, op, value = trigger[0], trigger[1], trigger[2]
                if field == 'media type':
                    if op == 'all' or value in ('', 'all') or value == media_type:
                        continue
                    return False
            return True

        def accepts(self, item):
            accepted = True
            for rule_data in self.rules:
                if len(rule_data) < 4:
                    continue
                if not sort.version.rule(rule_data[0], rule_data[1], rule_data[2], rule_data[3]).accepts(item):
                    accepted = False
                    break
            return accepted

        class rule:
            def __init__(self, field, mode, operator, value):
                self.field = field
                self.mode = mode
                self.operator = operator
                self.value = value

            def accepts(self, item):
                if self.mode not in ['requirement', 'exclude']:
                    return True
                matched = self._matches(item)
                if self.mode == 'exclude':
                    return not matched
                return matched

            def upgrade(self, existing_releases):
                if not existing_releases:
                    return True
                pattern = _as_text(self.value)
                return not any(regex.search(pattern, _as_text(title), regex.I) for title in existing_releases)

            def _matches(self, item):
                value = _as_text(self.value)
                if self.field == 'title':
                    haystack = _as_text(getattr(item, 'title', ''))
                    if self.operator in ['exclude', 'include', 'contains']:
                        return bool(regex.search(value, haystack, regex.I))
                    return bool(regex.search(value, haystack, regex.I))
                if self.field == 'cache status':
                    cached = len(getattr(item, 'cached', [])) > 0
                    return (value == 'cached' and cached) or (value == 'uncached' and not cached)
                if self.field == 'resolution':
                    return self._compare_number(getattr(item, 'resolution', 0), value)
                if self.field == 'size':
                    return self._compare_number(getattr(item, 'size', 0), value)
                if self.field == 'seeders':
                    return self._compare_number(getattr(item, 'seeders', 0), value)
                return True

            def _compare_number(self, actual, expected):
                try:
                    actual = float(actual)
                    expected = float(expected)
                except Exception:
                    return False
                if self.operator in ['>=', '=>']:
                    return actual >= expected
                if self.operator in ['<=', '=<']:
                    return actual <= expected
                if self.operator == '>':
                    return actual > expected
                if self.operator == '<':
                    return actual < expected
                if self.operator in ['!=', 'not']:
                    return actual != expected
                return actual == expected


def print_releases(releases, debug=False):
    for index, item in enumerate(releases, start=1):
        cache = ','.join(getattr(item, 'cached', [])) or 'uncached'
        _ui_print(f'{index}) {item.title} [{item.source}] {item.size:.2f} GB {cache}', debug=debug)


def torrent2magnet(data):
    # Fallback parser: if a magnet/hash is embedded in returned data, expose it as a magnet URI.
    if isinstance(data, bytes):
        data = data.decode('latin-1', errors='ignore')
    data = _as_text(data)
    match = regex.search(r'btih:([A-Fa-f0-9]{40})', data)
    if match:
        return 'magnet:?xt=urn:btih:' + match.group(1).lower()
    match = regex.search(r'(?<![A-Fa-f0-9])([A-Fa-f0-9]{40})(?![A-Fa-f0-9])', data)
    if match:
        return 'magnet:?xt=urn:btih:' + match.group(1).lower()
    return ''
