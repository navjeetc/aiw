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

## Privacy

Everything stays on your machine. aiw makes no network requests: it reads your assistants' local
files and exports, and writes one SQLite index at `~/.aiw/history.sqlite3`. Nothing is uploaded and
there is no telemetry. Results show a command for getting back to the conversation (`claude --resume …`,
`codex resume …` or `open https://claude.ai/chat/…`). aiw only prints it; nothing runs unless you do.

aiw only reads from your assistants' folders; it never changes or deletes them. The index holds the full
text of your conversations, so treat it as being as private as the chats themselves. Deleting it
removes everything aiw stored.

If a future feature (such as AI recap summaries on the [roadmap](docs/ROADMAP.md)) ever sends text to
an outside model, it will be opt-in and clearly labelled.

## Setup

aiw is a Ruby command-line tool. It needs Ruby 3.4 or newer and was built on macOS. Linux should work
for Claude Code, Codex and the export-based sources but is untested, and Grok Bot is macOS only.

If you already use Ruby 3.4, skip to [Install aiw](#2-install-aiw).

### 1. Get Ruby 3.4

Check what you have:

```
ruby -v
```

If that prints `ruby 3.4` or newer, you're set. macOS comes with Ruby 2.6 at `/usr/bin/ruby`, which is
too old, so most Macs need a newer one. Pick **one** of these:

**Homebrew** (simplest if you don't use Ruby for anything else):

```
brew install ruby
echo 'export PATH="$(brew --prefix ruby)/bin:$PATH"' >> ~/.zshrc
exec zsh
ruby -v    # should now say 3.4 or newer
```

Homebrew doesn't put its Ruby on your PATH by itself, so it won't hide the macOS one. The `echo` line
fixes that. If you skip it, `ruby` still means 2.6 and aiw won't start.

**mise** (if you already use mise or asdf for other languages):

```
mise use -g ruby@3.4
ruby -v
```

rbenv, chruby and asdf work too. aiw's `.ruby-version` file names the exact version it was developed with.

Bundler, which installs the gems aiw needs, comes with Ruby 3.4, so there's nothing else to install.

### 2. Install aiw

```
git clone https://github.com/navjeetc/aiw.git
cd aiw
bundle install                          # installs sqlite3 and rubyzip
mkdir -p ~/.local/bin
ln -s "$PWD/bin/aiw" ~/.local/bin/aiw   # or anywhere on your PATH
```

If `~/.local/bin` isn't on your PATH yet (`aiw` gives "command not found"), add it and open a new shell:

```
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
exec zsh
```

### 3. Build the index

```
aiw import    # first run reads everything; later runs only pick up new chats
aiw stats     # what got indexed
aiw recap     # what you worked on in the last 24 hours
```

Exports from claude.ai, ChatGPT and Muse are picked up once you download them (see [Sources](#sources)).
Claude Code, Codex and Grok Bot are read from their own folders, so no exports are needed.

To update aiw later, run `git pull` and then `bundle install` in the folder you cloned.

### Troubleshooting

- **`syntax error` mentioning `Ruby.framework/Versions/2.6`**: aiw is running under the old macOS Ruby.
  Redo step 1 and check that `ruby -v` says 3.4 or newer.
- **`cannot load such file -- sqlite3`**: aiw is running under a different Ruby than the one you ran
  `bundle install` with. Run `ruby -v` and `which ruby` in the same shell, fix your PATH (step 1), then
  run `bundle install` again.
- **`bundle install` fails while compiling**: install Apple's command line tools with
  `xcode-select --install` and try again.
- **A source shows 0 conversations**: run `AIW_DEBUG=1 aiw import` to see which files failed and why.

### Where things live

The index lives at `~/.aiw/history.sqlite3` (override with `AIW_DB`). Delete it any time to rebuild from
scratch. Set `AIW_DEBUG=1` to see files that failed to import.

## Tests

```
bundle exec rake
```

## License

MIT. See [LICENSE](LICENSE).
