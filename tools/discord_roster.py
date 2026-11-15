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
        return "unknown"
    h = int((time.time() - (ts or 0)) / 3600)
    return "now" if h < 1 else f"{h}h ago" if h < 48 else f"{h // 24}d ago"

def profs_of(m):
    out = []
    for p in (m.get("profs") or "").split(","):
        parts = p.split(":")
        if len(parts) == 3 and parts[0]:
            out.append((parts[0], int(parts[1])))
    return out

def build(members, guild):
    rows = sorted(members.items(), key=lambda kv: (-(kv[1].get("level") or 0), kv[0]))
    by_prof, fields = {}, []
    for key, m in rows:
        name = key.split("-")[0]
        cls = m.get("class") or "?"
        spec = m.get("spec") or ""
        what = f"{spec} {cls}" if spec and spec != cls else cls
        ps = profs_of(m)
        for pn, rank in ps:
            by_prof.setdefault(pn, []).append((name, rank))
        lines = [f"Lv **{m.get('level', 0)}** {what}" + (f"  ·  ilvl {m['ilvl']}" if m.get("ilvl") else ""),
                 f"📍 {m.get('zone') or 'unknown'}  ·  seen {seen(m.get('ts'))}",
                 "🛠 " + (", ".join(f"{p} {r}" for p, r in ps) if ps else "no professions")]
        if m.get("note"):
            lines.append(f"📝 {m['note']}")
        fields.append({"name": name, "value": "\n".join(lines)[:1024], "inline": True})
    if by_prof:
        txt = "\n".join(f"**{p}**: " + ", ".join(f"{n} ({r})" for n, r in sorted(v, key=lambda x: -x[1]))
                        for p, v in sorted(by_prof.items()))
        fields.append({"name": "Who can make what", "value": txt[:1024], "inline": False})
    top_cls = rows[0][1].get("class") if rows else None
    return {"username": "Guild Board", "embeds": [{
        "title": f"{guild} roster",
        "description": f"{len(rows)} members reporting. Get the addon in #addons.",
        "color": CLASS_COLOR.get(top_cls, 0x5865F2),
        "fields": fields[:25],
        "footer": {"text": "Guild Board · updates when someone syncs"},
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}],
        "allowed_mentions": {"parse": []}}

def send(url, payload, msg_id):
    if msg_id:
        req = urllib.request.Request(f"{url}/messages/{msg_id}", method="PATCH")
    else:
        req = urllib.request.Request(f"{url}?wait=true", method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "GuildBoard (github.com/KrisHendo09/guild-board, 1.0)")
    with urllib.request.urlopen(req, json.dumps(payload).encode()) as r:
        return json.load(r)["id"]

if __name__ == "__main__":
    members = json.loads(os.environ.get("ROSTER_JSON") or "{}")
    payload = build(members, os.environ.get("GUILD_NAME") or "Guild")
    if "--dry" in sys.argv:
        print(json.dumps(payload, indent=2)); sys.exit(0)
    url = (os.environ.get("DISCORD_WEBHOOK_URL") or "").strip()
    if not url.startswith("https://"):
        print("DISCORD_WEBHOOK_URL is empty or not a URL. Add it under Settings > Secrets and variables > Actions > Repository secrets."); sys.exit(1)
    msg_id = (os.environ.get("MESSAGE_ID") or "").strip()
    try:
        new_id = send(url, payload, msg_id)
    except urllib.error.HTTPError as e:
        if msg_id and e.code == 404:  # old message deleted, post a fresh one
            new_id = send(url, payload, "")
        else:
            print(f"Discord error {e.code}: {e.read()[:300].decode(errors='replace')}"); sys.exit(1)
    print(f"message_id={new_id}")
