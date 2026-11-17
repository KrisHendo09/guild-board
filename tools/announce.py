"""Post release announcements to Discord as rich embeds. Run only by the Announce workflow, which Kris starts by hand.
Images load from the public repo, so nothing is uploaded. Never prints the webhook.
Forum mode: the webhook lives in the addons-forum channel. A file with "thread_name" opens a new forum post; every
other file is posted as a reply inside the Guild Board post (its id is kept in images/announce/forum.json).
Usage: announce.py file1.json[,file2.json,...]   (paths relative to images/announce/)"""
import json, os, sys, urllib.request, urllib.error
RAW = 'https://raw.githubusercontent.com/KrisHendo09/guild-board/main/images/'
REL = 'https://github.com/KrisHendo09/guild-board/releases/latest'
RED = 0xB3261E; GOLD = 0xE8B964
def post(spec, thread):
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
    for mid in spec.get('replace', []) if os.environ.get('CLEANUP') == 'true' else []:
        try:
            urllib.request.urlopen(urllib.request.Request(f'{hook}/messages/{mid}', method='DELETE', headers={'User-Agent': 'GuildBoard/3.0'})); print('DELETED', mid)
        except urllib.error.HTTPError as e:
            print('DELETE_SKIPPED', mid, e.code)      # 404 = already gone
    url = hook + '?wait=true'
    if spec.get('thread_name'): body['thread_name'] = spec['thread_name']          # opens a new forum post
    elif thread: url += '&thread_id=' + thread                                     # reply inside the forum post
    req = urllib.request.Request(url, json.dumps(body).encode(), {'Content-Type': 'application/json', 'User-Agent': 'GuildBoard/3.0'})
    try:
        r = json.load(urllib.request.urlopen(req))
    except urllib.error.HTTPError as e:
        raise SystemExit(f'DISCORD_ERROR {e.code} {e.read()[:300]!r}')
    print('POSTED', r.get('id'), 'in', r.get('channel_id'))
    return r.get('channel_id') if spec.get('thread_name') else thread

hook = os.environ.get('ANNOUNCE_WEBHOOK', '')
if not hook.startswith('https://discord.com/api/webhooks/'): raise SystemExit('BAD_WEBHOOK')
HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'images', 'announce')
FORUM = os.path.join(HERE, 'forum.json')
try: thread = json.load(open(FORUM)).get('thread_id') or None
except Exception: thread = None
for name in sys.argv[1].split(','):
    name = name.strip()
    path = name if os.path.exists(name) else os.path.join(HERE, name)
    thread = post(json.load(open(path, encoding='utf-8')), thread)
if thread: print('THREAD', thread)
