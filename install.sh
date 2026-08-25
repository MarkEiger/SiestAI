#!/bin/bash
# sleeplock installer — idempotent; re-run after editing anything in this repo.
#   ./install.sh [--no-codex] [--no-gui] [--dry-run]
set -euo pipefail
cd "$(dirname "$0")"
PREFIX="$HOME/.local/bin"; AGENTS="$HOME/Library/LaunchAgents"; ME=$(id -un); UID_=$(id -u)
PY=$(command -v python3); CODEX=1; GUI=1; DRY=0
for a in "$@"; do case $a in --no-codex) CODEX=0;; --no-gui) GUI=0;; --dry-run) DRY=1;; *) echo "unknown arg $a"; exit 2;; esac; done
run() { if [ $DRY = 1 ]; then echo "+ $*"; else "$@"; fi; }
say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

say "prerequisites"
"$PY" -c 'import select; select.kqueue' || { echo "python3 without kqueue support: $PY"; exit 1; }
echo "python3: $PY"
if [ $GUI = 1 ] && ! command -v swiftc >/dev/null; then echo "swiftc not found — skipping menu-bar app (xcode-select --install to get it)"; GUI=0; fi

say "binaries -> $PREFIX"
run install -d "$PREFIX" "$HOME/.cache/sleeplock"
run install -m 755 bin/sleeplock bin/sleeplockd "$PREFIX/"
if [ $GUI = 1 ]; then
  run mkdir -p build
  run swiftc -O -o build/SleepLockMenu gui/SleepLockMenu.swift
  run install -m 755 build/SleepLockMenu "$PREFIX/SleepLockMenu"
fi

say "sudoers (asks for your password): pmset disablesleep 0/1 only"
tmp=$(mktemp); sed "s/__USER__/$ME/g" sudoers/sleeplock > "$tmp"
run sudo visudo -cf "$tmp"
run sudo install -o root -g wheel -m 440 "$tmp" /etc/sudoers.d/sleeplock; rm -f "$tmp"
run sudo -n /usr/bin/pmset -a disablesleep 0     # proves the rule works, and starts from a clean state

say "boot-time reset (root LaunchDaemon): pmset disablesleep 0 on every boot"
run sudo install -o root -g wheel -m 644 launchd/local.sleeplock.boot.plist /Library/LaunchDaemons/local.sleeplock.boot.plist
run sudo launchctl bootout system/local.sleeplock.boot 2>/dev/null || true
run sudo launchctl bootstrap system /Library/LaunchDaemons/local.sleeplock.boot.plist

say "user agents: daemon${GUI:+ + menu bar}"
render() { sed -e "s|__HOME__|$HOME|g" -e "s|__PY__|$PY|g" "launchd/$1" > "$AGENTS/$1"; }
run install -d "$AGENTS"
for label in local.sleeplockd $([ $GUI = 1 ] && echo local.sleeplock.menu); do
  if [ $DRY = 1 ]; then echo "+ render $label.plist"; else render "$label.plist"; fi
  run launchctl bootout "gui/$UID_/$label" 2>/dev/null || true
  run launchctl bootstrap "gui/$UID_" "$AGENTS/$label.plist"
done

say "hooks: Claude Code"
run "$PY" bin/merge-hooks.py add "$HOME/.claude/settings.json" hooks/claude.json
if [ $CODEX = 1 ]; then
  say "hooks: Codex"
  run "$PY" bin/merge-hooks.py add "$HOME/.codex/hooks.json" hooks/codex.json
  run "$PY" bin/codex-enable-hooks.py "$HOME/.codex/config.toml"
  echo "NOTE: enabling Codex hooks also re-enables any plugin hooks (e.g. babysitter); manage those via /hooks in the Codex TUI."
fi

say "verify"
if [ $DRY = 0 ]; then sleep 1; "$PREFIX/sleeplock" status; pmset -g | grep SleepDisabled; fi
echo "done. logs: ~/.cache/sleeplock/sleeplockd.log"
