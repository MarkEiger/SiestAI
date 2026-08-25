# SiestAI

Let the machine take its siesta — but only when the AI is done. macOS today; Linux port is straightforward (see the bottom of this file).

Keeps a Mac awake (lid closed included) **only while a Claude Code / Codex prompt is running**, across any number of concurrent sessions.

```
hook (UserPromptSubmit) ─┐                       ┌─ kqueue NOTE_EXIT on each agent PID
hook (Stop/SessionEnd)  ─┼─ unix socket ─▶ sleeplockd ─┼─ sudo pmset -a disablesleep 0|1  (only on empty⇄non-empty)
menu-bar app / CLI      ─┘                       └─ state.json (survives daemon restart, not reboot)
```

- **Per prompt, not per session:** `UserPromptSubmit` registers the turn; `Stop` (normal end), `StopFailure` (API error — 429, budget, network), `SessionEnd`, or `idle_prompt` release it. While a **permission / question dialog** is waiting on you the hold is released (`PermissionRequest`) and re-taken when work resumes (`PostToolUse`); `PreToolUse`/`PostToolUse` also act as heartbeats that heal a missed acquire.
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

## Known gap: user-interrupted prompts
If you interrupt a running prompt (Esc / Ctrl-C once) **neither tool emits any hook** — not `Stop`, not `StopFailure`, and Claude Code's `idle_prompt` never fires after an interrupt (verified with both CLIs). The hold stays until that session's next hook event (any tool call, prompt, error) or exit. Use the menu bar / `sleeplock release-all` meanwhile. How to close this without heuristics is an open question.

Codex extra: Codex runs `hooks.json` hooks only after you trust them once in the TUI ("Trust all and continue", or `t` in `/hooks`). Its `PermissionRequest` hook is documented but not verified here.

What was verified (fake API under tmux, 2026-08-25): Claude Code fires `StopFailure` on API errors; `PreToolUse → PermissionRequest → Notification(permission_prompt)` while a permission or `AskUserQuestion` dialog is up, then `PostToolUse → Stop` after approval; nothing after Esc. Codex fires `UserPromptSubmit` then nothing on API error or Esc; `SessionEnd` on exit.

Runtime files: `~/.cache/sleeplock/{sock,state.json,sleeplockd.log}`.

## Linux?
Not yet. The port is mostly deletions: `systemd-inhibit --what=sleep:handle-lid-switch` (an inhibitor lock that dies with its process) replaces `pmset` + sudoers + the boot LaunchDaemon; `pidfd_open` + `epoll` replaces `kqueue`; a systemd user unit replaces launchd; the SwiftBar plugin already speaks the xbar format that GNOME's Argos extension reads.
