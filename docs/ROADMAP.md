# aiw roadmap

Ideas for where aiw goes next. The rule so far still holds: everything stays on this machine,
and every feature works without AI first, with AI making it better.

## Shipped

- Claude Code, Codex and Grok Bot importers (local files, auto-refreshed on every search)
  - Grok Bot: reads the desktop app's local transcript copies, no export needed
- Claude and ChatGPT export importers (2026-10-04/05), including Codex cloud tasks from the ChatGPT export
- Muse importer (2026-10-04): reads the Muse desktop app's own export (`EYI Package_*.zip`) from
  ~/Documents or ~/Downloads. Muse keeps no conversations on disk, so new chats need a fresh export.
- Full-text search with stemming, phrases, `--apps`, `--source`, and resume commands
- `aiw recap` level 1: activity by assistant and project for any window, with Markdown output

## 1. Natural-language queries (local model)

**Goal:** ask the way you'd ask a person.

```
$ aiw ask "where did I set up the private github repo for the financial tracker last month?"
$ aiw ask "which assistant helped me compare time tracking tools?"
```

**Approach: the model plans, SQLite searches.** The model doesn't read your history to answer.
It turns the question into a structured search that the existing engine runs:

```json
{ "keywords": ["github", "repo", "private", "financial tracker"],
  "since": "2026-09-01", "until": "2026-09-30",
  "source": null }
```

- Small and fast, since the model only sees the question, not thousands of messages.
- Easy to test: the model's output is a plain JSON object we can check before running it.
- Easy to fall back: if the model is down or returns junk, run the words as a normal `aiw` search.

**Then search by meaning.** Keyword search misses paraphrases ("fixed login redirects" vs "auth
callback bug"). Add embeddings, number lists that capture what a passage means:

- Embed each message (or chunks of long ones) with a local embedding model at import time.
- Store the vectors next to the full-text index, for example with the `sqlite-vec` extension, so it's
  still one database file.
- Rank results by blending keyword and meaning scores ("hybrid search").
- Only new messages get embedded on each import, matching how imports work today.

**Runtime:** Ollama or LM Studio. Both serve a local HTTP API, so aiw needs nothing beyond `net/http`.

- On a 16 GB Mac with a normal app load, `qwen3.5:4b` (3.4 GB) is the recommended model.
  `qwen3.5:9b` (6.6 GB) is smarter but can push macOS into swap while it runs.
- Embedding model: `qwen3-embedding:0.6b` (small, fast).
- Config: `AIW_LLM_URL` and `AIW_LLM_MODEL`, defaulting to Ollama on `localhost:11434`.

**Decisions (2026-10-04)**

- **Fallback: yes.** When a plain `aiw WORDS` search finds nothing, retry it through the model,
  using query planning plus meaning search, and say so in the output ("No exact matches; closest by
  meaning:"). `aiw ask` always uses the model. Without a running model, plain search behaves as today.
- **Embed every message, not just prompts and titles.** Assistant replies are where the substance
  lives (the config, the fix, the repo name), so skipping them would make search dumber where it
  matters most. The cost is small: ~10,000 messages and ~5 MB of text split into ~1,000-character
  chunks is on the order of 8,000 vectors, roughly 30 MB at 1,024 dimensions.
  - Chunk long messages (some replies run past 4,000 characters) so one long answer doesn't blur
    into a single vague vector.
  - Skip throwaway messages under ~40 characters ("yes", "next", "merge and deploy"); they carry no
    meaning to match on.
  - The first full embedding pass runs once in the background. After that, each import only embeds
    new messages.

## 2. Activity recap across assistants

**Goal:** "What did I get done with AI in the last day / few days?"

```
$ aiw recap                 # last 24 hours, every assistant
$ aiw recap --since 3d
$ aiw recap --since 1w --source codex
```

**Level 1, no AI needed. Shipped 2026-10-04.** Group conversations active in the window by assistant and project:

```
Last 24 hours: 7 conversations in 2 assistants

Claude Code
  shop     Nginx staging setup         42 messages
  billing  Invoice rounding bug         9 messages

Codex
  infra    Rotate load balancer certs  15 messages
  ...
```

This only needs a query over message timestamps. Count by message `created_at`, not conversation
start, so a long-running session shows up on the days you actually worked in it.

**Level 2, AI summaries with the local model.**

- One or two sentences per conversation about what got done, built from only the messages inside the
  window.
- A short "today in brief" paragraph across all of them on top.
- Cache each summary keyed by conversation and last message, so re-running a recap only summarizes
  what changed. This keeps it fast on a laptop model.
- Long sessions: summarize in chunks, then summarize the summaries.

**Possible extras**

- `--format markdown` to paste into a standup, weekly review, or journal.
- A scheduled morning recap (launchd) written to a file or sent as a notification.
- Flag unfinished threads, for example conversations whose last message is the assistant asking you
  a question.

## Still on the list from the original plan

- screenpipe as an optional live feed for apps without local history
- MCP server so Claude Code itself can ask "where did I work on X?"
- Optional web UI on the same SQLite file
