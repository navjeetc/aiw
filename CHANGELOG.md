# Changelog

All notable changes to aiw are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). `aiw -v` prints the version you have.

## [Unreleased]

### Added

- `aiw -v` and `aiw --version` print the version.

## [0.1.1] - 2026-11-11

### Fixed

These crashes happened when the locale isn't UTF-8 (`LANG=C` or unset, as in cron, launchd, ssh
sessions and most Docker images):

- `aiw import` no longer crashes on non-ASCII text.
- Searching for a non-ASCII word (`aiw café`) works.
- A transcript with invalid bytes no longer stops the whole import. The bad bytes are shown as �.

## [0.1.0] - 2026-11-11

First public release.

### Added

- Full-text search across Claude Code, Codex, Claude (claude.ai export), ChatGPT (export, including
  Codex cloud tasks), Grok Bot and Muse, from one local SQLite index.
- `aiw recap` for what you worked on in a time window, with `--markdown` output and a collapsible
  view in the terminal.
- `--since` windows shared by search and recap (24h, 3d, 1w, today, yesterday, a date).
- Web results print the command that opens them on your platform: `open`, `xdg-open` or `start`.
- Runs entirely locally, with no network requests.

[Unreleased]: https://github.com/navjeetc/aiw/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/navjeetc/aiw/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/navjeetc/aiw/releases/tag/v0.1.0
