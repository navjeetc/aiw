require_relative "test_helper"

class ClaudeImporterTest < Aiw::TestCase
  def setup
    @home = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@home, "Downloads"))
    @importer = Aiw::Importers::Claude.new(@home)
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def test_reads_conversations_with_their_names
    export "conversations-000.zip", [ chat("c-1", "Lisbon trip planning", [
      turn("human", [ text("Plan three days in Lisbon") ], "2026-09-01T10:00:00.123456Z"),
      turn("assistant", [ { type: "thinking", thinking: "secret about porto" },
                             text("Day 1: Alfama and the castle."),
                             { type: "tool_use", name: "web_search", input: {} } ], "2026-09-01T10:00:30.000000Z")
    ]) ]

    @importer.parse(@importer.files.first) => [ chat ]

    assert_equal "Claude", chat.source
    assert_equal "c-1", chat.external_id
    assert_equal "Lisbon trip planning", chat.title
    assert_equal %w[ user assistant ], chat.messages.map(&:role)
    assert_equal [ "Plan three days in Lisbon", "Day 1: Alfama and the castle." ], chat.messages.map(&:text)
    assert_equal "2026-09-01T10:00:00.123Z", chat.messages.first.created_at
  end

  def test_includes_voice_notes_and_falls_back_to_the_text_field
    export "conversations-000.zip", [ chat("c-2", "", [
      turn("human", [ { type: "voice_note", title: "Note", text: "Remind me about the condo lease" } ], "2026-09-02T10:00:00Z"),
      turn("assistant", [], "2026-09-02T10:00:05Z", text: "Lease renews on November 1.")
    ]) ]

    @importer.parse(@importer.files.first) => [ chat ]

    assert_equal "Remind me about the condo lease", chat.title, "untitled chats are named after the first prompt"
    assert_equal [ "Remind me about the condo lease", "Lease renews on November 1." ], chat.messages.map(&:text)
  end

  def test_ignores_zips_that_are_not_claude_exports
    chatgpt = [ { title: "From ChatGPT", mapping: {} } ]
    path = File.join(@home, "Downloads", "data-2026-10-04.zip")
    Zip::File.open(path, create: true) { |zip| zip.get_output_stream("conversations.json") { it.write(JSON.generate(chatgpt)) } }

    assert_nil @importer.parse(path)
  end

  def test_searchable_with_a_link_back_to_the_chat
    export "conversations-000.zip", [ chat("c-1", "Lisbon trip planning", [
      turn("human", [ text("Plan three days in Lisbon") ], "2026-09-01T10:00:00Z") ]) ]
    @importer.import_into(store)

    out = StringIO.new
    Aiw::CLI.new(out, store:, importers: []).run(%w[ lisbon --source claude ])

    assert_includes out.string, "Found in: Claude (1)"
    assert_includes out.string, "#{Aiw::RecapView::OPENER} https://claude.ai/chat/c-1"
  end

  private
    def chat(uuid, name, chat_messages)
      { uuid:, name:, summary: "", created_at: chat_messages.first[:created_at], updated_at: chat_messages.last[:created_at], chat_messages: }
    end

    def turn(sender, content, created_at, text: "")
      { uuid: "m", text:, content:, sender:, created_at:, updated_at: created_at, attachments: [], files: [] }
    end

    def text(value) = { type: "text", text: value, citations: [] }

    def export(name, chats)
      path = File.join(@home, "Downloads", name)
      Zip::File.open(path, create: true) { |zip| zip.get_output_stream("conversations.json") { it.write(JSON.generate(chats)) } }
    end
end
