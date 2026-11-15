"""Post a release announcement to Discord as rich embeds. Run only by the Announce workflow, which Kris starts by hand.
Images load from the public repo, so nothing is uploaded. Never prints the webhook."""
import json, os, sys, urllib.request, urllib.error
RAW = 'https://raw.githubusercontent.com/KrisHendo09/guild-board/main/images/'
REL = 'https://github.com/KrisHendo09/guild-board/releases/latest'
RED = 0xB3261E; GOLD = 0xE8B964
spec = json.load(open(sys.argv[1], encoding='utf-8'))
hook = os.environ.get('ANNOUNCE_WEBHOOK', '')
if not hook.startswith('https://discord.com/api/webhooks/'): raise SystemExit('BAD_WEBHOOK')
embeds = []
for i, e in enumerate(spec['embeds']):
    em = {'color': RED if i == 0 else GOLD}
    for k in ('title', 'description', 'fields'):
        if k in e: em[k] = e[k]
    if e.get('link'): em['url'] = REL
    if e.get('image'): em['image'] = {'url': RAW + e['image']}
    if e.get('thumb'): em['thumbnail'] = {'url': RAW + e['thumb']}
    if i == 0: em['author'] = {'name': 'Guild Board  ·  Push To Prod', 'icon_url': RAW + 'guild-board-logo.png', 'url': REL}
    if e.get('gallery'):          # same url on following image-only embeds makes Discord show one image grid
        em['url'] = e['gallery']; em['image'] = {'url': RAW + e['images'][0]}
        embeds.append(em)
        for img in e['images'][1:]: embeds.append({'url': e['gallery'], 'image': {'url': RAW + img}})
        continue
    embeds.append(em)
embeds[-1]['footer'] = {'text': spec.get('footer', ''), 'icon_url': RAW + 'guild-board-logo.png'}
from datetime import datetime, timezone
embeds[-1]['timestamp'] = datetime.now(timezone.utc).isoformat()
ping = os.environ.get('PING') == 'everyone'
body = {'username': spec.get('from', 'Guild Board'), 'content': '@everyone' if ping else '',
        'embeds': embeds, 'allowed_mentions': {'parse': ['everyone'] if ping else []}}
if spec.get('avatar'): body['avatar_url'] = RAW + spec['avatar']      # no avatar: uses the picture set on the webhook in Discord
req = urllib.request.Request(hook + '?wait=true', json.dumps(body).encode(), {'Content-Type': 'application/json', 'User-Agent': 'GuildBoard/3.0'})
try:
    print('POSTED', json.load(urllib.request.urlopen(req)).get('id'))
except urllib.error.HTTPError as e:
    raise SystemExit(f'DISCORD_ERROR {e.code} {e.read()[:300]!r}')
