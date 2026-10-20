# herdr-ghostty-badge

[![CI](https://github.com/suleymanyaryev/herdr-ghostty-badge/actions/workflows/ci.yml/badge.svg)](https://github.com/suleymanyaryev/herdr-ghostty-badge/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A [Herdr](https://herdr.dev) plugin that tells you when an agent needs you, even when Ghostty isn't the
app you're looking at.

When an agent (Claude Code, OpenCode, Codex, or any agent Herdr tracks) becomes **blocked** or **done**:

- **The dock icon gets a badge and bounces.** The plugin rings the terminal bell and Ghostty handles the rest.
- **The window title shows how many agents are waiting**, e.g. `🔔 (2) waiting · herdr`.

When nothing is waiting, the title goes back to Herdr's normal one.

## Requirements

- macOS with [Ghostty](https://ghostty.org) 1.2 or newer (developed on 1.3.1)
- Herdr 0.9.5 or newer, running locally
- `jq` and `nc`. `jq` ships with macOS 15 and later; on older versions, `brew install jq`

## Install

```sh
herdr plugin install suleymanyaryev/herdr-ghostty-badge
```

Herdr shows the plugin's files and commands before installing. Check that it's active:

```sh
herdr plugin list
```

### Ghostty setup

- Keep Ghostty's default `bell-features`. The `attention` and `title` options must stay on; they are on
  by default.
- In **System Settings → Notifications → Ghostty**, turn on **Badge app icon**.

To check, run `sleep 5; printf '\a'` in a Ghostty window and switch to another app. The dock icon should
get a badge.

### Update and uninstall

```sh
herdr plugin update suleymanyaryev.ghostty-badge
herdr plugin uninstall suleymanyaryev.ghostty-badge
```

## Configuration

Settings are optional. They go in a file named `config` in the plugin's config directory:

```sh
dir=$(herdr plugin config-dir suleymanyaryev.ghostty-badge)
mkdir -p "$dir"
cat > "$dir/config" <<'EOF'
BADGE_DELAY=2
BADGE_TITLE_FMT='⏳ %d agents waiting'
EOF
```

| Setting           | Default                | Meaning                                                 |
|-------------------|------------------------|---------------------------------------------------------|
| `BADGE_DELAY`     | `1`                    | Seconds a pane must stay blocked/done before it rings    |
| `BADGE_TITLE_FMT` | `(%d) waiting · herdr` | `printf` format for the window title; `%d` is the count |
| `BADGE_DEBUG`     | `0`                    | `1` logs every step to the plugin log                   |

The file is plain `sh` and is read on every hook run, so changes apply without a reload.

## How it works

The plugin is one POSIX shell script, [`bin/badge.sh`](bin/badge.sh), hooked to Herdr events:

| Event                                                                   | What it does                   |
|-------------------------------------------------------------------------|--------------------------------|
| `pane.agent_status_changed`                                             | Maybe ring, then recount       |
| `pane.closed`, `pane.exited`, `pane.agent_detected`, `pane.focused`, startup | Recount                  |

- **Ring:** when a pane turns `blocked` or `done`, the script waits `BADGE_DELAY` seconds and checks the
  pane again. That way a prompt that's answered straight away doesn't ring. If the state hasn't changed,
  it writes a BEL to the pane's own pty. Herdr treats it like output from the agent and forwards the bell
  to the attached client, i.e. Ghostty. Ghostty only badges and bounces while it's unfocused, so the
  plugin can ring every time.
- **Recount:** counts the `blocked` + `done` panes in `herdr agent list`. If the count is above zero it
  sets the title with `client.window_title.set`. When it reaches zero it calls `client.window_title.clear`,
  but only if the plugin set the title. Nothing is cached, so a missed event is fixed on the next one.

## Limits

- **The dock badge doesn't count.** Only Ghostty can set its badge, and it shows the same mark for one
  bell or many. The number is only in the window title.
- The title is set on Herdr's foreground client.
- The plugin runs on the Herdr server, so remote sessions (`herdr --remote`) are untested.
- A bell written while an agent's TUI is in the middle of an OSC escape sequence can end that sequence
  early. This is rare and only causes a brief visual glitch.
- Other terminals: the bell still reaches whatever terminal you attach from, but the badge is a Ghostty
  feature.

## Troubleshooting

- **No badge from a plain `printf '\a'` either:** check the Ghostty notification permission and
  `bell-features` above.
- **No badge from agents:** set `BADGE_DEBUG=1` in the config, trigger a state change, then read the hook
  output:

  ```sh
  herdr plugin log list | jq -r '.result.logs[-5:][] | "\(.event) \(.status)\n\(.stderr)"'
  ```

- **The title is stuck showing a count:** focus any pane to force a recount. Or reset the title by hand:

  ```sh
  printf '%s\n' '{"id":"x","method":"client.window_title.clear","params":{}}' | nc -U -w 1 ~/.config/herdr/herdr.sock
  ```

## Development

```sh
git clone https://github.com/suleymanyaryev/herdr-ghostty-badge
herdr plugin link ./herdr-ghostty-badge
shellcheck bin/badge.sh
```

A linked plugin runs straight from the checkout. Edits take effect on the next hook run.

To fake agent states for testing, run a long-lived process in a scratch pane so Herdr doesn't reset the
state, then report states for it:

```sh
herdr pane run <pane_id> 'sleep 600'
herdr pane report-agent --source test --agent test --state blocked <pane_id>
herdr pane report-agent --source test --agent test --state working <pane_id>
```

`report-agent` can't fake `done`; test that with a real agent.

Background notes from the initial research: [docs/herdr-ghostty-badge-handoff.md](docs/herdr-ghostty-badge-handoff.md).

## License

[MIT](LICENSE) © 2026 Suleyman Yaryev
