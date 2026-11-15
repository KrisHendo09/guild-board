"""Reads Guild Board's SavedVariables (GuildBoard.lua from Kris's WTF folder) and writes data/addon_users.json:
who in the guild has the addon and which version. Run by Kris's hourly WoW dashboard task, which commits the result.
Usage: python3 export_addon_users.py <path to GuildBoard.lua> [out.json]"""
import json, os, re, sys, time

def parse_lua(src):
    i = 0
    def ws():
        nonlocal i
        while i < len(src):
            if src[i] in ' \t\r\n,;': i += 1
            elif src.startswith('--', i):
                j = src.find('\n', i); i = len(src) if j < 0 else j
            else: break
    def string():
        nonlocal i
        q = src[i]; i += 1; out = []
        while src[i] != q:
            if src[i] == '\\':
                i += 1; c = src[i]
                out.append({'n': '\n', 't': '\t', 'r': '\r'}.get(c, c)); i += 1
            else: out.append(src[i]); i += 1
        i += 1; return ''.join(out)
    def value():
        nonlocal i
        ws(); c = src[i]
        if c == '{': return table()
        if c in '"\'': return string()
        m = re.compile(r'-?\d+(\.\d+)?([eE][-+]?\d+)?').match(src, i)
        if m: i = m.end(); return float(m.group()) if any(x in m.group() for x in '.eE') else int(m.group())
        for w, v in (('true', True), ('false', False), ('nil', None)):
            if src.startswith(w, i): i += len(w); return v
        raise ValueError(f'bad value at {i}')
    def table():
        nonlocal i
        i += 1; d = {}; n = 1
        while True:
            ws()
            if src[i] == '}': i += 1; return d
            if src[i] == '[':
                i += 1; k = value(); ws(); i += 1; ws(); i += 1      # ] =
                d[k] = value()
            else:
                d[n] = value(); n += 1
    m = re.search(r'GuildBoardDB\s*=', src)
    if not m: return {}
    i = m.end(); return value()

def main():
    src = open(sys.argv[1], encoding='utf-8', errors='replace').read()
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data', 'addon_users.json')
    db = parse_lua(src) or {}
    now = int(time.time()); users = {}
    for name, m in (db.get('members') or {}).items():
        if not isinstance(m, dict) or '-' in name: continue        # "Name-Realm" keys are stale self copies
        if now - int(m.get('ts') or 0) > 30 * 86400: continue
        users[name] = {'seen': int(m.get('ts') or 0), 'level': m.get('level'), 'class': m.get('class'), 'version': None}
    for name, v in (db.get('versions') or {}).items():
        if not isinstance(v, dict): continue
        n = name.split('-')[0] if name not in users else name
        if n in users: users[n]['version'] = v.get('v')
        elif now - int(v.get('at') or 0) <= 30 * 86400: users[n] = {'seen': int(v.get('at') or 0), 'level': None, 'class': None, 'version': v.get('v')}
    data = {'note': 'Who has the Guild Board addon, as seen by the exporter\'s copy of the addon in the last 30 days.',
            'users': dict(sorted(users.items()))}
    old = None
    try: old = json.load(open(out))
    except Exception: pass
    if old and old.get('users') == data['users']:
        print('UNCHANGED'); return
    data['updated'] = now
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump(data, open(out, 'w'), indent=1, sort_keys=True); print('WROTE', len(users), 'users')

if __name__ == '__main__':
    main()
