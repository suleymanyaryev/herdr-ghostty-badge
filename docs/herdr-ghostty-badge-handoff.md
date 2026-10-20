# Handoff: Herdr notifications -> Ghostty dock badge (macOS)

> **Status:** implemented as `suleymanyaryev.ghostty-badge`, see the [README](../README.md). These are the
> original research notes, kept for background. Two things differ from this handoff:
> - The plugin writes BEL to the agent pane's pty (Herdr forwards it) instead of the client's tty.
> - The count goes in the window title, because Ghostty's dock badge stays at "(1)".

## Goal
Herdr (agent multiplexer TUI) tracks agent notifications (agent blocked / done), but when Ghostty is
unfocused nothing shows on the Ghostty dock icon. Want Herdr's "needs attention" events to produce a
Ghostty dock badge on macOS.

## Findings so far (researched, NOT tested on the user's machine)

### Ghostty (macOS)
- Default reaction to the terminal bell (BEL, 0x07): bell emoji in the title, one dock bounce, and a
  badge on the dock / app-switcher icon. No audio. (Ghostty 1.2.0 release notes, "Terminal Bell".)
- Controlled by the `bell-features` config option (flags include `title`, `attention`, `audio`,
  `system`, `border`; `no-<flag>` disables). I could not confirm which flag controls the badge, so
  don't set `no-attention` / `no-title` blindly.
- The badge appears to be tied to the bell only. Found no evidence that OSC 9 / OSC 777 desktop
  notifications set a dock badge.

### Herdr
- Config: `~/.config/herdr/config.toml`; reload with `herdr server reload-config`.
- `ui.toast.delivery` = off | herdr | terminal | system. None of these emits BEL.
  - `terminal` asks the outer terminal for a desktop notification.
  - `system` on macOS uses `terminal-notifier`, falling back to `osascript`.
- `ui.toast.delay_seconds`: waits N seconds and notifies only if the pane is still in the same state.
- Herdr suppresses popups for the active tab.
- A proposal to emit a terminal bell on agent notifications (herdrdev/herdr #626) was reported as
  not merged (from an older thread, verify whether it has landed since).
- Plugins: directory with `herdr-plugin.toml`; `[[events]]` hooks (`on = "<event>"`, `command = [argv]`)
  run when Herdr emits that event. Hooks receive `HERDR_BIN_PATH`, `HERDR_SOCKET_PATH`,
  `HERDR_PLUGIN_EVENT`, `HERDR_PLUGIN_EVENT_JSON`, `HERDR_PANE_ID`, etc. `plugin.link` warns on
  unknown event names.
- Socket API event: `pane.agent_status_changed` (agent states: idle, working, blocked, done, unknown).
  Not yet confirmed that it is usable as a manifest `on = ...` hook name.
- Plugins run on the Herdr server, so this only works when Herdr runs locally (not `herdr --remote`
  from the Mac to a remote server).

## Proposed approach
1. Test whether BEL gives the badge: in plain Ghostty run `sleep 5; printf '\a'`, switch to another
   app, look for the dock badge. Repeat inside a Herdr pane. If it works inside a Herdr pane, Herdr
   may already forward pane BEL to the outer terminal.
2. If not, write a Herdr plugin with an event hook on `pane.agent_status_changed` filtered to
   `blocked` and `done`. The hook writes BEL (`printf '\a'`) to the tty of the attached Herdr client
   process (find the client PID's tty, e.g. via `ps -o tty= -p <pid>`, then write to `/dev/<tty>`).
3. Validate with `herdr plugin link <dir>`, check warnings, trigger an agent state change while
   Ghostty is in the background.

## Badge is a dot, not a count
- Ghostty PR #7118 (dock badge for bell events) describes a Slack-style indicator; a reviewer
  suggested a zero-width-space label, which implies a plain red dot rather than a number.
  Screenshots were not viewable, so this is inferred, not confirmed.
- Multiple waiting agents look the same as one. Clears when Ghostty is refocused.
- The PR requests macOS badge permission. Check System Settings -> Notifications -> Ghostty ->
  "Badge app icon" is allowed.
- Nothing outside Ghostty can set a number on its dock icon (badge is controlled by the app itself).
  `system` toast delivery goes through `terminal-notifier`, which badges its own icon, not Ghostty's.
- Optional count substitute: the plugin can call `client.window_title.set` with something like
  "(2) waiting". Shows in Ghostty's title bar / window list, not the dock.

## Expected final result
- Deliverable is a Herdr plugin only (folder with `herdr-plugin.toml` + a short script), installed
  with `herdr plugin link <folder>`. No Ghostty patch or code changes.
- Ghostty side: keep default `bell-features`; just ensure badge permission (above).
- Behavior: when an agent turns `blocked` or `done` while Ghostty is in the background, the plugin
  rings the bell on the Herdr client's terminal -> red dot on the Ghostty dock icon + bell emoji in
  the window title. Dot clears on focus.
- Limits: dot not count; local Herdr only (not `herdr --remote` from the Mac); untested so far.
- If Herdr later adds a bell option under `ui.toast` (see #626), the plugin can be dropped in favor
  of a config setting.

## Open questions
- Which Ghostty `bell-features` flag drives the badge?
- Is `pane.agent_status_changed` accepted as a hook event?
- How to reliably find the right client tty when multiple clients/sessions are attached.

## Sources
- https://ghostty.org/docs/install/release-notes/1-2-0
- https://herdr.dev/docs/config-reference/
- https://herdr.dev/docs/configuration/
- https://herdr.dev/docs/plugins/
- https://herdr.dev/docs/socket-api/
- https://github.com/herdrdev/herdr/discussions/3561
- https://github.com/ghostty-org/ghostty/pull/7118
