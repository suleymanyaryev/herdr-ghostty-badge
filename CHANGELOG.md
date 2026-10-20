# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-21

### Added
- Ring the terminal bell from the agent's pane when it turns `blocked` or `done` and stays that way for
  `BADGE_DELAY` seconds (default 1). In Ghostty this badges and bounces the dock icon.
- Window title `(N) waiting · herdr` counting `blocked` + `done` panes, handed back to Herdr when the count
  reaches zero.
- Optional settings file at `$(herdr plugin config-dir suleymanyaryev.ghostty-badge)/config`.

[0.1.0]: https://github.com/suleymanyaryev/herdr-ghostty-badge/releases/tag/v0.1.0
