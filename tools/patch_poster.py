"""Draws a patch notes board on the guild board art. Usage: python3 tools/patch_poster.py images/announce/1.4.0.poster.json"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont
HERE = os.path.dirname(os.path.abspath(__file__)); R = os.path.join(HERE, 'art') + '/'
spec = json.load(open(sys.argv[1])); out = os.path.join(HERE, '..', 'images', 'announce', spec['out'])
W, H = 1200, 800
im = Image.open(R + 'board_bg.png').convert('RGBA').resize((W, H), Image.LANCZOS)
F = lambda s, w='Regular': ImageFont.truetype(R + f'fonts/Poppins-{w}.ttf', s)
GOLD = '#E8B964'; TXT = '#F1E9DA'; MUTE = '#B9AD98'
def T(d, xy, s, f, fill, a='lm'):
    d.text((xy[0] + 1, xy[1] + 2), s, font=f, fill=(0, 0, 0, 220), anchor=a); d.text(xy, s, font=f, fill=fill, anchor=a)
def card(im, box, accent):
    ov = Image.new('RGBA', im.size, (0, 0, 0, 0)); o = ImageDraw.Draw(ov)
    o.rounded_rectangle(box, 10, fill=(12, 9, 7, 210), outline=(232, 185, 100, 110))
    o.rounded_rectangle([box[0], box[1], box[0] + 6, box[3]], 3, fill=accent)
    return Image.alpha_composite(im, ov)
def wrap(d, s, f, w):
    out, cur = [], ''
    for word in s.split():
        if cur and d.textlength(cur + ' ' + word, font=f) > w: out.append(cur); cur = word
        else: cur = (cur + ' ' + word).strip()
    return out + [cur]
d = ImageDraw.Draw(im)
T(d, (W // 2, 96), spec['title'], F(40, 'Bold'), GOLD, 'mm')
T(d, (W // 2, 140), spec['sub'], F(15, 'Medium'), MUTE, 'mm')
X0, X1, Y0, Y1 = 58, 1142, 210, 700
rows = spec['rows']; gap = 12; rh = (Y1 - Y0 - gap * (len(rows) - 1)) / len(rows)
for ri, row in enumerate(rows):
    y = int(Y0 + ri * (rh + gap))
    label, color, items = row['label'], tuple(row['color']), row['items']
    T(d, (X0, y + 2), '', F(10), MUTE)
    n = len(items); cw = (X1 - X0 - gap * (n - 1)) / n
    for i, (t, s) in enumerate(items):
        cx = int(X0 + i * (cw + gap)); cx2 = int(cx + cw)
        im = card(im, [cx, y, cx2, int(y + rh)], color + (255,)); d = ImageDraw.Draw(im)
        tw = d.textlength(label, font=F(11, 'Bold')) + 16
        d.rounded_rectangle([cx + 20, y + 16, cx + 20 + tw, y + 36], 6, fill=color + (255,))
        d.text((cx + 20 + tw / 2, y + 26), label, font=F(11, 'Bold'), fill='#14100c', anchor='mm')
        T(d, (cx + 20, y + 58), t, F(19, 'Bold'), TXT)
        for j, l in enumerate(wrap(d, s, F(14), cw - 40)[:4]):
            T(d, (cx + 20, y + 88 + j * 22), l, F(14), MUTE)
T(d, (W // 2, 726), spec['footer'], F(14, 'Medium'), GOLD, 'mm')
im.convert('RGB').save(out, optimize=True); print(out)
