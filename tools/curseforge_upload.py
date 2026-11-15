"""Upload GuildBoard.zip to CurseForge. Runs from the Release workflow after the zips are built.
Needs repo secret CF_API_KEY and '## X-Curse-Project-ID: <id>' in GuildBoard.toc. Skips quietly if either is missing.
Never prints the token."""
import json, os, re, sys, urllib.request, urllib.error, uuid

key = os.environ.get('CF_API_KEY', '').strip()
toc = open('GuildBoard/GuildBoard.toc', encoding='utf-8').read()
pid = (re.search(r'X-Curse-Project-ID:\s*(\d+)', toc) or [None, None])[1]
if not key or not pid:
    print('CurseForge upload skipped (no CF_API_KEY secret or no X-Curse-Project-ID in the toc)'); sys.exit(0)
ver = (re.search(r'## Version:\s*(\S+)', toc) or [None, '?'])[1]
API = 'https://wow.curseforge.com/api'
H = {'X-Api-Token': key, 'User-Agent': 'guild-board-release'}

def get(path):
    with urllib.request.urlopen(urllib.request.Request(API + path, headers=H), timeout=30) as r: return json.load(r)

versions = get('/game/versions')
want = os.environ.get('CF_GAME_VERSION', '').strip()
pick = [v for v in versions if want and v.get('name') == want]
if not pick:
    # WoW Forever's interface is 16001, which CurseForge lists as game version 1.60.x
    pick = [v for v in versions if 'forever' in str(v.get('name', '')).lower() or str(v.get('name', '')).startswith('1.60')]
if not pick:
    print('Could not find a WoW Forever game version on CurseForge. Versions that look recent:')
    for v in sorted(versions, key=lambda v: v.get('id', 0))[-25:]: print(' ', v.get('id'), v.get('name'))
    print('Set repo variable CF_GAME_VERSION to the right name and re-run.'); sys.exit(1)
pick = sorted(pick, key=lambda v: v.get('id', 0))[-1:]
print('Game version:', pick[0].get('name'))

log = open('CHANGELOG.md', encoding='utf-8').read()
m = re.search(r'### ' + re.escape(ver) + r'.*?(?=\n### |\n## )', log, re.S)
meta = {'changelog': (m.group(0) if m else f'Guild Board {ver}'), 'changelogType': 'markdown', 'displayName': f'Guild Board {ver}',
        'gameVersions': [pick[0]['id']], 'releaseType': 'release'}
b = uuid.uuid4().hex
body = (f'--{b}\r\nContent-Disposition: form-data; name="metadata"\r\n\r\n{json.dumps(meta)}\r\n'
        f'--{b}\r\nContent-Disposition: form-data; name="file"; filename="GuildBoard-{ver}.zip"\r\nContent-Type: application/zip\r\n\r\n').encode()
body += open('GuildBoard.zip', 'rb').read() + f'\r\n--{b}--\r\n'.encode()
req = urllib.request.Request(f'{API}/projects/{pid}/upload-file', data=body, method='POST',
                             headers=dict(H, **{'Content-Type': f'multipart/form-data; boundary={b}'}))
try:
    with urllib.request.urlopen(req, timeout=120) as r: print('Uploaded to CurseForge, file id', json.load(r).get('id'))
except urllib.error.HTTPError as e:
    print('CurseForge upload failed', e.code, e.read()[:300].decode(errors='replace')); sys.exit(1)
