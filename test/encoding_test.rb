require_relative "test_helper"
require "fileutils"
require "open3"
require "rbconfig"

# cron, launchd, ssh sessions and most Docker images run without a UTF-8 locale, which makes Ruby read
# files as US-ASCII. Assistant transcripts are UTF-8 JSON whatever the locale says.
class EncodingTest < Aiw::TestCase
  AIW = File.expand_path("../bin/aiw", __dir__)

  def setup
    @home = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def test_the_locale_really_is_ascii_in_these_tests
    assert_equal "US-ASCII", run_ruby("-e", "print Encoding.default_external")
  end

  def test_imports_and_searches_non_ascii_text_without_a_utf8_locale
    write ".claude/projects/-Users-me-dev-trip/s-1.jsonl",
      { type: "user", message: { role: "user", content: "Plan a café crawl in Lisbon — pastéis de nata" },
        timestamp: "2026-08-01T10:00:00.000Z", cwd: "/Users/me/dev/trip" }.to_json
    write ".codex/sessions/rollout-2025-06-23-cdx-u.json",
      { session: { timestamp: "2025-06-23T22:14:51.988Z", id: "cdx-u" },
        items: [ { type: "message", role: "user", content: [ { type: "input_text", text: "Grüße für die Crème brûlée" } ] } ] }.to_json

    imported = run_ruby(AIW, "import")
    assert_match(/Claude Code\s+1 imported/, imported)
    assert_match(/Codex\s+1 imported/, imported)

    assert_match "café crawl", run_ruby(AIW, "--no-import", "pastéis")
    assert_match "Crème brûlée", run_ruby(AIW, "--no-import", "brûlée")
  end

  def test_invalid_bytes_are_replaced_instead_of_stopping_the_import
    line = ->(text) { %({"type":"user","message":{"role":"user","content":"#{text}"},"timestamp":"2026-08-01T10:00:00.000Z","cwd":"/p"}\n) }
    write ".claude/projects/-p/a-damaged.jsonl", line.("half a message \xFF\xFE then the rest".b)
    write ".claude/projects/-p/b-fine.jsonl", line.("a perfectly fine session")

    result = Aiw::Importers::ClaudeCode.new(File.join(@home, ".claude/projects")).import_into(store)

    assert_equal 2, result.imported
    assert_equal 0, result.failed
    assert_equal 1, search("perfectly").size
    assert_match "half a message \uFFFD\uFFFD then the", search("rest").first.snippet
  end

  private
    def write(relative, content)
      path = File.join(@home, relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, content)
    end

    def run_ruby(*args)
      env = { "HOME" => @home, "AIW_DB" => File.join(@home, "aiw.sqlite3"), "LC_ALL" => "C", "LANG" => "C", "NO_COLOR" => "1" }
      out, status = Open3.capture2e(env, RbConfig.ruby, *args)
      assert status.success?, "#{args.join(" ")} failed:\n#{out}"
      out.force_encoding(Encoding::UTF_8)
    end
end
