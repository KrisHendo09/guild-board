#!/usr/bin/env python3
"""Guild Board for Discord, built from the official WoW Forever Armory API (no addon needed).
Pulls the whole guild roster plus each member's professions, draws image panels (crafting board
first, then the roster, 10 members per panel) and posts them through the channel webhook,
replacing the same messages on later runs.

Secrets come from environment variables, or from files beside this script (never print them):
  BLIZZARD_CLIENT_ID / BLIZZARD_CLIENT_SECRET   or blizzard_api.txt (line 1 id, line 2 secret)
  DISCORD_WEBHOOK_URL                           or discord_webhook.txt
  DISCORD_MESSAGE_IDS (optional, comma separated) or out/_discord_state.json
Run:  python3 guild_armory.py            fetch, draw, post or update
      python3 guild_armory.py --dry      fetch and draw into out/, send nothing
Needs Pillow and the DejaVu fonts. The API namespace profile-forever-us is undocumented."""
import base64, hashlib, json, os, sys, time, urllib.request, urllib.error
from datetime import datetime, timezone
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out'); os.makedirs(OUT, exist_ok=True)
GUILD = os.environ.get('GUILD_SLUG', 'push-to-prod'); NS = 'profile-forever-us'; API = 'https://us.api.blizzard.com'
STATE = os.path.join(OUT, '_discord_state.json'); PAYLOAD = os.path.join(OUT, 'discord_payload.json')
CLASSES = {1: 'Warrior', 2: 'Paladin', 3: 'Hunter', 4: 'Rogue', 5: 'Priest', 7: 'Shaman', 8: 'Mage', 9: 'Warlock', 11: 'Druid'}
CLASS_COLOR = {'Warrior': '#C79C6E', 'Paladin': '#F58CBA', 'Hunter': '#ABD473', 'Rogue': '#FFF569', 'Priest': '#FFFFFF',
               'Shaman': '#2E8CFF', 'Mage': '#69CCF0', 'Warlock': '#A996E8', 'Druid': '#FF7D0A'}
CRAFT = ['Alchemy', 'Blacksmithing', 'Enchanting', 'Engineering', 'Leatherworking', 'Tailoring']
GATHER = ['Herbalism', 'Mining', 'Skinning']
SECOND = ['Cooking', 'First Aid', 'Fishing']
MAXSKILL = 300


def secret(env, fname, line=0):
    v = os.environ.get(env)
    if v: return v.strip()
    return open(os.path.join(HERE, fname)).read().split()[line]


def http(url, data=None, headers=None, method=None):
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode() or '{}')


# ---------------------------------------------------------------- data
def fetch():
    auth = base64.b64encode(f"{secret('BLIZZARD_CLIENT_ID', 'blizzard_api.txt', 0)}:{secret('BLIZZARD_CLIENT_SECRET', 'blizzard_api.txt', 1)}".encode()).decode()
    tok = http('https://oauth.battle.net/token', b'grant_type=client_credentials', {'Authorization': 'Basic ' + auth})['access_token']
    H = {'Authorization': 'Bearer ' + tok}

    def get(path):
        try:
            return http(f'{API}{path}?namespace={NS}&locale=en_US', headers=H)
        except urllib.error.HTTPError as e:
            if e.code in (403, 404): return {}
            raise
    guild = get(f'/data/wow/guild/{GUILD}')
    roster = get(f'/data/wow/guild/{GUILD}/roster').get('members') or []
    if not roster: raise SystemExit('ROSTER_EMPTY: the Armory returned no members, not posting')
    rows = []
    for m in roster:
        c = m['character']; slug = c.get('slug') or c['name'].lower()
        prof = get(f'/profile/wow/character/{slug}'); pr = get(f'/profile/wow/character/{slug}/professions')
        skills = {}
        for k in ('primaries', 'secondaries'):
            for x in pr.get(k) or []:
                skills[x['profession']['name']] = max([t.get('skill_points') or 0 for t in x.get('tiers') or []] + [x.get('skill_points') or 0])
        rows.append({'name': (c['name'] + ' ' + (c.get('surname') or '')).strip(),
                     'cls': (prof.get('character_class') or {}).get('name') or CLASSES.get(c['playable_class']['id'], '?'),
                     'race': (prof.get('race') or {}).get('name') or '', 'level': prof.get('level') or c.get('level') or 0,
                     'rank': m.get('rank'), 'ilvl': prof.get('equipped_item_level') or 0, 'seen': prof.get('last_login_timestamp'), 'skills': skills})
    rows.sort(key=lambda r: (-r['level'], r['name']))
    data = {'guild': guild.get('name') or GUILD, 'faction': (guild.get('faction') or {}).get('name') or '', 'members': rows, 'at': time.time()}
    json.dump(data, open(os.path.join(OUT, 'guild_roster.json'), 'w'), indent=1)
    return data


