#!/usr/bin/env python3
"""Smoke test for the addons in this repo. No game needed.
  pip install lupa luaparser
  python3 tools/test/smoke.py            -> prints a JSON report
  python3 tools/test/smoke.py --save a.json   then, after a change:   python3 tools/test/smoke.py --against a.json
1. Every .lua must parse (luaparser).  A parse error always fails.
2. Each addon is loaded in toc order inside Lua 5.1 (lupa) with a fake WoW API where every unknown global is a
   do-nothing stub, then every registered event handler is fired once.  The fake API is crude, so some errors are
   only the mock's fault.  That is why you compare: --against fails only on errors that were NOT there before."""
import glob, json, os, re, sys
from lupa.lua51 import LuaRuntime
from luaparser import ast

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
MOCK = r'''
local stub = {}
local mt = {}
mt.__index = function() return stub end
mt.__call = function() return stub end
mt.__concat = function(a, b) return (type(a) == "string" and a or "") .. (type(b) == "string" and b or "") end
mt.__add = function() return 0 end  mt.__sub = function() return 0 end  mt.__mul = function() return 0 end
mt.__div = function() return 0 end  mt.__mod = function() return 0 end  mt.__unm = function() return 0 end
mt.__lt = function() return false end  mt.__le = function() return false end
mt.__newindex = function() end
mt.__tostring = function() return "" end
setmetatable(stub, mt)
_HANDLERS, _ERR = {}, {}
local function frame()
  local f = { _scripts = {} }
  return setmetatable(f, { __index = function(t, k)
    if k == "SetScript" or k == "HookScript" then return function(self, n, fn) self._scripts[n] = fn; _HANDLERS[#_HANDLERS + 1] = { self, n, fn } end end
    if k == "GetScript" then return function(self, n) return self._scripts[n] end end
    if k == "CreateTexture" or k == "CreateFontString" or k == "CreateAnimationGroup" or k == "CreateAnimation" then return function() return frame() end end
    if k == "IsShown" or k == "IsVisible" then return function() return false end end
    if k == "GetWidth" or k == "GetHeight" or k == "GetStringWidth" or k == "GetNumPoints" then return function() return 100 end end
    if k == "GetText" then return function() return "" end end
    if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 0 end end
    return function() return nil end end })
end
function CreateFrame(kind, name) local f = frame() if type(name) == "string" then _G[name] = f end return f end
UIParent, GameTooltip, Minimap, WorldFrame = frame(), frame(), frame(), frame()
UISpecialFrames, StaticPopupDialogs, SlashCmdList = {}, {}, {}
tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
format, strsub, strlen, strlower, strupper, strfind, strmatch, gsub, strrep = string.format, string.sub, string.len, string.lower, string.upper, string.find, string.match, string.gsub, string.rep
floor, ceil, min, max, abs = math.floor, math.ceil, math.min, math.max, math.abs
function strsplit(sep, s) local o = {} for p in ((s or "") .. sep):gmatch("(.-)%" .. sep) do o[#o + 1] = p end return unpack(o) end
function strtrim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
function time() return 1795000000 end  function GetTime() return 1000 end  function date() return "2026-11-20" end
function UnitName() return "Tester" end  function UnitLevel() return 30 end  function UnitClass() return "Shaman", "SHAMAN" end
function UnitExists() return false end  function IsInGuild() return true end  function IsInGroup() return false end
function IsInInstance() return false, "none" end  function GetNumGroupMembers() return 0 end  function GetNumGuildMembers() return 0 end
function GetRealmName() return "Realm" end  function GetRealZoneText() return "Orgrimmar" end  function GetMoney() return 0 end
function InCombatLockdown() return false end  function hooksecurefunc() end  function issecurevariable() return true end
function geterrorhandler() return function() end end  function seterrorhandler() end
function GetBuildInfo() return "1.60.1", "1", "Nov 1 2026", 16001 end
C_Timer = { After = function(_, fn) end, NewTicker = function() return { Cancel = function() end } end, NewTimer = function() return { Cancel = function() end } end }
C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end, SendAddonMessage = function() return true end }
setmetatable(_G, { __index = function() return stub end })
'''


