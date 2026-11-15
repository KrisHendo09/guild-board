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
    GF = os.path.join(HERE, 'art', 'fonts') + os.sep      # Poppins (OFL) ships in the repo so GitHub draws the same thing
    _fc = {}
    def F(size, w='Regular'):
        w = {'SemiBold': 'Bold'}.get(w, w)
        k = (size, w)
        if k not in _fc:
            try: _fc[k] = ImageFont.truetype(GF + f'Poppins-{w}.ttf', size)
            except OSError: _fc[k] = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans' + ('-Bold' if w in ('Bold', 'SemiBold') else '') + '.ttf', size)
        return _fc[k]
    # every panel is the painted board at its own 3:2 shape, so the frame, banner and torches always line up
    W, H = 1200, 800
    X0, X1, Y0, Y1 = 58, 1142, 214, 748        # inside the iron frame, below the banner and torches
    BG = '#111318'; TXT = '#F1E9DA'; MUTE = '#A79C8A'; GOLD = '#E8B964'
    rows = data['members']; now = data['at']
    try:
        from zoneinfo import ZoneInfo
        stamp = datetime.fromtimestamp(now, ZoneInfo('America/Chicago')).strftime('%b %d, %I:%M %p CT').replace(' 0', ' ')
    except Exception:
        stamp = datetime.fromtimestamp(now, timezone.utc).strftime('%b %d, %H:%M UTC')

    ART = os.path.join(HERE, 'art', 'board_bg.png')
    art = Image.open(ART).convert('RGBA').resize((W, H), Image.LANCZOS) if os.path.exists(ART) else None

    def seen(ms):
        if not ms: return ''
        h = (now - ms / 1000) / 3600
        return 'under 1h ago' if h < 1 else (f'{int(h)}h ago' if h < 48 else f'{int(h / 24)}d ago')

    def fit(d, s, font, width):
        if d.textlength(s, font=font) <= width: return s
        while s and d.textlength(s + '…', font=font) > width: s = s[:-1]
        return s + '…'

    def canvas():
        return art.copy() if art else Image.new('RGBA', (W, H), BG)

    def panel(im, box, alpha=200, radius=10, outline=None):
        ov = Image.new('RGBA', im.size, (0, 0, 0, 0)); od = ImageDraw.Draw(ov)
        od.rounded_rectangle(box, radius, fill=(12, 9, 7, alpha), outline=outline, width=1)
        return Image.alpha_composite(im, ov)

    def text(d, xy, s, font, fill, anchor='lm'):
        x, y = xy
        d.text((x + 1, y + 2), s, font=font, fill=(0, 0, 0, 220), anchor=anchor)
        d.text((x, y), s, font=font, fill=fill, anchor=anchor)

    def header(im, title, sub):
        d = ImageDraw.Draw(im)
        text(d, (W // 2, 98), title, F(38, 'Bold'), GOLD, 'mm')
        text(d, (W // 2, 140), f'{sub}  ·  updated {stamp}', F(16, 'Medium'), MUTE, 'mm')
        return im, d

    panels = []
    # ---- crafting board: 4 x 3 cards, top 3 per profession
    profs = CRAFT + GATHER + SECOND
    kind = {**{p: 'Crafting' for p in CRAFT}, **{p: 'Gathering' for p in GATHER}, **{p: 'Everyday' for p in SECOND}}
    by = {}
    for r in rows:
        for p, v in r['skills'].items(): by.setdefault(p, []).append((v, r['name'], r['cls']))
    cols = 4; gap = 14; TOP = 3; lh = 31
    nrow = (len(profs) + cols - 1) // cols
    cw = (X1 - X0 - gap * (cols - 1)) / cols; ch = (Y1 - Y0 - gap * (nrow - 1)) / nrow
    im = canvas()
    im, d = header(im, 'Who Can Make What', f"{data['guild']}  ·  {len(rows)} members  ·  top {TOP}, skill out of {MAXSKILL}")
    for i, p in enumerate(profs):
        cx = int(X0 + (i % cols) * (cw + gap)); cy = int(Y0 + (i // cols) * (ch + gap)); cx2 = int(cx + cw); cy2 = int(cy + ch)
        im = panel(im, [cx, cy, cx2, cy2], outline=(232, 185, 100, 110))
        d = ImageDraw.Draw(im)
        who = sorted(by.get(p, []), reverse=True)
        text(d, (cx + 16, cy + 24), p, F(20, 'SemiBold'), TXT)
        text(d, (cx + 16, cy + 50), kind[p].upper() + (f'  ·  {len(who)} in guild' if who else '  ·  nobody yet'), F(11, 'SemiBold'), GOLD)
        d.line([cx + 16, cy + 64, cx2 - 16, cy + 64], fill=(232, 185, 100, 70))
        for j, (v, name, cls) in enumerate(who[:TOP]):
            ly = cy + 86 + j * lh
            text(d, (cx + 16, ly), fit(d, name, F(16, 'Medium'), cw - 80), F(16, 'Medium'), CLASS_COLOR.get(cls, TXT))
            text(d, (cx2 - 16, ly), str(v), F(16, 'Bold'), GOLD, 'rm')
    panels.append(('guild_crafting.png', im))

    # ---- roster panels (anyone offline 7+ days is hidden until they log back in)
    AWAY = 7 * 86400
    hidden = [r for r in rows if r['seen'] and now - r['seen'] / 1000 >= AWAY]
    rows = [r for r in rows if r not in hidden]
    away_note = f"  ·  {len(hidden)} away 7+ days hidden" if hidden else ""
    gains = week_gains(rows, now)
    PER = 10; hh = 30; rh = (Y1 - Y0 - hh) // PER
    chunks = [rows[i:i + PER] for i in range(0, len(rows), PER)] or [[]]
    X = {'name': X0 + 20, 'lvl': 430, 'cls': 452, 'ilvl': 652, 'dung': 678, 'week': 1010, 'seen': X1 - 14}
    for ci, chunk in enumerate(chunks):
        im = canvas()
        a = ci * PER + 1
        im, d = header(im, 'Guild Roster', f"Members {a} to {a + max(len(chunk), 1) - 1} of {len(rows)}{away_note}")
        y = Y0
        for label, x, anc in (('NAME', X['name'], 'lm'), ('LVL', X['lvl'], 'rm'), ('CLASS', X['cls'], 'lm'), ('ILVL', X['ilvl'], 'rm'),
                              ('DUNGEONS IN RANGE', X['dung'], 'lm'), ('THIS WEEK', X['week'], 'rm'), ('LAST SEEN', X['seen'], 'rm')):
            text(d, (x, y + hh // 2), label, F(12, 'SemiBold'), GOLD, anc)
        y += hh
        for i, r in enumerate(chunk):
            col = CLASS_COLOR.get(r['cls'], TXT)
            im = panel(im, [X0, y + 2, X1, y + rh - 3], alpha=215 if i % 2 == 0 else 185, radius=7)
            d = ImageDraw.Draw(im)
            d.rounded_rectangle([X0, y + 2, X0 + 5, y + rh - 3], 2, fill=col)
            m = y + rh // 2
            nm = fit(d, r['name'], F(19, 'SemiBold'), 300); text(d, (X['name'], m), nm, F(19, 'SemiBold'), col)
            if r['rank'] == 0:
                tx = X['name'] + d.textlength(nm, font=F(19, 'SemiBold')) + 10
                d.rounded_rectangle([tx, m - 11, tx + 38, m + 11], 5, fill=GOLD); d.text((tx + 19, m + 1), 'GM', font=F(12, 'Bold'), fill='#111318', anchor='mm')
            text(d, (X['lvl'], m), str(r['level']), F(19, 'Bold'), TXT, 'rm')
            text(d, (X['cls'], m), fit(d, (r['race'] + ' ' + r['cls']).strip(), F(15), 180), F(15), MUTE)
            text(d, (X['ilvl'], m), str(r['ilvl'] or '-'), F(16, 'Medium'), TXT, 'rm')
            dz = dungeons_for(r['level'])
            dtxt = ', '.join(dz) if dz else ('too low yet' if r['level'] < 13 else 'none')
            text(d, (X['dung'], m), fit(d, dtxt, F(15), X['week'] - X['dung'] - 100), F(15), TXT if dz else MUTE)
            g = gains.get(r['name']); gt = '-' if g is None else (f'+{g}' if g > 0 else '0')
            text(d, (X['week'], m), gt, F(17, 'Bold'), GOLD if (g or 0) > 0 else MUTE, 'rm')
            text(d, (X['seen'], m), seen(r['seen']), F(14), MUTE, 'rm')
            y += rh
        panels.append((f'guild_roster_{ci + 1}.png', im))

    # ---- wall of heroes: who's on the newest addon, who's behind, who doesn't have it
    #      (data/addon_users.json comes from Kris's copy of the addon; newest = latest GitHub release)
    def has_addon(name, users):
        n = name.lower()
        for k in users:
            k2 = k.lower()
            if k2 == n or k2.split('-')[0] == n.split(' ')[0] or n == k2.split(' ')[0]: return k
        return None
    def vkey(v):
        try: return tuple(int(x) for x in str(v).lstrip('v').split('.')[:3])
        except Exception: return (0,)
    shame = None
    try: addon = json.load(open(os.path.join(HERE, '..', 'data', 'addon_users.json')))
    except Exception: addon = None
    if addon is not None:
        users = addon.get('users', {})
        latest = None
        try:
            req = urllib.request.Request('https://api.github.com/repos/KrisHendo09/guild-board/releases/latest', headers={'User-Agent': 'GuildBoard'})
            latest = json.load(urllib.request.urlopen(req, timeout=10)).get('tag_name', '').lstrip('v') or None
        except Exception: pass
        known = [u['version'] for u in users.values() if u.get('version')]
        if known and (not latest or vkey(max(known, key=vkey)) > vkey(latest)): latest = max(known, key=vkey)
        heroes, old, none = [], [], []
        for r in rows:
            k = has_addon(r['name'], users)
            v = users[k].get('version') if k else None
            if not k: none.append((r, ''))
            elif v and latest and vkey(v) < vkey(latest): old.append((r, v))
            else: heroes.append((r, v or '?'))
        im = canvas()
        im, d = header(im, 'Wall of Heroes', f"Guild Board addon  ·  latest is {latest or '?'}  ·  active in the last 7 days")
        cols = [('HEROES', 'on the latest version', heroes, (90, 200, 110)),
                ('OLD VERSION', 'time to update', old, (232, 170, 60)),
                ('NO ADDON', 'grab it from #addons', none, (210, 70, 50))]
        gap = 14; cw = (X1 - X0 - gap * 2) / 3; lh = 34; top = Y0
        foot_y = Y1 - 56
        for ci, (title, sub, lst, acc) in enumerate(cols):
            cx = int(X0 + ci * (cw + gap)); cx2 = int(cx + cw)
            im = panel(im, [cx, top, cx2, foot_y - 12], outline=acc + (150,)); d = ImageDraw.Draw(im)
            d.rounded_rectangle([cx, top, cx2, top + 5], 2, fill=acc)
            text(d, (cx + 18, top + 32), title, F(19, 'Bold'), acc)
            text(d, (cx2 - 18, top + 32), str(len(lst)), F(26, 'Bold'), TXT, 'rm')
            text(d, (cx + 18, top + 58), sub, F(13, 'Medium'), MUTE)
            d.line([cx + 18, top + 76, cx2 - 18, top + 76], fill=acc + (90,))
            room = int((foot_y - 24 - (top + 96)) // lh)
            for j, (r, v) in enumerate(lst[:room]):
                ly = top + 98 + j * lh
                col = CLASS_COLOR.get(r['cls'], TXT)
                text(d, (cx + 18, ly), fit(d, r['name'], F(16, 'Bold'), cw - 110), F(16, 'Bold'), col)
                tag = (f"v{v}" if v and v != '?' else '') if title != 'NO ADDON' else f"lvl {r['level']}"
                if tag: text(d, (cx2 - 18, ly), tag, F(13, 'Medium'), MUTE, 'rm')
            if len(lst) > room: text(d, (cx2 - 18, foot_y - 32), f"+{len(lst) - room} more", F(13, 'Medium'), MUTE, 'rm')
            if not lst: text(d, ((cx + cx2) // 2, top + 130), 'nobody', F(16, 'Medium'), MUTE, 'mm')
        im = panel(im, [X0, foot_y, X1, Y1], outline=(232, 185, 100, 110)); d = ImageDraw.Draw(im)
        tot = max(len(rows), 1); have = len(heroes) + len(old)
        text(d, (X0 + 20, foot_y + 28), f"ADDON CREW  {have} of {len(rows)}", F(13, 'Bold'), GOLD)
        bx = X0 + 250
        d.rounded_rectangle([bx, foot_y + 20, X1 - 20, foot_y + 36], 8, fill=(40, 30, 22))
        w = X1 - 20 - bx
        if heroes: d.rounded_rectangle([bx, foot_y + 20, bx + int(w * len(heroes) / tot), foot_y + 36], 8, fill=(90, 200, 110))
        if old:
            x0 = bx + int(w * len(heroes) / tot)
            d.rounded_rectangle([x0, foot_y + 20, x0 + int(w * len(old) / tot), foot_y + 36], 8, fill=(232, 170, 60))
        shame = ('guild_wall_of_heroes.png', im)

    # keep the same number of Discord posts when the roster shrinks: same-size board with a short note
    n = len(panels)
    while len(panels) < (min_panels - 1 if shame else min_panels):
        im = canvas()
        im, d = header(im, 'Guild Roster', f"{len(rows)} active{away_note}")
        text(d, (W // 2, (Y0 + Y1) // 2), "That's everyone active this week.", F(26, 'SemiBold'), MUTE, 'mm')
        panels.append((f'guild_roster_spare_{len(panels) - n + 1}.png', im))
    if shame: panels.append(shame)          # always the last Discord post
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
            if not done and os.environ.get('EDIT_ONLY') and not (os.environ.get('ADD_PANELS') == 'true' and not mid):
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
