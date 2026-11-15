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
# WoW Forever dungeons and level ranges (warcrafttavern.com, Nov 2026), short names for the roster column
DUNGEONS = [('RFC', 13, 18), ('Thanes', 13, 20), ('Lordaeron', 15, 22), ('WC', 15, 24), ('DM', 17, 26), ('SFK', 20, 30),
            ('BFD', 24, 32), ('Stocks', 25, 29), ('Excavation', 26, 33), ('Dalaran', 28, 35), ('RFK', 29, 38), ('Gnomer', 29, 38),
            ('SM', 30, 46), ('Drowned', 35, 42), ('RFD', 37, 46), ("Krol'dok", 40, 47), ('Ulda', 41, 51), ('ZF', 44, 54),
            ('Mara', 46, 55), ('Alcaz', 48, 55), ('ST', 50, 60), ('BRD', 52, 60), ('DM East', 54, 60), ('LBRS', 55, 60),
            ('Blackmaw', 55, 60), ('DM West', 56, 60), ('DM North', 56, 60), ("Shaper's", 58, 60), ('Strat', 58, 60),
            ('Scholo', 58, 60), ('UBRS', 59, 60)]

def dungeons_for(level):
    # the three best fits: the in-range dungeons with the highest starting level
    fits = sorted([(lo, n) for n, lo, hi in DUNGEONS if lo <= level <= hi], reverse=True)[:3]
    return [n for lo, n in sorted(fits)]

HISTORY = os.path.join(OUT, 'level_history.json')   # kept between runs by the workflow's cache step

def week_gains(rows, now):
    try: hist = json.load(open(HISTORY))
    except Exception: hist = {}
    gains = {}
    for r in rows:
        h = [x for x in hist.get(r['name'], []) if now - x[0] <= 8 * 86400]
        h.append([now, r['level']])
        hist[r['name']] = h[-200:]
        week = [lv for t, lv in h if now - t <= 7 * 86400]
        gains[r['name']] = (r['level'] - min(week)) if len(week) > 1 else None
    json.dump(hist, open(HISTORY, 'w'))
    return gains

