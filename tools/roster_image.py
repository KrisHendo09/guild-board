"""Draw the Guild Board roster as a PNG (dark card, class-colored names). Needs Pillow.
No DPS by design."""
import time
from PIL import Image, ImageDraw, ImageFont

CLASS_RGB = {"Warrior": (198, 155, 109), "Paladin": (244, 140, 186), "Hunter": (170, 211, 114),
    "Rogue": (255, 244, 104), "Priest": (240, 240, 240), "Shaman": (40, 140, 240), "Mage": (63, 199, 235),
    "Warlock": (135, 136, 238), "Druid": (255, 124, 10), "Death Knight": (196, 30, 58), "Monk": (0, 255, 152),
    "Demon Hunter": (163, 48, 201), "Evoker": (51, 147, 127)}
BG, CARD, ROW_A, ROW_B = (17, 18, 20), (24, 25, 28), (30, 32, 36), (26, 27, 31)
WHITE, GRAY, DIM, GOLD = (235, 236, 238), (150, 153, 160), (110, 113, 120), (230, 180, 80)

def font(size, bold=False):
    for p in (f"/usr/share/fonts/truetype/dejavu/DejaVuSans{'-Bold' if bold else ''}.ttf",):
        try: return ImageFont.truetype(p, size)
        except OSError: pass
    return ImageFont.load_default(size)

def seen(ts):
    if not ts: return "-"
    h = int((time.time() - ts) / 3600)
    return "now" if h < 1 else f"{h}h ago" if h < 48 else f"{h // 24}d ago"

def fit(d, text, f, w):
    if d.textlength(text, font=f) <= w: return text
    while text and d.textlength(text + "...", font=f) > w: text = text[:-1]
    return text + "..."

def render(members, guild, path):
    rows = sorted(members.items(), key=lambda kv: (-(kv[1].get("level") or 0), kv[0]))
    W, RH, top = 1000, 40, 120
    H = top + RH * max(len(rows), 1) + 30
    img = Image.new("RGB", (W, H), BG); d = ImageDraw.Draw(img)
    d.rounded_rectangle((10, 10, W - 10, H - 10), 14, fill=CARD)
    fT, fS, fH, fN, fR, fB = font(30, True), font(15), font(12, True), font(17, True), font(15), font(15, True)
    d.text((36, 26), f"{guild}: roster", font=fT, fill=WHITE)
    d.text((36, 66), f"{len(rows)} members, highest level first", font=fS, fill=GRAY)
    try:
        from zoneinfo import ZoneInfo; from datetime import datetime
        up = "Updated " + datetime.now(ZoneInfo("America/Chicago")).strftime("%b %d, %I:%M %p CT").replace(" 0", " ")
    except Exception:
        up = "Updated " + time.strftime("%b %d, %H:%M UTC", time.gmtime())
    d.text((W - 36 - d.textlength(up, font=fS), 66), up, font=fS, fill=GRAY)
    d.line((26, 92, W - 26, 92), fill=GOLD, width=3)
    X = {"name": 46, "lvl": 340, "class": 390, "ilvl": 540, "prof": 590, "seen": W - 36}
    hy = 100
    for k, lab in (("name", "NAME"), ("lvl", "LVL"), ("class", "CLASS"), ("ilvl", "ILVL"), ("prof", "PROFESSIONS")):
        d.text((X[k], hy), lab, font=fH, fill=GRAY)
    d.text((X["seen"] - d.textlength("LAST SEEN", font=fH), hy), "LAST SEEN", font=fH, fill=GRAY)
    for i, (key, m) in enumerate(rows):
        y = top + i * RH
        cls = m.get("class") or "?"; col = CLASS_RGB.get(cls, WHITE)
        d.rectangle((26, y, W - 26, y + RH - 4), fill=ROW_A if i % 2 == 0 else ROW_B)
        d.rectangle((26, y, 31, y + RH - 4), fill=col)
        cy = y + (RH - 4) // 2
        name = key.split("-")[0]
        d.text((X["name"], cy), fit(d, name, fN, 285), font=fN, fill=col, anchor="lm")
        d.text((X["lvl"] + 20, cy), str(m.get("level", 0)), font=fB, fill=WHITE, anchor="rm")
        spec = m.get("spec") or ""
        what = f"{spec} {cls}" if spec and spec != cls else cls
        d.text((X["class"], cy), fit(d, what, fR, 140), font=fR, fill=GRAY, anchor="lm")
        il = m.get("ilvl") or 0
        d.text((X["ilvl"] + 22, cy), str(il) if il else "-", font=fR, fill=WHITE, anchor="rm")
        x = X["prof"]
        for p in (m.get("profs") or "").split(","):
            parts = p.split(":")
            if len(parts) != 3 or not parts[0]: continue
            d.text((x, cy), parts[0], font=fR, fill=WHITE, anchor="lm"); x += d.textlength(parts[0] + " ", font=fR)
            d.text((x, cy), parts[1], font=fB, fill=GOLD, anchor="lm"); x += d.textlength(parts[1] + "   ", font=fB)
        s = seen(m.get("ts"))
        d.text((X["seen"], cy), s, font=fR, fill=GRAY, anchor="rm")
    img.save(path, format="PNG")
