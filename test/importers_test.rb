require_relative "test_helper"

class ClaudeCodeImporterTest < Aiw::TestCase
  def setup
    path = File.join(FIXTURES, "claude_code", "-Users-me-dev-shop", "11111111-aaaa.jsonl")
    @conversation = Aiw::Importers::ClaudeCode.new(File.join(FIXTURES, "claude_code")).parse(path)
  end

  def test_reads_the_session
    assert_equal "Claude Code", @conversation.source
    assert_equal "11111111-aaaa", @conversation.external_id
    assert_equal "Nginx staging setup", @conversation.title
    assert_equal "/Users/me/dev/shop", @conversation.project
    assert_equal "2026-08-01T10:00:00.000Z", @conversation.started_at
  end

  def test_keeps_only_what_was_said
    assert_equal [ "Set up nginx for the staging box", "Here is a proxy_pass config for staging." ],
      @conversation.messages.map(&:text)
  end

  def test_skips_subagent_transcripts
    files = Aiw::Importers::ClaudeCode.new(File.join(FIXTURES, "claude_code")).files
    assert_equal [ "11111111-aaaa.jsonl" ], files.map { File.basename(it) }
  end
end

class CodexImporterTest < Aiw::TestCase
  def setup
    @importer = Aiw::Importers::Codex.new(File.join(FIXTURES, "codex"))
  end

  def test_drops_injected_context_and_developer_messages
    conversation = parse("sessions/2026/08/12/rollout-2026-08-12T09-00-00-cdx-1.jsonl")

    assert_equal [ "Rotate the TLS certificates on the load balancer", "Certificates rotated using certbot." ],
      conversation.messages.map(&:text)
    assert_equal "/Users/me/dev/infra", conversation.project
  end

  def test_uses_the_latest_thread_name
    assert_equal "Rotate load balancer certs", parse("sessions/2026/08/12/rollout-2026-08-12T09-00-00-cdx-1.jsonl").title
  end

  def test_falls_back_to_the_first_prompt_for_a_title
    assert_equal "Download the latest Plaid transactions", parse("archived_sessions/rollout-2026-05-01T08-00-00-cdx-2.jsonl").title
  end

  def test_reads_legacy_json_sessions
    conversation = parse("sessions/rollout-2025-06-23-cdx-legacy.json")

    assert_equal "cdx-legacy", conversation.external_id
    assert_equal [ "make dmg package", "Built the dmg with electron-builder." ], conversation.messages.map(&:text)
  end

  def test_skips_subagent_sessions
    assert_nil parse("sessions/2026/08/12/rollout-2026-08-12T10-00-00-cdx-guardian.jsonl")
  end

  private
    def parse(relative_path) = @importer.parse(File.join(FIXTURES, "codex", relative_path))
end
