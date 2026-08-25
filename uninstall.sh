#!/bin/bash
# Removes everything install.sh added. Leaves Codex's [features] hooks flag as-is.
set -uo pipefail
cd "$(dirname "$0")"
PREFIX="$HOME/.local/bin"; AGENTS="$HOME/Library/LaunchAgents"; UID_=$(id -u); PY=$(command -v python3)
"$PREFIX/sleeplock" release-all 2>/dev/null
for label in local.sleeplock.menu local.sleeplockd; do launchctl bootout "gui/$UID_/$label" 2>/dev/null; rm -f "$AGENTS/$label.plist"; done
"$PY" bin/merge-hooks.py remove "$HOME/.claude/settings.json" hooks/claude.json
[ -f "$HOME/.codex/hooks.json" ] && "$PY" bin/merge-hooks.py remove "$HOME/.codex/hooks.json" hooks/codex.json
SWIFTBAR_DIR=$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true); [ -n "$SWIFTBAR_DIR" ] && rm -f "$SWIFTBAR_DIR/sleeplock.2s.py"
rm -f "$PREFIX/sleeplock" "$PREFIX/sleeplockd" "$PREFIX/SleepLockMenu" "$HOME/.cache/sleeplock/sock" "$HOME/.cache/sleeplock/state.json"
echo "root parts (asks for password):"
sudo launchctl bootout system/local.sleeplock.boot 2>/dev/null
sudo rm -f /Library/LaunchDaemons/local.sleeplock.boot.plist /etc/sudoers.d/sleeplock
sudo /usr/bin/pmset -a disablesleep 0
pmset -g | grep SleepDisabled; echo "uninstalled"
