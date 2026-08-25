#!/usr/bin/python3
# <xbar.title>sleeplock</xbar.title>
# <xbar.version>v1.0</xbar.version>
# <xbar.desc>Shows whether sleep is being held off by running Claude Code / Codex prompts.</xbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
#
# Menu bar:  ☕ 2 💤   sleep blocked by 2 running prompts   (hover for who/where/how long)
#            ☾ 0 💤   sleep allowed
#            ⚠︎ 💤     daemon not running
# Also invoked by its own menu items:  sleeplock.2s.py release <session> | release-all
import json, os, socket, sys, time

BASE = os.environ.get("SLEEPLOCK_DIR", os.path.expanduser("~/.cache/sleeplock"))
SOCK = os.path.join(BASE, "sock")
LOG = os.path.join(BASE, "sleeplockd.log")
ME = os.path.abspath(__file__)
ICON_HELD, ICON_FREE, ICON_DOWN = "☕", "☾", "⚠︎"      # tweak the look here
ZZZ = "💤"


def query(req):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(1.5); s.connect(SOCK); s.sendall(json.dumps(req).encode() + b"\n")
        return json.loads(s.makefile().readline())


def esc(s):  # keep SwiftBar's "|" parameter separator and newlines out of user-controlled text
    return str(s).replace("|", "¦").replace("\n", " ")


def dur(secs):
    m = int(secs // 60)
    return f"{m // 60}h{m % 60:02d}m" if m >= 60 else f"{m}m"


# ---- actions from menu clicks ----------------------------------------------------------
if len(sys.argv) > 1:
    cmd = sys.argv[1]
    if cmd == "release" and len(sys.argv) > 2:
        query({"cmd": "release", "session": sys.argv[2]})
    elif cmd == "release-all":
        query({"cmd": "release-all"})
    sys.exit(0)

# ---- render ----------------------------------------------------------------------------
try:
    st = query({"cmd": "status"})
except (OSError, ValueError):
    print(f"{ICON_DOWN} {ZZZ} | tooltip=sleeplockd is not running — sleep behaves normally")
    print("---")
    print("sleeplockd not reachable | color=red")
    print(f"Open log | bash=/usr/bin/open param1={LOG} terminal=false")
    sys.exit(0)

home = os.path.expanduser("~")
now = st.get("now", time.time())
holders = sorted(st["holders"].items(), key=lambda kv: kv[1]["since"])
rows = [(h["tool"], (h["cwd"] or "?").replace(home, "~"), dur(now - h["since"]), h["pid"], sid, h.get("alive", True))
        for sid, h in holders]
n = len(rows)
blocked = st.get("sleep_disabled") == 1

if blocked:
    detail = "; ".join(f"{t} {c} ({d})" for t, c, d, *_ in rows)
    tip = f"Sleep blocked by {n} running prompt{'s' if n != 1 else ''}: {detail}"
    print(f"{ICON_HELD} {n} {ZZZ} | tooltip={esc(tip)}")
else:
    print(f"{ICON_FREE} {n} {ZZZ} | tooltip=Sleep allowed — no prompts running")

print("---")
print(("Sleep blocked — " if blocked else "Sleep allowed — ") + f"{n} running prompt{'s' if n != 1 else ''} | size=12")
if rows:
    print("---")
    for tool, cwd, d, pid, sid, alive in rows:
        label = f"{tool:<6} {cwd}  ·  {d}  ·  pid {pid}" + ("" if alive else "  (dead)")
        print(f"{esc(label)} | font=Menlo size=12 tooltip=session {esc(sid)} — click to release this one "
              f"bash={sys.executable} param1={ME} param2=release param3={esc(sid)} terminal=false refresh=true")
print("---")
print(f"Release all (allow sleep now) | bash={sys.executable} param1={ME} param2=release-all terminal=false refresh=true")
print(f"Open log | bash=/usr/bin/open param1={LOG} terminal=false")