def toc_files(toc):
    d = os.path.dirname(toc)
    return [os.path.join(d, ln.strip().replace('\\', '/')) for ln in open(toc, encoding='utf-8', errors='replace').read().splitlines()
            if ln.strip() and not ln.startswith('#') and ln.strip().lower().endswith('.lua')]


def run():
    rep = {'parse': [], 'missing': [], 'load': [], 'events': []}
    for toc in sorted(glob.glob(os.path.join(ROOT, '*', '*.toc'))):
        addon = os.path.basename(os.path.dirname(toc))
        for f in sorted(glob.glob(os.path.join(os.path.dirname(toc), '*.lua'))):
            try:
                ast.parse(open(f, encoding='utf-8', errors='replace').read())
            except Exception as e:
                rep['parse'].append(f"{os.path.relpath(f, ROOT)}: {str(e)[:200]}")
        L = LuaRuntime(unpack_returned_tuples=True); L.execute(MOCK)
        L.execute('_NS = {}')
        for f in toc_files(toc):
            rel = os.path.relpath(f, ROOT)
            if not os.path.exists(f):
                rep['missing'].append(rel); continue
            L.globals()._SRC = open(f, encoding='utf-8', errors='replace').read().replace('\r\n', '\n')
            L.globals()._NAME = rel; L.globals()._ADDON = addon
            r = L.eval('(function() local f, e = loadstring(_SRC, "@" .. _NAME) if not f then return "syntax: " .. tostring(e) end '
                       'local ok, err = pcall(f, _ADDON, _NS) if not ok then return tostring(err) end return "" end)()')
            if r:
                rep['load'].append(f"{rel}: {re.sub(r'^.*?@', '', str(r))[:200]}")
        L.execute('''
          local EV = {"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GUILD_ROSTER_UPDATE", "GROUP_ROSTER_UPDATE", "BAG_UPDATE", "QUEST_LOG_UPDATE",
                      "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "CHAT_MSG_ADDON", "MERCHANT_SHOW", "MAIL_SHOW", "BANKFRAME_OPENED", "PLAYER_REGEN_ENABLED"}
          local n = #_HANDLERS
          for i = 1, n do local h = _HANDLERS[i]
            if h[2] == "OnEvent" then for _, e in ipairs(EV) do local ok, err = pcall(h[3], h[1], e, _ADDON, "x", "GUILD", "Tester") if not ok then _ERR[tostring(err)] = true end end
            elseif h[2] == "OnUpdate" then local ok, err = pcall(h[3], h[1], 5) if not ok then _ERR[tostring(err)] = true end
            elseif h[2] == "OnShow" or h[2] == "OnClick" then local ok, err = pcall(h[3], h[1], "LeftButton") if not ok then _ERR[tostring(err)] = true end end end
          for name, fn in pairs(SlashCmdList) do if type(fn) == "function" then local ok, err = pcall(fn, "") if not ok then _ERR[tostring(err)] = true end end end''')
        for k in L.globals()._ERR.keys():
            rep['events'].append(re.sub(r'^.*?@', '', str(k))[:200])
    for k in rep:
        rep[k] = sorted(set(rep[k]))
    return rep


def key(s):   # ignore line numbers so a fix that shifts lines is not read as a new error
    return re.sub(r':\d+:', ':N:', s)


if __name__ == '__main__':
    rep = run(); a = sys.argv[1:]
    if a[:1] == ['--save']:
        json.dump(rep, open(a[1], 'w'), indent=1); print('saved', a[1], {k: len(v) for k, v in rep.items()}); sys.exit(1 if rep['parse'] else 0)
    if a[:1] == ['--against']:
        old = json.load(open(a[1])); bad = list(rep['parse']) + list(rep['missing'])
        for k in ('load', 'events'):
            seen = {key(x) for x in old.get(k, [])}
            bad += [f'NEW {k} error: {x}' for x in rep[k] if key(x) not in seen]
        gone = [x for k in ('load', 'events') for x in old.get(k, []) if key(x) not in {key(y) for y in rep[k]}]
        print(json.dumps({'new_or_fatal': bad, 'fixed': gone}, indent=1)); sys.exit(1 if bad else 0)
    print(json.dumps(rep, indent=1)); sys.exit(1 if rep['parse'] or rep['missing'] else 0)
