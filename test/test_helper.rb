require "minitest/autorun"
require "stringio"
require "tmpdir"
require_relative "../lib/aiw"

class Aiw::TestCase < Minitest::Test
  FIXTURES = File.expand_path("fixtures", __dir__)

  def store
    @store ||= Aiw::Store.new(":memory:")
  end

  def import_fixtures
    Aiw::Importers::ClaudeCode.new(File.join(FIXTURES, "claude_code")).import_into(store)
    Aiw::Importers::Codex.new(File.join(FIXTURES, "codex")).import_into(store)
  end

  def search(query, **options)
    Aiw::Search.new(store).call(query, **options)
  end
end
