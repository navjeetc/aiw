require_relative "test_helper"

class RecapTest < Aiw::TestCase
  def setup
    import_fixtures
  end

  def test_web_conversations_open_with_the_platforms_browser_command
    assert_equal "xdg-open https://claude.ai/chat/c-1", Aiw::RecapView.resume_command("Claude", "c-1", opener: "xdg-open")
    assert_equal "start https://chatgpt.com/c/c-2", Aiw::RecapView.resume_command("ChatGPT", "c-2", opener: "start")
    assert_equal "xdg-open https://chatgpt.com/codex/tasks/task_e_9",
      Aiw::RecapView.resume_command("Codex", "task_e_9", opener: "xdg-open")
  end

  def test_cli_sessions_resume_the_same_way_everywhere
    assert_equal "claude --resume s-1", Aiw::RecapView.resume_command("Claude Code", "s-1", opener: "xdg-open")
    assert_equal "codex resume cdx-1", Aiw::RecapView.resume_command("Codex", "cdx-1", opener: "start")
    assert_nil Aiw::RecapView.resume_command("Grok Bot", "bot-1")
  end

  def test_includes_only_conversations_active_in_the_window
    report = recap("24h", now: Time.utc(2026, 8, 12, 12))

    assert_equal "Last 24 hours", report.label
    assert_equal [ "cdx-1" ], report.entries.map(&:external_id)
  end

  def test_orders_the_most_recent_first
    report = recap("3w", now: Time.utc(2026, 8, 15))

    assert_equal [ "Codex", "Claude Code" ], report.entries.map(&:source)
  end

  def test_counts_messages_and_keeps_meaningful_prompts
    recap("1d", now: Time.utc(2026, 8, 1, 12)).entries => [ entry ]

    assert_equal 2, entry.messages
    assert_equal [ "Set up nginx for the staging box" ], entry.prompts
    assert_equal "2026-08-01T10:00:00.000Z", entry.first_at
    assert_equal "2026-08-01T10:00:05.000Z", entry.last_at
  end

  def test_counts_only_messages_inside_the_window
    recap("2026-08-01", now: Time.utc(2026, 8, 1, 12)).entries => [ entry ]

    assert_equal "Since Aug 1", recap("2026-08-01").label
    assert_equal 2, entry.messages
  end

  def test_filters_by_source
    assert_empty recap("1w", source: "codex", now: Time.utc(2026, 8, 3)).entries
  end

  def test_rejects_windows_it_does_not_understand
    error = assert_raises(ArgumentError) { recap("last week") }
    assert_match "try 24h", error.message
  end

  private
    def recap(since, source: nil, now: Time.now)
      Aiw::Recap.new(store, now:).call(since:, source:)
    end
end

class RecapCLITest < Aiw::TestCase
  def test_groups_conversations_by_assistant
    output = run_cli("recap", "--since", "2026-07-01")

    assert_match(/conversations? in 2 assistants/, output)
    assert_includes output, "Codex (1)"
    assert_includes output, "    • Rotate the TLS certificates on the load balancer"
    assert_includes output, "    codex resume cdx-1"
  end

  def test_writes_markdown
    output = run_cli("recap", "--since", "2026-07-01", "--markdown")

    assert_match(/\A## Since Jul 1: 2 conversations in 2 assistants/, output)
    assert_includes output, "### Claude Code"
    assert_includes output, "- **Nginx staging setup** (shop) · 2 messages"
  end

  def test_accepts_loose_assistant_names
    %w[ grok grokbot GROK-BOT codex ].each do |name|
      Aiw::CLI.new(StringIO.new, store:, importers: []).run([ "recap", "--source", name ])
    end
  end

  def test_says_when_an_assistant_is_not_indexed
    assert_output(nil, "aiw: copilot isn't indexed yet. aiw currently reads: Claude Code, Claude, ChatGPT, Codex, Grok Bot, Muse\n") do
      assert_raises(SystemExit) { Aiw::CLI.new(StringIO.new, store:).run(%w[ recap --source copilot ]) }
    end
  end

  def test_refreshes_the_index_before_answering
    output = run_cli("nginx")

    assert_includes output, "Found in: Claude Code (1)"
  end

  private
    def run_cli(*args)
      out = StringIO.new
      importers = [ Aiw::Importers::ClaudeCode.new(File.join(FIXTURES, "claude_code")),
                    Aiw::Importers::Codex.new(File.join(FIXTURES, "codex")) ]
      Aiw::CLI.new(out, store:, importers:).run(args)
      out.string
    end
end

class WindowTest < Minitest::Test
  NOW = Time.new(2026, 10, 7, 15, 30)

  def test_relative_spans
    assert_equal [ NOW - 7 * 86_400, "Last week" ], parse("1w")
    assert_equal [ NOW - 3 * 86_400, "Last 3 days" ], parse("3d")
    assert_equal [ NOW - 12 * 3600, "Last 12 hours" ], parse("12h")
  end

  def test_calendar_days
    assert_equal [ Time.new(2026, 10, 7), "Today" ], parse("today")
    assert_equal [ Time.new(2026, 10, 6), "Since yesterday" ], parse("yesterday")
    assert_equal [ Time.new(2026, 10, 1), "Since Oct 1" ], parse("2026-10-01")
  end

  def test_ends_now
    assert_equal NOW, Aiw::Window.parse("1w", now: NOW).finish
  end

  private
    def parse(spec) = Aiw::Window.parse(spec, now: NOW).then { [ it.start, it.label ] }
end
