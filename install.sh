#!/bin/bash
# sleeplock installer — idempotent; re-run after editing anything in this repo.
#   ./install.sh [--no-codex] [--no-gui] [--native-gui] [--user-only] [--dry-run]
#   --user-only: update binaries, daemon, hooks and GUI without touching sudoers / the boot LaunchDaemon (no password)
#   GUI: SwiftBar plugin if SwiftBar is installed (sits next to your other plugins), else a native menu-bar app.
set -euo pipefail
cd "$(dirname "$0")"
PREFIX="$HOME/.local/bin"; AGENTS="$HOME/Library/LaunchAgents"; ME=$(id -un); UID_=$(id -u)
PY=$(command -v python3); CODEX=1; GUI=1; NATIVE=0; DRY=0; USERONLY=0
for a in "$@"; do case $a in --no-codex) CODEX=0;; --no-gui) GUI=0;; --native-gui) NATIVE=1;; --user-only) USERONLY=1;; --dry-run) DRY=1;; *) echo "unknown arg $a"; exit 2;; esac; done
run() { if [ $DRY = 1 ]; then echo "+ $*"; else "$@"; fi; }
say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

say "prerequisites"
"$PY" -c 'import select; select.kqueue' || { echo "python3 without kqueue support: $PY"; exit 1; }
echo "python3: $PY"
SWIFTBAR_DIR=$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)
if [ $GUI = 1 ] && [ $NATIVE = 0 ] && [ -n "$SWIFTBAR_DIR" ] && [ -d "$SWIFTBAR_DIR" ]; then
  MENU=swiftbar; echo "gui: SwiftBar plugin -> $SWIFTBAR_DIR"
elif [ $GUI = 1 ] && command -v swiftc >/dev/null; then
  MENU=native; echo "gui: native menu-bar app"
elif [ $GUI = 1 ]; then
  echo "gui: neither SwiftBar nor swiftc found — skipping (brew install --cask swiftbar, or xcode-select --install)"; MENU=none
else MENU=none; fi

say "binaries -> $PREFIX"
run install -d "$PREFIX" "$HOME/.cache/sleeplock"
run install -m 755 bin/sleeplock bin/sleeplockd "$PREFIX/"
case $MENU in
  swiftbar) run install -m 755 swiftbar/sleeplock.2s.py "$SWIFTBAR_DIR/sleeplock.2s.py" ;;   # SwiftBar picks it up automatically
  native)   run mkdir -p build
            run swiftc -O -o build/SleepLockMenu gui/SleepLockMenu.swift
            run install -m 755 build/SleepLockMenu "$PREFIX/SleepLockMenu" ;;
esac

if [ $USERONLY = 0 ]; then
say "sudoers (asks for your password): pmset disablesleep 0/1 only"
tmp=$(mktemp); sed "s/__USER__/$ME/g" sudoers/sleeplock > "$tmp"
run sudo visudo -cf "$tmp"
run sudo install -o root -g wheel -m 440 "$tmp" /etc/sudoers.d/sleeplock; rm -f "$tmp"

say "boot-time reset (root LaunchDaemon): pmset disablesleep 0 on every boot"
run sudo install -o root -g wheel -m 644 launchd/local.sleeplock.boot.plist /Library/LaunchDaemons/local.sleeplock.boot.plist
run sudo launchctl bootout system/local.sleeplock.boot 2>/dev/null || true
run sudo launchctl bootstrap system /Library/LaunchDaemons/local.sleeplock.boot.plist

say "prove the sudoers rule works without a password (this is what the daemon relies on)"
run sudo -k                                       # drop the cached password so the rule itself is tested
if ! run sudo -n /usr/bin/pmset -a disablesleep 0; then
  echo "FAIL: 'sudo -n pmset' still needs a password — check that /etc/sudoers has '#includedir /etc/sudoers.d' (sudo visudo -c)"; exit 1
fi
echo "ok: passwordless pmset works"
else
  say "user-only update: skipping sudoers and boot LaunchDaemon"
fi

say "user agents: daemon$([ $MENU = native ] && echo ' + native menu bar')"
render() { sed -e "s|__HOME__|$HOME|g" -e "s|__PY__|$PY|g" "launchd/$1" > "$AGENTS/$1"; }
run install -d "$AGENTS"
for label in local.sleeplockd $([ $MENU = native ] && echo local.sleeplock.menu); do
  if [ $DRY = 1 ]; then echo "+ render $label.plist"; else render "$label.plist"; fi
  run launchctl bootout "gui/$UID_/$label" 2>/dev/null || true
  for attempt in 1 2 3 4 5 6; do          # launchd needs a moment after bootout; retry "Bootstrap failed: 5"
    sleep 1
    if run launchctl bootstrap "gui/$UID_" "$AGENTS/$label.plist" 2>/dev/null; then break; fi
    [ $attempt = 6 ] && { echo "could not bootstrap $label"; launchctl bootstrap "gui/$UID_" "$AGENTS/$label.plist"; exit 1; }
  done
done

say "hooks: Claude Code"
run "$PY" bin/merge-hooks.py add "$HOME/.claude/settings.json" hooks/claude.json
if [ $CODEX = 1 ]; then
  say "hooks: Codex"
  run "$PY" bin/merge-hooks.py add "$HOME/.codex/hooks.json" hooks/codex.json
  run "$PY" bin/codex-enable-hooks.py "$HOME/.codex/config.toml"
  echo "NOTE: Codex will NOT run these hooks until you approve them once: start codex, pick 'Trust all and continue'"
  echo "      (or press t in /hooks). Non-interactive 'codex exec' needs that persisted trust or --dangerously-bypass-hook-trust."
  echo "NOTE: enabling Codex hooks also re-enables any plugin hooks (e.g. babysitter); manage those via /hooks in the Codex TUI."
fi

say "verify"
if [ $DRY = 0 ]; then
  for _ in 1 2 3 4 5 6; do [ -S "$HOME/.cache/sleeplock/sock" ] && break; sleep 0.5; done
  "$PREFIX/sleeplock" status || echo "daemon not up yet — check: launchctl print gui/$UID_/local.sleeplockd; tail ~/.cache/sleeplock/sleeplockd.log"
  pmset -g | grep SleepDisabled
fi
echo "done. logs: ~/.cache/sleeplock/sleeplockd.log"
