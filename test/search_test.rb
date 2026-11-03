require_relative "test_helper"

class SearchTest < Aiw::TestCase
  def setup
    import_fixtures
  end

  def test_names_the_assistant_that_was_used
    assert_equal [ "Claude Code" ], search("nginx staging").map(&:source)
    assert_equal [ "Codex" ], search("certificates").map(&:source)
  end

  def test_matches_word_stems
    assert_equal [ "Codex" ], search("rotating certificate").map(&:source)
  end

  def test_finds_conversations_by_title
    assert_equal [ "cdx-1" ], search("load balancer certs").map(&:external_id)
  end

  def test_quoted_words_match_as_a_phrase
    assert_equal 1, search(%("staging box")).size
    assert_empty search(%("box staging"))
  end

  def test_collapses_many_matching_messages_into_one_hit
    hits = search("certificates")

    assert_equal 1, hits.size
    assert_equal 2, hits.first.matches
  end

  def test_filters_by_source
    assert_empty search("certificates", source: "claude code")
    assert_equal 1, search("certificates", source: "codex").size
  end

  def test_ignores_what_was_never_said_to_the_user
    assert_empty search("kubernetes")  # thinking
    assert_empty search("terraform")   # injected AGENTS.md
    assert_empty search("redis")       # subagents
    assert_empty search("screenshot")  # image placeholders
    assert_empty search("memcached")   # compaction summaries
  end

  def test_survives_stray_quotes_and_operators
    assert_empty search(%(don't OR "))
    assert_empty search("   ")
  end
end

class ImportTest < Aiw::TestCase
  def test_only_rereads_files_that_changed
    first = import_fixtures
    second = import_fixtures

    assert_equal 0, second.imported
    assert_equal first.imported + first.skipped, second.skipped
  end

  def test_reimporting_a_grown_session_replaces_its_messages
    Dir.mktmpdir do |root|
      FileUtils.cp_r(File.join(FIXTURES, "codex", "."), root)
      session = File.join(root, "archived_sessions", "rollout-2026-05-01T08-00-00-cdx-2.jsonl")
      importer = Aiw::Importers::Codex.new(root)
      importer.import_into(store)

      File.open(session, "a") do |file|
        file.puts({ timestamp: "2026-05-01T08:01:00.000Z", type: "response_item",
          payload: { type: "message", role: "assistant", content: [ { type: "output_text", text: "Fetched 42 transactions" } ] } }.to_json)
      end
      File.utime(Time.now, Time.now + 5, session)
      importer.import_into(store)

      assert_equal 1, search("plaid").size
      assert_equal 1, search("42 transactions").size
    end
  end
end

class CLITest < Aiw::TestCase
  def test_lists_the_assistants_that_matched
    output = run_cli("--apps", "certificates")

    assert_equal "Found in: Codex (1)\n", output
  end

  def test_shows_how_to_resume_the_conversation
    output = run_cli("nginx")

    assert_includes output, "Claude Code   2026-08-01  shop  Nginx staging setup"
    assert_includes output, "claude --resume 11111111-aaaa"
  end

  private
    def run_cli(*args)
      import_fixtures
      out = StringIO.new
      Aiw::CLI.new(out, store:).run([ *args, "--no-import" ])
      out.string
    end
end

class ExactWordsTest < Aiw::TestCase
  def setup
    save "packed", "These weeks are packed with meetings and packing tape is low"
    save "packing", "Make a packing list for Lisbon"
    save "pack", "Buy the 35-pack of Coke Zero"
  end

  def test_finds_related_forms_but_ranks_exact_words_first
    hits = search("packing")

    assert_equal %w[ packing packed pack ].sort, hits.map(&:external_id).sort
    assert hits.first(2).all?(&:exact), "both messages containing 'packing' come first"
    assert_equal [ "pack" ], hits.reject(&:exact).map(&:external_id)
  end

  def test_lists_the_most_recent_conversations_first
    save "older", "Pack the tent", at: "2026-07-01T10:00:00.000Z"
    save "newest", "Pack the stove", at: "2026-09-01T10:00:00.000Z"

    assert_equal %w[ newest pack older ], search("pack", exact: true).map(&:external_id)
  end

  def test_exact_keeps_only_the_words_you_typed
    assert_equal %w[ packed packing ].sort, search("packing", exact: true).map(&:external_id).sort
    assert_equal [ "pack" ], search("pack", exact: true).map(&:external_id)
  end

  def test_exact_phrases
    assert_equal [ "packing" ], search(%("packing list"), exact: true).map(&:external_id)
  end

  private
    def save(id, text, at: "2026-08-01T10:00:00.000Z")
      store.save(Aiw::Conversation.new(source: "Codex", external_id: id, title: nil, project: nil,
        started_at: at, updated_at: at, path: id,
        messages: [ Aiw::Message.new(role: "user", text:, created_at: at) ]))
    end
end

class ExactWordsCLITest < Aiw::TestCase
  def test_marks_where_related_forms_begin
    import_fixtures
    out = StringIO.new
    Aiw::CLI.new(out, store:, importers: []).run(%w[ stage ])

    assert_includes out.string, "── Related word forms (use -e for exact words only) ──"
  end
end

class SearchWindowTest < Aiw::TestCase
  def setup
    import_fixtures # Claude Code nginx chat on Aug 1, Codex certificates chat on Aug 12
  end

  def test_only_counts_messages_inside_the_window
    window = Aiw::Window.parse("1w", now: Time.utc(2026, 8, 13))

    assert_equal [ "Codex" ], search("certificates", window:).map(&:source)
    assert_empty search("nginx", window:)
  end

  def test_without_a_window_searches_everything
    assert_equal [ "Claude Code" ], search("nginx").map(&:source)
  end

  def test_the_cli_says_which_window_it_searched
    out = StringIO.new
    Aiw::CLI.new(out, store:, importers: []).run(%w[ search nginx --since 2026-07-01 ])

    assert_includes out.string, "Since Jul 1, found in: Claude Code (1)"
  end
end
