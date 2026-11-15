"""Turn a Guild Board SavedVariables file into JSON for the Discord roster post.

Usage: python roster_json.py "path/to/WTF/Account/NAME/SavedVariables/GuildBoard.lua" > roster.json
No dependencies. Only reads GuildBoardDB.members. DPS is dropped on purpose.
"""
import json, re, sys

KEEP = ("class", "level", "zone", "profs", "note", "ts", "spec", "ilvl")

def parse_members(text):
    start = text.find('["members"]')
    if start < 0:
        return {}
    i = text.index("{", start)
    depth, j = 0, i
    while True:
        c = text[j]
        if c == "{": depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0: break
        elif c == '"':
            j += 1
            while text[j] != '"':
                j += 2 if text[j] == "\\" else 1
        j += 1
    body = text[i + 1:j]
    members = {}
    for m in re.finditer(r'\["((?:[^"\\]|\\.)+)"\]\s*=\s*\{(.*?)\n\s*\},?', body, re.S):
        rec = {}
        for k, v in re.findall(r'\["(\w+)"\]\s*=\s*("(?:[^"\\]|\\.)*"|-?[\d.]+|true|false)', m.group(2)):
            if k not in KEEP: continue
            rec[k] = json.loads(v) if v.startswith('"') else (float(v) if "." in v else int(v)) if v not in ("true", "false") else v == "true"
        members[m.group(1)] = rec
    return members

if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
        print(json.dumps(parse_members(f.read())))
