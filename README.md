# SiestAI

Let the machine take its siesta — but only when the AI is done. macOS today; Linux port is straightforward (see the bottom of this file).

Keeps a Mac awake (lid closed included) **only while a Claude Code / Codex prompt is running**, across any number of concurrent sessions.

```
hook (UserPromptSubmit) ─┐                       ┌─ kqueue NOTE_EXIT on each agent PID
hook (Stop/SessionEnd)  ─┼─ unix socket ─▶ sleeplockd ─┼─ sudo pmset -a disablesleep 0|1  (only on empty⇄non-empty)
menu-bar app / CLI      ─┘                       └─ state.json (survives daemon restart, not reboot)
```

- **Per prompt, not per session:** `UserPromptSubmit` registers the turn, `Stop` (or `SessionEnd` / `idle_prompt`) releases it.
- **Bound to the process:** if the agent dies without firing `Stop`, the kernel tells the daemon and the turn is released.
- **Boot safety:** a root LaunchDaemon runs `pmset disablesleep 0` on every boot; the user daemon also resets on start and discards state from a previous boot.
- **Query:** menu-bar item `☕ 2 💤` (sleep blocked by 2 prompts) / `☾ 0 💤` (sleep allowed) / `⚠︎ 💤` (daemon down). Hover for who/where/how long; click for the list, release one row, or release all. Delivered as a **SwiftBar plugin** (`swiftbar/sleeplock.2s.py`, sits next to your other SwiftBar items) when SwiftBar is installed, otherwise as the native **SleepLockMenu** app. CLI: `sleeplock status [--json]`, `sleeplock gui`.

## Install / uninstall
```sh
./install.sh            # --no-codex  --no-gui  --native-gui  --dry-run
./uninstall.sh
```
Install writes: `~/.local/bin/{sleeplock,sleeplockd}`, the SwiftBar plugin (or `~/.local/bin/SleepLockMenu`), `/etc/sudoers.d/sleeplock`, `/Library/LaunchDaemons/local.sleeplock.boot.plist`, `~/Library/LaunchAgents/local.sleeplock{d,.menu}.plist`, hook entries in `~/.claude/settings.json` and `~/.codex/hooks.json` (+ `features.hooks = true` in `~/.codex/config.toml`). Existing settings are backed up as `*.bak-<timestamp>`.

## Files
| path | role |
|---|---|
| `bin/sleeplockd` | daemon: socket + kqueue event loop |
| `bin/sleeplock` | hook client / CLI |
| `bin/merge-hooks.py` | adds/removes our hook entries in a settings file |
| `swiftbar/sleeplock.2s.py` | SwiftBar plugin (preferred GUI) |
| `gui/SleepLockMenu.swift` | native menu-bar app (fallback GUI) |
| `launchd/*.plist` | templates (`__HOME__`, `__PY__` filled by install) |
| `hooks/*.json` | hook definitions per tool |

## Known gap
A turn interrupted with Esc keeps its lock until that session's next `Stop`, exit, or (Claude Code only) the 60 s `idle_prompt` notification. Codex has no idle event; use the menu bar / `sleeplock release-all` if needed.

Runtime files: `~/.cache/sleeplock/{sock,state.json,sleeplockd.log}`.

## Linux?
Not yet. The port is mostly deletions: `systemd-inhibit --what=sleep:handle-lid-switch` (an inhibitor lock that dies with its process) replaces `pmset` + sudoers + the boot LaunchDaemon; `pidfd_open` + `epoll` replaces `kqueue`; a systemd user unit replaces launchd; the SwiftBar plugin already speaks the xbar format that GNOME's Argos extension reads.
