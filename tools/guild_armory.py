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

# Level floor for the whole board: people under it are hidden everywhere (roster, crafting, Wall of Heroes).
# It rises on its own: 20 now, 30 from Dec 15 2026, 40 from Jan 15 2027.
LEVEL_FLOOR = [('2027-01-15', 40), ('2026-12-15', 30), ('2000-01-01', 20)]

def level_floor(now_ts):
    day = datetime.fromtimestamp(now_ts, timezone.utc).strftime('%Y-%m-%d')
    for start, lvl in LEVEL_FLOOR:
        if day >= start: return lvl
    return 20


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
    floor = level_floor(now)
    rows = [r for r in rows if (r.get('level') or 0) >= floor]
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
    im, d = header(im, 'Who Can Make What', f"{data['guild']}  ·  {len(rows)} members level {floor}+  ·  top {TOP}, skill out of {MAXSKILL}")
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
        im, d = header(im, 'Guild Roster', f"Level {floor}+  ·  {a} to {a + max(len(chunk), 1) - 1} of {len(rows)}{away_note}")
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
    # ---- right side of the Wall of Heroes: who helped build it (data/feedback.json, kept by the daily
    #      bug fix patrol) and the dunce corner for anyone caught sending a request meant to break things
    def credits_and_dunce(im, x0, x1, y0, y1):
        try: fb = json.load(open(os.path.join(HERE, '..', 'data', 'feedback.json'), encoding='utf-8'))
        except Exception: fb = {}
        cred = {}
        for it in fb.get('items', []):
            who = (it.get('who') or '').strip(); who = (fb.get('aliases') or {}).get(who, who)   # one person, one name
            if not who or it.get('status') == 'declined': continue
            c = cred.setdefault(who, {'shipped': 0, 'queued': 0})
            c['shipped' if it.get('status') == 'shipped' else 'queued'] += 1
        crew = sorted(cred.items(), key=lambda kv: (-kv[1]['shipped'], -kv[1]['queued'], kv[0].lower()))
        split = y0 + 268
        acc = (180, 140, 255)
        im = panel(im, [x0, y0, x1, split], outline=acc + (150,)); d = ImageDraw.Draw(im)
        d.rounded_rectangle([x0, y0, x1, y0 + 5], 2, fill=acc)
        text(d, (x0 + 16, y0 + 32), 'HELPED BUILD IT', F(18, 'Bold'), acc)
        text(d, (x1 - 16, y0 + 32), str(len(crew)), F(24, 'Bold'), TXT, 'rm')
        text(d, (x0 + 16, y0 + 58), 'bug reports and ideas that made it in', F(12, 'Medium'), MUTE)
        d.line([x0 + 16, y0 + 74, x1 - 16, y0 + 74], fill=acc + (90,))
        room = int((split - 16 - (y0 + 92)) // 30)
        for j, (who, c) in enumerate(crew[:room]):
            ly = y0 + 94 + j * 30
            tag = ' · '.join(x for x in (f"{c['shipped']} shipped" if c['shipped'] else '', f"{c['queued']} queued" if c['queued'] else '') if x)
            text(d, (x0 + 16, ly), fit(d, who, F(15, 'Bold'), x1 - x0 - 140), F(15, 'Bold'), TXT if c['shipped'] else MUTE)
            text(d, (x1 - 16, ly), tag, F(12, 'Medium'), GOLD if c['shipped'] else MUTE, 'rm')
        if len(crew) > room: text(d, (x1 - 16, split - 18), f"+{len(crew) - room} more", F(12, 'Medium'), MUTE, 'rm')
        if not crew: text(d, ((x0 + x1) // 2, y0 + 130), 'report a bug in #guild-board', F(14, 'Medium'), MUTE, 'mm')
        # dunce corner: painted goblin, name on the wood, gone after 7 days
        dy0 = split + 12; red = (210, 70, 50)
        dun = [dict(x, who=(fb.get('aliases') or {}).get(x.get('who'), x.get('who'))) for x in fb.get('dunce', []) if now - x.get('at', 0) < 7 * 86400]
        dun.sort(key=lambda x: -x.get('at', 0))
        art_p = os.path.join(HERE, 'art', 'dunce_goblin.png')
        bw, bh = x1 - x0, y1 - dy0
        if os.path.exists(art_p):
            g = Image.open(art_p).convert('RGBA')
            sc = max(bw / g.width, bh / g.height); g = g.resize((int(g.width * sc) + 1, int(g.height * sc) + 1), Image.LANCZOS)
            gx = (g.width - bw) // 2 + int(bw * 0.12); gy = (g.height - bh) // 2
            g = g.crop((min(gx, g.width - bw), gy, min(gx, g.width - bw) + bw, gy + bh))
            if not dun:
                g = Image.blend(g, Image.new('RGBA', g.size, (12, 9, 7, 255)), 0.55)
            m = Image.new('L', (bw, bh), 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, bw - 1, bh - 1], 10, fill=255)
            im.paste(g, (x0, dy0), m)
        ov = Image.new('RGBA', im.size, (0, 0, 0, 0)); od = ImageDraw.Draw(ov)
        band = 62 if len(dun) < 2 else 92
        od.rectangle([x0, dy0, x1, dy0 + 46], fill=(8, 5, 3, 170)); od.rectangle([x0, y1 - band, x1, y1], fill=(8, 5, 3, 195))
        od.rounded_rectangle([x0, dy0, x1, y1], 10, outline=red + (200,), width=2)
        im = Image.alpha_composite(im, ov); d = ImageDraw.Draw(im)
        text(d, (x0 + 16, dy0 + 23), 'DUNCE CORNER', F(18, 'Bold'), red)
        if len(dun) == 1:
            text(d, (x1 - 16, dy0 + 23), 'this week', F(12, 'Medium'), MUTE, 'rm')
            text(d, ((x0 + x1) // 2, y1 - 42), fit(d, dun[0].get('who', '?'), F(24, 'Bold'), bw - 30), F(24, 'Bold'), TXT, 'mm')
            text(d, ((x0 + x1) // 2, y1 - 16), fit(d, dun[0].get('why', ''), F(12, 'Medium'), bw - 24), F(12, 'Medium'), GOLD, 'mm')
        elif dun:
            # everyone gets called out: two rows of name + crime, newest first, then "+N more"
            shown = dun[:2]; rest = len(dun) - len(shown)
            text(d, (x1 - 16, dy0 + 23), f"{len(dun)} this week", F(12, 'Medium'), MUTE, 'rm')
            for k, x in enumerate(shown):
                ry = y1 - band + 8 + k * 40
                text(d, (x0 + 14, ry + 9), fit(d, x.get('who', '?'), F(18, 'Bold'), bw - 28), F(18, 'Bold'), TXT)
                text(d, (x0 + 14, ry + 28), fit(d, x.get('why', ''), F(11, 'Medium'), bw - 28), F(11, 'Medium'), GOLD)
            if rest > 0: text(d, (x1 - 14, y1 - band + 17), f"+{rest} more", F(12, 'Medium'), MUTE, 'rm')
        else:
            text(d, ((x0 + x1) // 2, y1 - 40), 'Empty. Keep it that way.', F(17, 'Bold'), TXT, 'mm')
            text(d, ((x0 + x1) // 2, y1 - 17), 'troll requests earn the hat', F(12, 'Medium'), MUTE, 'mm')
        return im

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
        if not latest and known: latest = max(known, key=vkey)      # only if GitHub can't be reached
        # anyone on the published release or a newer test build counts as a hero
        heroes, old, none = [], [], []
        for r in rows:
            k = has_addon(r['name'], users)
            v = users[k].get('version') if k else None
            if not k: none.append((r, ''))
            elif v and latest and vkey(v) < vkey(latest): old.append((r, v))
            else: heroes.append((r, v or '?'))
        im = canvas()
        im, d = header(im, 'Wall of Heroes', f"Guild Board addon  ·  latest is {latest or '?'}  ·  level {floor}+, active in the last 7 days")
        cols = [('HEROES', 'on the latest version or newer', heroes, (90, 200, 110)),
                ('OLD VERSION', 'time to update', old, (232, 170, 60)),
                ('NO ADDON', 'grab it from #addons', none, (210, 70, 50))]
        LX1 = 786; RX0 = 800                     # left: the three version columns  ·  right: credits and the dunce corner
        gap = 12; cw = (LX1 - X0 - gap * 2) / 3; lh = 34; top = Y0
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
                tag = (f"v{v}" if v and v != '?' else '') if title != 'NO ADDON' else f"lvl {r['level']}"
                tcol = MUTE
                # newer than the published release = a test build
                if title == 'HEROES' and v and v != '?' and latest and vkey(v) > vkey(latest):
                    tag, tcol = f"v{v} experimental", (180, 140, 255)
                if title == 'HEROES' and tag.endswith('experimental'): tag = 'test build'
                room_name = cw - 36 - (d.textlength(tag, font=F(12, 'Medium')) if tag else 0)
                text(d, (cx + 14, ly), fit(d, r['name'], F(15, 'Bold'), room_name), F(15, 'Bold'), col)
                if tag: text(d, (cx2 - 14, ly), tag, F(12, 'Medium'), tcol, 'rm')
            if len(lst) > room: text(d, (cx2 - 18, foot_y - 32), f"+{len(lst) - room} more", F(13, 'Medium'), MUTE, 'rm')
            if not lst: text(d, ((cx + cx2) // 2, top + 130), 'nobody', F(16, 'Medium'), MUTE, 'mm')
        im = panel(im, [X0, foot_y, LX1, Y1], outline=(232, 185, 100, 110)); d = ImageDraw.Draw(im)
        tot = max(len(rows), 1); have = len(heroes) + len(old)
        text(d, (X0 + 20, foot_y + 28), f"ADDON CREW  {have} of {len(rows)}", F(13, 'Bold'), GOLD)
        bx = X0 + 210
        d.rounded_rectangle([bx, foot_y + 20, LX1 - 20, foot_y + 36], 8, fill=(40, 30, 22))
        w = LX1 - 20 - bx
        if heroes: d.rounded_rectangle([bx, foot_y + 20, bx + int(w * len(heroes) / tot), foot_y + 36], 8, fill=(90, 200, 110))
        if old:
            x0 = bx + int(w * len(heroes) / tot)
            d.rounded_rectangle([x0, foot_y + 20, x0 + int(w * len(old) / tot), foot_y + 36], 8, fill=(232, 170, 60))
        im = credits_and_dunce(im, RX0, X1, top, Y1)
        shame = ('guild_wall_of_heroes.png', im)

    # keep the same number of Discord posts when the roster shrinks: same-size board with a short note
    n = len(panels)
    while len(panels) < (min_panels - 1 if shame else min_panels):
        im = canvas()
        im, d = header(im, 'Guild Roster', f"{len(rows)} active at level {floor}+{away_note}")
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
    # more panels than Discord posts (roster grew): the Wall of Heroes keeps the last post, extra roster pages wait
    if want and len(paths) > want and paths[-1].endswith('guild_wall_of_heroes.png'):
        print(f'NEW_PANEL_NEEDED {len(paths) - want} roster page(s) not shown: run with add_panels or add a post id')
        paths = paths[:want - 1] + [paths[-1]]
    if '--dry' in sys.argv: print('DRY', [os.path.basename(p) for p in paths])
    else: send(paths)
