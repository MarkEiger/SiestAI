#!/usr/bin/env python3
"""merge-hooks.py add|remove <settings.json> <hooks.json>
Adds/removes sleeplock hook entries in a Claude/Codex settings file, leaving other hooks alone."""
import json, os, shutil, sys, time

mode, target, src = sys.argv[1], os.path.expanduser(sys.argv[2]), sys.argv[3]
ours = json.load(open(src))
settings = {}
if os.path.exists(target):
    shutil.copy(target, f"{target}.bak-{time.strftime('%Y%m%d-%H%M%S')}")
    settings = json.load(open(target))
hooks = settings.setdefault("hooks", {})
is_ours = lambda entry: any("sleeplock" in h.get("command", "") for h in entry.get("hooks", []))
for event, entries in ours.items():
    kept = [e for e in hooks.get(event, []) if not is_ours(e)]
    if mode == "add":
        kept += entries
    if kept:
        hooks[event] = kept
    else:
        hooks.pop(event, None)
if not hooks:
    settings.pop("hooks", None)
os.makedirs(os.path.dirname(target), exist_ok=True)
json.dump(settings, open(target, "w"), indent=2); open(target, "a").write("\n")
print(f"{mode}: {target}")
