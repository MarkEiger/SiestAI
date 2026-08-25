# SiestAI

Let the machine take its siesta — but only when the AI is done. macOS today; Linux port is straightforward (see the bottom of this file).

Keeps a Mac awake (lid closed included) **only while a Claude Code / Codex prompt is running**, across any number of concurrent sessions.

```
hook (UserPromptSubmit) ─┐                       ┌─ kqueue NOTE_EXIT on each agent PID
hook (Stop/SessionEnd)  ─┼─ unix socket ─▶ sleeplockd ─┼─ sudo pmset -a disablesleep 0|1  (only on empty⇄non-empty)
menu-bar app / CLI      ─┘                       └─ state.json (survives daemon restart, not reboot)
```

- **Per prompt, not per session:** `UserPromptSubmit` registers the turn; `Stop`, `StopFailure` (API error), `SessionEnd` release it. `PreToolUse`/`PostToolUse` are heartbeats.
- **Waiting on you doesn't keep the lid open:** `PermissionRequest` (permission dialog or `AskUserQuestion`) marks the session *waiting* — sleep is allowed, the session stays listed — and the next `PostToolUse`/`PermissionDenied` marks it active again.
- **The tool's own transcript is the tie-breaker:** on registration the daemon notes the transcript file (`transcript_path` from the hook), watches it with kqueue, and only looks at records written *after* that point. Claude Code writes `[Request interrupted by user…]` on Esc, `isApiErrorMessage` on API errors, `stop_reason: end_turn` when done; Codex writes `turn_aborted`, `task_complete{error}`, `task_complete`. Any of these releases the turn within a second — no timeouts, no heuristics.
- **Bound to the process:** kqueue `NOTE_EXIT` on the agent PID releases everything that session held if it dies without a hook.
- **Boot safety:** a root LaunchDaemon runs `pmset disablesleep 0` on every boot; the user daemon also resets on start and discards state from a previous boot.
- **Jump to a session:** clicking a row in the menu brings that session's terminal window to the front (`sleeplock focus <session>`): kitty via its remote-control socket, Terminal.app / iTerm2 via AppleScript, tmux panes resolved to their client. Hold ⌥ on the row to release it instead. kitty needs `allow_remote_control socket-only` + `listen_on unix:/tmp/kitty-{kitty_pid}` in `kitty.conf` (the installer doesn't touch kitty.conf; add those two lines and restart kitty).
- **Query:** menu-bar item `☕ 2 💤` / `☾ 0 💤` / `⚠︎ 💤` (SwiftBar plugin; ▶ active, ⏸ waiting rows; click a row to release). CLI: `sleeplock status`, `sleeplock inspect <session_id>` (classifies any session from its transcript, registered or not), `sleeplock gui`.

## Edge cases

| turn ends by… | Claude Code | Codex |
|---|---|---|
| normal completion | `Stop` hook, or transcript `end_turn` | `Stop` hook, or transcript `task_complete` |
| API error (429, budget, network) | `StopFailure` hook, or transcript `isApiErrorMessage` | transcript `task_complete{error}` (no hook fires) |
| **user interrupt (Esc)** | transcript `[Request interrupted by user…]` | transcript `turn_aborted` |
| permission / question dialog | `PermissionRequest` → waiting (sleep allowed); `PostToolUse` → active | `PermissionRequest` (documented, unverified) |
| session exit | `SessionEnd` hook + kernel | `SessionEnd` hook + kernel |
| crash / `kill -9` / terminal closed | kernel (`NOTE_EXIT`) | kernel |
| daemon restart mid-turn | state restored, PID + transcript re-subscribed | same |
| reboot | root LaunchDaemon + boot-stamped state | same |
| hooks not yet trusted | n/a | nothing is registered — trust them once in the TUI (`Trust all and continue`) |

Everything above was exercised against the real CLIs (fake API, fake `pmset`) on 2026-08-25; see `git log` for the runs.

## Install / uninstall
```sh
./install.sh            # --no-codex  --no-gui  --native-gui  --dry-run
./uninstall.sh
```
Install writes: `~/.local/bin/{sleeplock,sleeplockd}`, the SwiftBar plugin (or `~/.local/bin/SleepLockMenu`), `/etc/sudoers.d/sleeplock`, `/Library/LaunchDaemons/local.sleeplock.boot.plist`, `~/Library/LaunchAgents/local.sleeplock{d,.menu}.plist`, hook entries in `~/.claude/settings.json` and `~/.codex/hooks.json` (+ `features.hooks = true` in `~/.codex/config.toml`). Existing settings are backed up as `*.bak-<timestamp>`.

## Files
| path | role |
|---|---|
| `bin/sleeplockd` | daemon: socket + kqueue (PIDs, transcript files) + transcript classifier (`sleeplockd classify <file>` works offline) |
| `bin/sleeplock` | hook client / CLI |
| `bin/merge-hooks.py` | adds/removes our hook entries in a settings file |
| `swiftbar/sleeplock.2s.py` | SwiftBar plugin (preferred GUI) |
| `gui/SleepLockMenu.swift` | native menu-bar app (fallback GUI) |
| `launchd/*.plist` | templates (`__HOME__`, `__PY__` filled by install) |
| `hooks/*.json` | hook definitions per tool |

Runtime files: `~/.cache/sleeplock/{sock,state.json,sleeplockd.log}`.

## Linux?
Not yet. The port is mostly deletions: `systemd-inhibit --what=sleep:handle-lid-switch` (an inhibitor lock that dies with its process) replaces `pmset` + sudoers + the boot LaunchDaemon; `pidfd_open` + `epoll` replaces `kqueue`; a systemd user unit replaces launchd; the SwiftBar plugin already speaks the xbar format that GNOME's Argos extension reads.