def render(data, min_panels=0):
    from PIL import Image, ImageDraw, ImageFont
    FD = '/usr/share/fonts/truetype/dejavu/'
    def F(size, bold=False): return ImageFont.truetype(FD + ('DejaVuSans-Bold.ttf' if bold else 'DejaVuSans.ttf'), size)
    W = 1200; M = 56; BG = '#111318'; TXT = '#EDEFF2'; MUTE = '#9AA3B2'; GOLD = '#E0B36A'; LINE = '#3A3F4A'
    rows = data['members']; now = data['at']
    try:
        from zoneinfo import ZoneInfo
        stamp = datetime.fromtimestamp(now, ZoneInfo('America/Chicago')).strftime('%b %d, %I:%M %p CT').replace(' 0', ' ')
    except Exception:
        stamp = datetime.fromtimestamp(now, timezone.utc).strftime('%b %d, %H:%M UTC')

    ART = os.path.join(HERE, 'art', 'board_bg.png')
    art = Image.open(ART).convert('RGB') if os.path.exists(ART) else None

    def seen(ms):
        if not ms: return ''
        h = (now - ms / 1000) / 3600
        return 'under 1h ago' if h < 1 else (f'{int(h)}h ago' if h < 48 else f'{int(h / 24)}d ago')

    def fit(d, s, font, width):
        if d.textlength(s, font=font) <= width: return s
        while s and d.textlength(s + '…', font=font) > width: s = s[:-1]
        return s + '…'

    def canvas(h):
        # painted background (tools/art/board_bg.png, made once in ChatGPT) cropped to fit; plain dark without it
        if not art: return Image.new('RGBA', (W, h), BG)
        aw, ah = art.size; sc = max(W / aw, h / ah)
        bg = art.resize((int(aw * sc) + 1, int(ah * sc) + 1), Image.LANCZOS)
        x0 = (bg.width - W) // 2; y0 = (bg.height - h) // 2
        return bg.crop((x0, y0, x0 + W, y0 + h)).convert('RGBA')

    def panel(im, box, alpha=185, radius=12, outline=None):
        ov = Image.new('RGBA', im.size, (0, 0, 0, 0)); od = ImageDraw.Draw(ov)
        od.rounded_rectangle(box, radius, fill=(10, 11, 15, alpha), outline=outline)
        return Image.alpha_composite(im, ov)

    def text(d, xy, s, font, fill, anchor='la'):
        x, y = xy
        d.text((x + 2, y + 2), s, font=font, fill=(0, 0, 0, 200), anchor=anchor)
        d.text((x, y), s, font=font, fill=fill, anchor=anchor)

    def header(im, title, sub):
        im = panel(im, [M - 16, 26, W - M + 16, 118], alpha=150, radius=14)
        d = ImageDraw.Draw(im)
        text(d, (M + 4, 34), title, F(40, True), TXT)
        text(d, (M + 6, 84), sub, F(19), MUTE)
        t = 'Updated ' + stamp; text(d, (W - M - 4, 88), t, F(17), MUTE, 'ra')
        d.rectangle([M - 16, 122, W - M + 16, 125], fill=GOLD)
        return im, d

    panels = []
    # ---- crafting board: 4 columns, top 3 per profession, same shape as the roster panels
    profs = CRAFT + GATHER + SECOND
    kind = {**{p: 'Crafting' for p in CRAFT}, **{p: 'Gathering' for p in GATHER}, **{p: 'Everyday' for p in SECOND}}
    by = {}
    for r in rows:
        for p, v in r['skills'].items(): by.setdefault(p, []).append((v, r['name'], r['cls']))
    cols = 4; gap = 16; TOP = 3; lh = 32
    cw = (W - 2 * M - gap * (cols - 1)) // cols; ch = 58 + TOP * lh + 10
    nrow = (len(profs) + cols - 1) // cols
    Hh = 140 + nrow * (ch + gap) + 40
    im = canvas(Hh)
    im, d = header(im, f"{data['guild']}: Who Can Make What", f"{data['faction']} · {len(rows)} members · top {TOP} per profession, skill out of {MAXSKILL}")
    for i, p in enumerate(profs):
        cx = M + (i % cols) * (cw + gap); cy = 140 + (i // cols) * (ch + gap)
        im = panel(im, [cx, cy, cx + cw, cy + ch], alpha=190, outline=(224, 179, 106, 90))
        d = ImageDraw.Draw(im)
        who = sorted(by.get(p, []), reverse=True)
        text(d, (cx + 14, cy + 12), p, F(21, True), TXT)
        text(d, (cx + 14, cy + 38), kind[p].upper() + (f'  ·  {len(who)} in guild' if who else '  ·  nobody yet'), F(12, True), GOLD)
        for j, (v, name, cls) in enumerate(who[:TOP]):
            ly = cy + 62 + j * lh
            text(d, (cx + 14, ly), fit(d, name, F(16), cw - 66), F(16), CLASS_COLOR.get(cls, TXT))
            text(d, (cx + cw - 12, ly), str(v), F(17, True), GOLD, 'ra')
    panels.append(('guild_crafting.png', im))

    # ---- roster panels (anyone offline 7+ days is hidden until they log back in)
    AWAY = 7 * 86400
    hidden = [r for r in rows if r['seen'] and now - r['seen'] / 1000 >= AWAY]
    rows = [r for r in rows if r not in hidden]
    away_note = f", {len(hidden)} away 7+ days hidden" if hidden else ""
    gains = week_gains(rows, now)
    PER = 10; rh = 50
    chunks = [rows[i:i + PER] for i in range(0, len(rows), PER)] or [[]]
    X = {'name': M + 18, 'lvl': 470, 'cls': 492, 'ilvl': 676, 'dung': 700, 'week': 1004, 'seen': W - M - 14}
    for ci, chunk in enumerate(chunks):
        Hh = 140 + 36 + PER * rh + 36       # every roster panel is the same height, so Discord shows them the same size
        im = canvas(Hh)
        a = ci * PER + 1
        im, d = header(im, f"{data['guild']} Roster", f"Members {a} to {a + max(len(chunk), 1) - 1} of {len(rows)}, highest level first{away_note}")
        y = 140
        for label, x, anc in (('NAME', X['name'], 'la'), ('LVL', X['lvl'], 'ra'), ('CLASS', X['cls'], 'la'), ('ILVL', X['ilvl'], 'ra'),
                              ('DUNGEONS IN RANGE', X['dung'], 'la'), ('THIS WEEK', X['week'], 'ra'), ('LAST SEEN', X['seen'], 'ra')):
            text(d, (x, y + 6), label, F(14, True), GOLD, anc)
        y += 34
        for i, r in enumerate(chunk):
            col = CLASS_COLOR.get(r['cls'], TXT)
            im = panel(im, [M - 6, y, W - M + 6, y + rh - 6], alpha=200 if i % 2 == 0 else 170, radius=8)
            d = ImageDraw.Draw(im)
            d.rounded_rectangle([M - 6, y, M, y + rh - 6], 3, fill=col)
            nm = fit(d, r['name'], F(21, True), 330); text(d, (X['name'], y + 11), nm, F(21, True), col)
            if r['rank'] == 0:
                tx = X['name'] + d.textlength(nm, font=F(21, True)) + 10
                d.rounded_rectangle([tx, y + 12, tx + 40, y + 33], 5, fill=GOLD); d.text((tx + 7, y + 14), 'GM', font=F(14, True), fill='#111318')
            text(d, (X['lvl'], y + 10), str(r['level']), F(22, True), TXT, 'ra')
            text(d, (X['cls'], y + 13), fit(d, (r['race'] + ' ' + r['cls']).strip(), F(17), 165), F(17), MUTE)
            text(d, (X['ilvl'], y + 12), str(r['ilvl'] or '-'), F(18), TXT, 'ra')
            dz = dungeons_for(r['level'])
            dtxt = ', '.join(dz) if dz else ('too low yet' if r['level'] < 13 else 'none')
            text(d, (X['dung'], y + 13), fit(d, dtxt, F(17), X['week'] - X['dung'] - 95), F(17), TXT if dz else MUTE)
            g = gains.get(r['name']); gt = '-' if g is None else (f'+{g}' if g > 0 else '0')
            text(d, (X['week'], y + 12), gt, F(19, True), GOLD if (g or 0) > 0 else MUTE, 'ra')
            text(d, (X['seen'], y + 14), seen(r['seen']), F(16), MUTE, 'ra')
            y += rh
        panels.append((f'guild_roster_{ci + 1}.png', im))

    # keep the same number of Discord posts when the roster shrinks: fill spare posts with a short note
    n = len(panels)
    while len(panels) < min_panels:
        im = canvas(300)
        im, d = header(im, f"{data['guild']} Roster", f"That's everyone active this week{away_note}.")
        panels.append((f'guild_roster_spare_{len(panels) - n + 1}.png', im))
    paths = []
    for name, im in panels:
        p = os.path.join(OUT, name); im.convert('RGB').save(p, optimize=True); paths.append(p)
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
    ids_env = os.environ.get('DISCORD_MESSAGE_IDS', '')
    want = 0 if ids_env == 'none' else len([x for x in ids_env.split(',') if x.strip()])
    paths = render(data, want)
    if '--dry' in sys.argv: print('DRY', [os.path.basename(p) for p in paths])
    else: send(paths)
