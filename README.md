# sleeplock

Keeps a Mac awake (lid closed included) **only while a Claude Code / Codex prompt is running**, across any number of concurrent sessions.

```
hook (UserPromptSubmit) ─┐                       ┌─ kqueue NOTE_EXIT on each agent PID
hook (Stop/SessionEnd)  ─┼─ unix socket ─▶ sleeplockd ─┼─ sudo pmset -a disablesleep 0|1  (only on empty⇄non-empty)
menu-bar app / CLI      ─┘                       └─ state.json (survives daemon restart, not reboot)
```

- **Per prompt, not per session:** `UserPromptSubmit` registers the turn, `Stop` (or `SessionEnd` / `idle_prompt`) releases it.
- **Bound to the process:** if the agent dies without firing `Stop`, the kernel tells the daemon and the turn is released.
- **Boot safety:** a root LaunchDaemon runs `pmset disablesleep 0` on every boot; the user daemon also resets on start and discards state from a previous boot.
- **Query:** `sleeplock status` (`--json`), `sleeplock gui` (dialog), or the **SleepLockMenu** menu-bar app (☕ = awake, ☾ = sleep allowed; lists tool / dir / duration per turn; click a row to release it).

## Install / uninstall
```sh
./install.sh            # --no-codex  --no-gui  --dry-run
./uninstall.sh
```
Install writes: `~/.local/bin/{sleeplock,sleeplockd,SleepLockMenu}`, `/etc/sudoers.d/sleeplock`, `/Library/LaunchDaemons/local.sleeplock.boot.plist`, `~/Library/LaunchAgents/local.sleeplock{d,.menu}.plist`, hook entries in `~/.claude/settings.json` and `~/.codex/hooks.json` (+ `features.hooks = true` in `~/.codex/config.toml`). Existing settings are backed up as `*.bak-<timestamp>`.

## Files
| path | role |
|---|---|
| `bin/sleeplockd` | daemon: socket + kqueue event loop |
| `bin/sleeplock` | hook client / CLI |
| `bin/merge-hooks.py` | adds/removes our hook entries in a settings file |
| `gui/SleepLockMenu.swift` | menu-bar app |
| `launchd/*.plist` | templates (`__HOME__`, `__PY__` filled by install) |
| `hooks/*.json` | hook definitions per tool |

## Known gap
A turn interrupted with Esc keeps its lock until that session's next `Stop`, exit, or (Claude Code only) the 60 s `idle_prompt` notification. Codex has no idle event; use the menu bar / `sleeplock release-all` if needed.

Runtime files: `~/.cache/sleeplock/{sock,state.json,sleeplockd.log}`.
