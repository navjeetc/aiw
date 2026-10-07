# aiw — AI work monitor

"Which assistant did I do that in?" One local, full-text index across your AI assistants.

```
$ aiw nginx staging
Found in: Codex (2), Claude Code (1)

Claude Code   2026-09-15  shop  Nginx staging setup
  Set up nginx for the staging box
  claude --resume 11111111-2222-3333-4444-555555555555

Codex         2026-08-12  infra  Rotate load balancer certs
  …proxy_pass for the staging box…
  codex resume 0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeeee
```

## Usage

```
aiw WORDS...              search (every word must appear in one message)
aiw '"two words"' more    quoted words match as a phrase (single quotes keep them past the shell)
aiw -e WORDS...           exact words only (packing, not packed or pack)
aiw WORDS... --since 1w   only messages from the last week (also 24h, 3d, today, yesterday, 2026-10-01)
aiw --apps WORDS...       only list which assistants matched
aiw -s grok WORDS...      search one assistant (loose names work: grok, grokbot, codex)
aiw -n 50 WORDS...        show more results (default 20)
aiw recap                 what you worked on in the last 24 hours, by assistant
aiw recap --since 3d      ...or: 12h, 1w, today, yesterday, 2026-10-01
aiw recap --markdown      paste into a standup, weekly review or journal
aiw import                refresh the index and show counts
aiw rebuild               re-read every session from scratch
aiw stats                 what's indexed
```

Each search first picks up new or changed sessions (about 0.1s when nothing changed), so there's no
background job to run. Skip that step with `--no-import`.

Words are stemmed, so `deploy` also finds `deploying` and `deployed`. Exact matches are listed first,
then related forms under a divider; `-e` drops the related forms. To pass a phrase through your
shell, wrap the double quotes in single quotes: `aiw '"packing list"'`.

## Sources

| Assistant   | Read from | Notes |
|-------------|-----------|-------|
| Claude Code | `~/.claude/projects/*/*.jsonl` | Titles come from your `/rename` or the auto title. Subagent transcripts are skipped. |
| Codex       | `~/.codex/sessions`, `~/.codex/archived_sessions` | Thread names come from `session_index.jsonl`. Guardian/subagent sessions are skipped. |
| Grok Bot    | `~/Library/Application Support/Grok Bot/sand-client-persistence` | The desktop app's local copy of each bot's transcript; the full history stays on xAI's servers. Each bot (e.g. Travel, Recipes) is one conversation. |
| Claude      | `conversations-*.zip` (or older `data-*.zip`) in `~/Downloads` or `~/Documents` | claude.ai export (Settings → Privacy → Export data). The emailed manifest lists several zips; only the conversations one is needed. Re-export to pick up new chats. Results link back to `claude.ai/chat/<id>`. |
| ChatGPT     | Export folder (or zip) in `~/Documents` or `~/Downloads`, recognized by its `chat.html` | chatgpt.com export (Settings → Data controls → Export data). Only the newest export is read. Codex cloud tasks in `codex.json` are filed under Codex (no timestamps, so search only). Results link back to chatgpt.com. |
| Muse        | `EYI Package_*.zip` in `~/Documents` or `~/Downloads` | Exported from the Muse desktop app. Muse keeps nothing on disk, so re-export to pick up new chats. Its one long chat is split into one conversation per day. |

Only what you typed and what the assistant replied gets indexed. Thinking, tool calls, tool output and
injected context (AGENTS.md, system reminders, environment blocks) are left out.

See [docs/ROADMAP.md](docs/ROADMAP.md) for planned
features such as natural-language search and AI recap summaries.

## Setup

Requires Ruby 3.4 and the `sqlite3` gem.

```
bundle install
ln -s "$PWD/bin/aiw" ~/.local/bin/aiw   # or anywhere on your PATH
```

The index lives at `~/.aiw/history.sqlite3` (override with `AIW_DB`). Delete it any time to rebuild from
scratch. Set `AIW_DEBUG=1` to see files that failed to import.

## Tests

```
bundle exec rake
```