# ---------------------------------------------------------------- drawing
def render(data):
    from PIL import Image, ImageDraw, ImageFont
    FD = '/usr/share/fonts/truetype/dejavu/'
    def F(size, bold=False): return ImageFont.truetype(FD + ('DejaVuSans-Bold.ttf' if bold else 'DejaVuSans.ttf'), size)
    W = 1200; BG = '#111318'; CARD = '#1A1D24'; ALT = '#161920'; TXT = '#E8EAED'; MUTE = '#8A93A3'; GOLD = '#E0B36A'; LINE = '#2A2F3A'
    rows = data['members']; now = data['at']
    try:
        from zoneinfo import ZoneInfo
        stamp = datetime.fromtimestamp(now, ZoneInfo('America/Chicago')).strftime('%b %d, %I:%M %p CT').replace(' 0', ' ')
    except Exception:
        stamp = datetime.fromtimestamp(now, timezone.utc).strftime('%b %d, %H:%M UTC')

    def seen(ms):
        if not ms: return ''
        h = (now - ms / 1000) / 3600
        return 'under 1h ago' if h < 1 else (f'{int(h)}h ago' if h < 48 else f'{int(h / 24)}d ago')

    def fit(d, s, font, width):
        if d.textlength(s, font=font) <= width: return s
        while s and d.textlength(s + '…', font=font) > width: s = s[:-1]
        return s + '…'

    def header(d, title, sub):
        d.rectangle([0, 0, W, 104], fill='#0C0E12'); d.rectangle([0, 104, W, 107], fill=GOLD)
        d.text((36, 20), title, font=F(40, True), fill=TXT)
        d.text((38, 70), sub, font=F(20), fill=MUTE)
        t = 'Updated ' + stamp; d.text((W - 36 - d.textlength(t, font=F(18)), 74), t, font=F(18), fill=MUTE)

    panels = []
    # ---- crafting board
    groups = [('Crafting', CRAFT), ('Gathering', GATHER), ('Everyday', SECOND)]
    by = {}
    for r in rows:
        for p, v in r['skills'].items(): by.setdefault(p, []).append((v, r['name'], r['cls']))
    cols = 3; gap = 20; cw = (W - 72 - gap * (cols - 1)) // cols; TOP = 4; lh = 34; ch = 54 + TOP * lh + 14
    nrows = sum((len(g) + cols - 1) // cols for _, g in groups)
    Hh = 107 + sum(46 for _ in groups) + nrows * (ch + gap) + 20
    im = Image.new('RGB', (W, Hh), BG); d = ImageDraw.Draw(im)
    header(d, f"{data['guild']}: who can make what", f"{data['faction']} · {len(rows)} members · WoW Forever · top {TOP} per profession, skill out of {MAXSKILL}")
    y = 107 + 14
    for gname, profs in groups:
        d.text((36, y + 6), gname.upper(), font=F(18, True), fill=GOLD); y += 46
        for i, p in enumerate(profs):
            cx = 36 + (i % cols) * (cw + gap); cy = y + (i // cols) * (ch + gap)
            d.rounded_rectangle([cx, cy, cx + cw, cy + ch], 12, fill=CARD, outline=LINE)
            who = sorted(by.get(p, []), reverse=True)
            d.text((cx + 18, cy + 14), p, font=F(24, True), fill=TXT)
            n = f'{len(who)} in guild' if who else 'nobody yet'
            d.text((cx + cw - 18 - d.textlength(n, font=F(16)), cy + 20), n, font=F(16), fill=MUTE)
            for j, (v, name, cls) in enumerate(who[:TOP]):
                ly = cy + 54 + j * lh
                d.text((cx + 18, ly), fit(d, name, F(19), cw - 128), font=F(19), fill=CLASS_COLOR.get(cls, TXT))
                bx0 = cx + cw - 108; bx1 = cx + cw - 62
                d.rounded_rectangle([bx0, ly + 9, bx1, ly + 17], 4, fill=LINE)
                d.rounded_rectangle([bx0, ly + 9, bx0 + max(4, int((bx1 - bx0) * min(v, MAXSKILL) / MAXSKILL)), ly + 17], 4, fill=GOLD)
                s = str(v); d.text((cx + cw - 18 - d.textlength(s, font=F(19, True)), ly), s, font=F(19, True), fill=TXT)
        y += ((len(profs) + cols - 1) // cols) * (ch + gap)
    panels.append(('guild_crafting.png', im))

    # ---- roster panels
    PER = 10; rh = 52
    chunks = [rows[i:i + PER] for i in range(0, len(rows), PER)]
    X = {'name': 40, 'lvl': 452, 'cls': 476, 'ilvl': 664, 'prof': 690, 'seen': W - 36}
    for ci, chunk in enumerate(chunks):
        Hh = 107 + 44 + len(chunk) * rh + 22
        im = Image.new('RGB', (W, Hh), BG); d = ImageDraw.Draw(im)
        a = ci * PER + 1
        header(d, f"{data['guild']}: roster", f"Members {a} to {a + len(chunk) - 1} of {len(rows)}, highest level first")
        y = 107 + 10; hf = F(15, True)
        for label, x, right in (('NAME', X['name'], 0), ('LVL', X['lvl'], 1), ('CLASS', X['cls'], 0), ('ILVL', X['ilvl'], 1), ('PROFESSIONS', X['prof'], 0), ('LAST SEEN', X['seen'], 1)):
            d.text((x - (d.textlength(label, font=hf) if right else 0), y + 8), label, font=hf, fill=MUTE)
        y += 34
        for i, r in enumerate(chunk):
            col = CLASS_COLOR.get(r['cls'], TXT)
            d.rectangle([24, y, W - 24, y + rh - 4], fill=CARD if i % 2 == 0 else ALT)
            d.rectangle([24, y, 30, y + rh - 4], fill=col)
            nm = fit(d, r['name'], F(22, True), 330); d.text((X['name'], y + 11), nm, font=F(22, True), fill=col)
            if r['rank'] == 0:
                tx = X['name'] + d.textlength(nm, font=F(22, True)) + 10
                d.rounded_rectangle([tx, y + 13, tx + 40, y + 35], 5, fill=GOLD); d.text((tx + 7, y + 15), 'GM', font=F(14, True), fill='#111318')
            s = str(r['level']); d.text((X['lvl'] - d.textlength(s, font=F(22, True)), y + 11), s, font=F(22, True), fill=TXT)
            d.text((X['cls'], y + 13), fit(d, (r['race'] + ' ' + r['cls']).strip(), F(19), 160), font=F(19), fill=MUTE)
            s = str(r['ilvl'] or '-'); d.text((X['ilvl'] - d.textlength(s, font=F(20)), y + 12), s, font=F(20), fill=TXT)
            main = sorted([(v, p) for p, v in r['skills'].items() if p in CRAFT + GATHER], reverse=True)[:2]
            px = X['prof']
            for v, p in main:
                d.text((px, y + 13), p, font=F(19), fill=TXT); px += d.textlength(p + ' ', font=F(19))
                d.text((px, y + 13), str(v), font=F(19, True), fill=GOLD); px += d.textlength(str(v), font=F(19, True)) + 18
            if not main: d.text((px, y + 13), 'none yet', font=F(19), fill=MUTE)
            s = seen(r['seen']); d.text((X['seen'] - 12 - d.textlength(s, font=F(18)), y + 14), s, font=F(18), fill=MUTE)
            y += rh
        panels.append((f'guild_roster_{ci + 1}.png', im))
    paths = []
    for name, im in panels:
        p = os.path.join(OUT, name); im.save(p, optimize=True); paths.append(p)
    return paths


# ---------------------------------------------------------------- discord
def multipart(payload, path):
    b = '----gb' + hashlib.md5(str(time.time()).encode()).hexdigest()
    body = (f'--{b}\r\nContent-Disposition: form-data; name="payload_json"\r\nContent-Type: application/json\r\n\r\n{json.dumps(payload)}\r\n'
            f'--{b}\r\nContent-Disposition: form-data; name="files[0]"; filename="{os.path.basename(path)}"\r\nContent-Type: image/png\r\n\r\n').encode()
    body += open(path, 'rb').read() + f'\r\n--{b}--\r\n'.encode()
    return body, {'Content-Type': 'multipart/form-data; boundary=' + b, 'User-Agent': 'GuildBoard/3.0'}


def send(paths):
    hook = secret('DISCORD_WEBHOOK_URL', 'discord_webhook.txt')
    if not hook.startswith('https://discord.com/api/webhooks/'): raise SystemExit('BAD_WEBHOOK')
    try: state = json.load(open(STATE, encoding='utf-8-sig'))
    except Exception: state = {}
    ids = [x for x in os.environ.get('DISCORD_MESSAGE_IDS', '').split(',') if x.strip()] or state.get('message_ids') or ([state['message_id']] if state.get('message_id') else [])
    if os.environ.get('DISCORD_MESSAGE_IDS') == 'none': ids = []
    out = []; did = []
    try:
        for i, p in enumerate(paths):
            payload = {'content': '', 'embeds': [], 'attachments': [{'id': 0, 'filename': os.path.basename(p)}], 'allowed_mentions': {'parse': []}}
            mid = ids[i].strip() if i < len(ids) else None; done = False
            if mid:
                body, H = multipart(payload, p)
                try:
                    http(f'{hook}/messages/{mid}', body, H, 'PATCH'); done = True; did.append('UPDATED')
                except urllib.error.HTTPError as e:
                    if e.code != 404: raise
                    if os.environ.get('EDIT_ONLY'): raise SystemExit(f'MESSAGE_GONE panel {i + 1}: refusing to post a duplicate')
            if not done and os.environ.get('EDIT_ONLY'):
                print(f'NEW_PANEL_NEEDED panel {i + 1}: add its id to DISCORD_MESSAGE_IDS'); continue
            if not done:
                payload['username'] = 'Guild Board'; body, H = multipart(payload, p)
                mid = http(hook + '?wait=true', body, H, 'POST').get('id'); did.append('POSTED')
            out.append(str(mid)); time.sleep(1)
    except urllib.error.HTTPError as e:
        raise SystemExit(f'DISCORD_ERROR {e.code}')          # never print the URL
    marker = json.dumps({'note': 'Guild Board is posted by guild_armory.py as images. Nothing to send from here.', 'at': int(time.time())}).encode()
    open(PAYLOAD, 'wb').write(marker)           # keeps the old Windows sender quiet: same hash, nothing to do
    json.dump({'message_id': out[0], 'message_ids': out, 'hash': hashlib.sha256(marker).hexdigest().upper()}, open(STATE, 'w'))
    if out: json.dump({'message_id': out[0], 'message_ids': out}, open(STATE, 'w'))
    print(' '.join(did)); print('MESSAGE_IDS', ','.join(out))


if __name__ == '__main__':
    try:
        data = fetch()
    except urllib.error.HTTPError as e:
        raise SystemExit(f'BLIZZARD_ERROR {e.code}')
    except urllib.error.URLError as e:
        raise SystemExit(f'NETWORK_ERROR {type(e.reason).__name__}')
    paths = render(data)
    if '--dry' in sys.argv: print('DRY', [os.path.basename(p) for p in paths])
    else: send(paths)
