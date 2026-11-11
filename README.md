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
aiw -v                    which version you have (also --version)
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
[CHANGELOG.md](CHANGELOG.md) lists what changed in each release.

## Privacy

Everything stays on your machine. aiw makes no network requests: it reads your assistants' local
files and exports, and writes one SQLite index at `~/.aiw/history.sqlite3`. Nothing is uploaded and
there is no telemetry. Results show a command for getting back to the conversation (`claude --resume …`,
`codex resume …`, or a browser command such as `open https://claude.ai/chat/…` for web chats). aiw only
prints it; nothing runs unless you do.

aiw only reads from your assistants' folders; it never changes or deletes them. The index holds the full
text of your conversations, so treat it as being as private as the chats themselves. Deleting it
removes everything aiw stored.

If a future feature (such as AI recap summaries on the [roadmap](docs/ROADMAP.md)) ever sends text to
an outside model, it will be opt-in and clearly labelled.

## Setup

aiw is a Ruby command-line tool that needs Ruby 3.4 or newer.

| Platform | Status |
|----------|--------|
| macOS    | Supported. This is where aiw is built and used every day. |
| Linux    | Should work, but nobody has tested it yet. Every source except Grok Bot (a Mac app) reads the same `~/` paths. Reports are welcome. |
| Windows  | Untested. Use [WSL](https://learn.microsoft.com/windows/wsl/install) and follow the Linux steps. Note that aiw inside WSL sees the Linux home folder, not your Windows one. |

Web results print the right command to open them for your platform: `open` on macOS, `xdg-open` on
Linux, `start` on Windows.

If you already use Ruby 3.4, skip to [Install aiw](#2-install-aiw).

### 1. Get Ruby 3.4

Check what you have:

```
ruby -v
```

If that prints `ruby 3.4` or newer, you're set. Otherwise, follow the steps for your system.

The commands below add lines to `~/.zshrc`, which is the default shell config on macOS. If your shell
is bash (the default on most Linux systems), use `~/.bashrc` and `exec bash` instead.

#### macOS

macOS comes with Ruby 2.6 at `/usr/bin/ruby`, which is too old, so most Macs need a newer one. Pick
**one** of these:

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

rbenv, chruby and asdf work too. aiw's `.ruby-version` file asks for Ruby 3.4.1, and those tools
switch to it as soon as you `cd` into the folder. So install that exact version even if you already
have another 3.4. Step 2 shows how to check.

#### Linux

Check your distribution's Ruby first, because it is often too old. Fedora 42+ and Arch ship 3.4 or newer
(`sudo dnf install ruby ruby-devel` or `sudo pacman -S ruby`). Ubuntu 24.04 ships 3.2 and Debian 13
ships 3.3, so `apt install ruby` isn't enough there.

If yours is too old, use [mise](https://mise.jdx.dev/getting-started.html). It builds Ruby from source,
so on Debian or Ubuntu install the build tools first:

```
sudo apt install build-essential libssl-dev libyaml-dev zlib1g-dev libffi-dev libreadline-dev
mise use -g ruby@3.4
ruby -v
```

On other distributions, see [ruby-build's list of dependencies](https://github.com/rbenv/ruby-build/wiki#suggested-build-environment).

#### Then, on any system

Bundler, which installs the gems aiw needs, comes with Ruby 3.4, so there's nothing else to install.

### 2. Install aiw

```
git clone https://github.com/navjeetc/aiw.git
cd aiw
ruby -v                                 # check again, now inside the folder
bundle install                          # installs sqlite3 and rubyzip
mkdir -p ~/.local/bin
ln -s "$PWD/bin/aiw" ~/.local/bin/aiw   # or anywhere on your PATH
```

If `cd` or `ruby -v` says 3.4.1 isn't installed, or `ruby -v` shows a different version, your version manager has read `.ruby-version`.
Install that version and run `ruby -v` again:

| Version manager | Command |
|-----------------|---------|
| rbenv           | `rbenv install 3.4.1` |
| chruby          | `ruby-install ruby 3.4.1`, then open a new shell |
| asdf            | `asdf install ruby 3.4.1` |
| mise            | `mise install ruby@3.4.1` |

Homebrew users without a version manager can skip this. Their Ruby ignores `.ruby-version`.

If `~/.local/bin` isn't on your PATH yet (`aiw` gives "command not found"), add it and open a new shell.
Many Linux systems already include it once the folder exists, after you log in again.

```
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc    # or ~/.bashrc
exec zsh                                                   # or exec bash
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
- **`bundle install` fails while compiling**: install a C compiler and try again. On macOS, run
  `xcode-select --install`. On Debian or Ubuntu, run `sudo apt install build-essential`. On Fedora,
  run `sudo dnf install gcc make ruby-devel`.- **A source shows 0 conversations**: run `AIW_DEBUG=1 aiw import` to see which files failed and why.

### Where things live

The index lives at `~/.aiw/history.sqlite3` (override with `AIW_DB`). Delete it any time to rebuild from
scratch. Set `AIW_DEBUG=1` to see files that failed to import.

## Tests

```
bundle exec rake
```

## License

MIT. See [LICENSE](LICENSE).
