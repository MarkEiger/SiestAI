#!/usr/bin/env python3
"""codex-enable-hooks.py <config.toml> — set `hooks = true` under [features], creating the section if needed."""
import os, re, sys

p = os.path.expanduser(sys.argv[1])
lines = open(p).read().splitlines() if os.path.exists(p) else []
start = next((i for i, l in enumerate(lines) if l.strip() == "[features]"), None)
if start is None:
    if lines and lines[-1].strip():
        lines.append("")
    lines += ["[features]", "hooks = true"]
else:
    end = next((i for i in range(start + 1, len(lines)) if lines[i].lstrip().startswith("[")), len(lines))
    for i in range(start + 1, end):
        if re.match(r"\s*hooks\s*=", lines[i]):
            lines[i] = "hooks = true"
            break
    else:
        lines.insert(start + 1, "hooks = true")
open(p, "w").write("\n".join(lines) + "\n")
print(f"features.hooks = true in {p}")
