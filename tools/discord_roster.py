"""Post or update the Guild Board roster card in a Discord channel through a webhook.

Env: DISCORD_WEBHOOK_URL (secret), ROSTER_JSON (members dict from roster_json.py),
     MESSAGE_ID (optional: edit this message instead of posting a new one),
     GUILD_NAME (optional title).
Prints only the message id. Never prints the webhook URL. No DPS by design.
"""
import json, os, sys, time, urllib.request, urllib.error

CLASS_COLOR = {"Warrior": 0xC69B6D, "Paladin": 0xF48CBA, "Hunter": 0xAAD372, "Rogue": 0xFFF468,
    "Priest": 0xFFFFFF, "Shaman": 0x0070DD, "Mage": 0x3FC7EB, "Warlock": 0x8788EE, "Druid": 0xFF7C0A,
    "Death Knight": 0xC41E3A, "Monk": 0x00FF98, "Demon Hunter": 0xA330C9, "Evoker": 0x33937F}

def seen(ts):
    if not ts:
        return "-"
    h = int((time.time() - (ts or 0)) / 3600)
    return "now" if h < 1 else f"{h}h ago" if h < 48 else f"{h // 24}d ago"

def profs_of(m):
    out = []
    for p in (m.get("profs") or "").split(","):
        parts = p.split(":")
        if len(parts) == 3 and parts[0]:
            out.append((parts[0], int(parts[1])))
    return out

ANSI = {"Warrior": 33, "Rogue": 33, "Paladin": 35, "Warlock": 35, "Demon Hunter": 35, "Hunter": 32,
    "Monk": 32, "Evoker": 32, "Priest": 37, "Shaman": 34, "Mage": 36, "Druid": 31, "Death Knight": 31}

def paint(text, code, bold=False):
    return f"\u001b[{1 if bold else 0};{code}m{text}\u001b[0m"

def cut(t, n):
    t = str(t or "")
    return t if len(t) <= n else t[:n - 1] + "."

def build(members, guild):
    rows = sorted(members.items(), key=lambda kv: (-(kv[1].get("level") or 0), kv[0]))
    by_prof, notes, lines = {}, [], []
    lines.append(paint(f"{'Name':<18} {'Lv':>2}  {'Class':<8} {'Zone':<12} Seen", 30))
    lines.append(paint("-" * 50, 30))
    for key, m in rows:
        name = key.split("-")[0]
        spec = m.get("spec") or ""
        cls = m.get("class") or "?"
        what = spec if spec and spec != cls else cls
        c = ANSI.get(cls, 37)
        lines.append(paint(f"{cut(name, 18):<18}", c, True) + f" {m.get('level', 0):>2}  " + paint(f"{cut(what, 8):<8}", c)
                     + paint(f" {cut(m.get('zone') or '-', 12):<12} {seen(m.get('ts'))}", 30))
        for pn, rank in profs_of(m):
            by_prof.setdefault(pn, []).append((name, rank))
        if m.get("note"):
            notes.append(f"**{name}**: {m['note']}")
    desc = f"**{len(rows)} members reporting**\n```ansi\n" + "\n".join(lines) + "\n```"
    fields = []
    if by_prof:
        w = max(len(p) for p in by_prof)
        txt = "\n".join(f"{p:<{w}}  " + ", ".join(f"{n} {r}" for n, r in sorted(v, key=lambda x: -x[1]))
                        for p, v in sorted(by_prof.items()))
        fields.append({"name": "Crafters", "value": ("```\n" + txt)[:1016] + "\n```", "inline": False})
    if notes:
        fields.append({"name": "Notes", "value": "\n".join(notes)[:1024], "inline": False})
    return {"username": "Guild Board", "embeds": [{
        "title": f"{guild} roster",
        "description": desc[:4096],
        "color": CLASS_COLOR.get(rows[0][1].get("class"), 0x5865F2) if rows else 0x5865F2,
        "fields": fields,
        "footer": {"text": "Install Guild Board from #addons · type /gb in game"},
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}],
        "allowed_mentions": {"parse": []}}

def send(url, payload, msg_id, png=None):
    if png:
        payload = dict(payload, attachments=[{"id": 0, "filename": "roster.png"}])
        b = "----guildboard" + str(int(time.time() * 1000))
        body = (f"--{b}\r\nContent-Disposition: form-data; name=\"payload_json\"\r\nContent-Type: application/json\r\n\r\n"
                + json.dumps(payload) + f"\r\n--{b}\r\nContent-Disposition: form-data; name=\"files[0]\"; filename=\"roster.png\"\r\n"
                  "Content-Type: image/png\r\n\r\n").encode() + png + f"\r\n--{b}--\r\n".encode()
        ctype = f"multipart/form-data; boundary={b}"
    else:
        body, ctype = json.dumps(payload).encode(), "application/json"
    if msg_id:
        req = urllib.request.Request(f"{url}/messages/{msg_id}", method="PATCH")
    else:
        req = urllib.request.Request(f"{url}?wait=true", method="POST")
    req.add_header("Content-Type", ctype)
    req.add_header("User-Agent", "GuildBoard (github.com/KrisHendo09/guild-board, 1.0)")
    with urllib.request.urlopen(req, body) as r:
        return json.load(r)["id"]

def image_payload(members, guild):
    n = len(members)
    return {"username": "Guild Board", "content": "", "embeds": [{
        "color": 0xE6B450, "image": {"url": "attachment://roster.png"},
        "footer": {"text": f"{n} members reporting · install Guild Board from #addons · /gb in game"}}],
        "allowed_mentions": {"parse": []}}

if __name__ == "__main__":
    members = json.loads(os.environ.get("ROSTER_JSON") or "{}")
    guild = os.environ.get("GUILD_NAME") or "Guild"
    png = None
    try:
        import io, roster_image
        buf = io.BytesIO(); roster_image.render(members, guild, buf); png = buf.getvalue()
        payload = image_payload(members, guild)
    except Exception as e:
        print(f"image skipped ({e}); posting text card")
        payload = build(members, guild)
    if "--dry" in sys.argv:
        print(json.dumps(payload, indent=2)[:400], "png bytes:", len(png or b"")); sys.exit(0)
    url = (os.environ.get("DISCORD_WEBHOOK_URL") or "").strip()
    if not url.startswith("https://"):
        print("DISCORD_WEBHOOK_URL is empty or not a URL. Add it under Settings > Secrets and variables > Actions > Repository secrets."); sys.exit(1)
    msg_id = (os.environ.get("MESSAGE_ID") or "").strip()
    try:
        new_id = send(url, payload, msg_id, png)
    except urllib.error.HTTPError as e:
        if msg_id and e.code == 404:  # old message deleted, post a fresh one
            new_id = send(url, payload, "", png)
        else:
            print(f"Discord error {e.code}: {e.read()[:300].decode(errors='replace')}"); sys.exit(1)
    print(f"message_id={new_id}")
