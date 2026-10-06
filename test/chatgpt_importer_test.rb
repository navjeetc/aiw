require_relative "test_helper"

class ChatGPTImporterTest < Aiw::TestCase
  T = Time.utc(2026, 9, 1, 10).to_f

  def setup
    @home = Dir.mktmpdir
    @export = File.join(@home, "Documents", "OpenAIExport")
    FileUtils.mkdir_p(@export)
    File.write(File.join(@export, "chat.html"), "<html></html>")
    @importer = Aiw::Importers::ChatGPT.new(@home)
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def test_finds_conversation_parts_and_codex_tasks_in_an_export_folder
    write "conversations-000.json", []
    write "conversations-001.json", []
    write "codex.json", []
    write "user.json", {}
    FileUtils.mkdir_p(File.join(@home, "Documents", "Unrelated"))
    File.write(File.join(@home, "Documents", "Unrelated", "conversations-000.json"), "[]")

    assert_equal %w[ codex.json conversations-000.json conversations-001.json ], @importer.files.map { File.basename(it) }
  end

  def test_follows_the_branch_the_chat_shows
    write "conversations-000.json", [ chat("c-1", "Sourdough schedule", current: "a2", mapping: {
      "root" => node(nil, nil),
      "u1"   => node("root", chat_message("user", "text", [ "Plan a sourdough bake for Saturday" ], T)),
      "a1"   => node("u1", chat_message("assistant", "text", [ "Old answer about rye" ], T + 10)),
      "a2"   => node("u1", chat_message("assistant", "text", [ "Feed the starter Friday night." ], T + 20)),
      "t1"   => node("u1", chat_message("assistant", "thoughts", [], T + 5))
    }) ]

    chat = parse_only
    assert_equal "Sourdough schedule", chat.title
    assert_equal [ "Plan a sourdough bake for Saturday", "Feed the starter Friday night." ], chat.messages.map(&:text)
    assert_equal "2026-09-01T10:00:00.000Z", chat.started_at
  end

  def test_keeps_text_from_multimodal_messages_and_skips_reasoning_and_custom_instructions
    write "conversations-000.json", [ chat("c-2", "", current: "a1", mapping: {
      "s1" => node(nil, chat_message("user", "text", [ "Always answer in French" ], T, system: true)),
      "u1" => node("s1", chat_message("user", "multimodal_text", [ { "asset_pointer" => "file-1" }, "What is in this photo?" ], T + 1)),
      "r1" => node("u1", chat_message("assistant", "reasoning_recap", [ "Thought for 4s" ], T + 2)),
      "a1" => node("r1", chat_message("assistant", "text", [ "A bowl of ramen." ], T + 3))
    }) ]

    chat = parse_only
    assert_equal [ "What is in this photo?", "A bowl of ramen." ], chat.messages.map(&:text)
    assert_equal "What is in this photo?", chat.title, "untitled chats are named after the first prompt"
  end

  def test_files_codex_cloud_tasks_under_codex
    write "codex.json", [ { id: "task_e_123", title: "Fix flaky login test", archived: false, turns: [
      { role: "user", input_items: [ { type: "message", role: "user", content: [ { content_type: "text", text: "Fix the flaky login test" } ] } ] },
      { role: "assistant", output_items: [ { type: "message", role: "assistant", content: [ { content_type: "text", text: "Added a wait for the redirect." } ] },
                                           { type: "pr", files: [] } ] }
    ] } ]

    task = parse_only
    assert_equal "Codex", task.source
    assert_equal [ "Fix the flaky login test", "Added a wait for the redirect." ], task.messages.map(&:text)
    assert_nil task.messages.first.created_at
  end

  def test_searchable_with_links_back
    write "conversations-000.json", [ chat("c-1", "Sourdough schedule", current: "u1", mapping: {
      "u1" => node(nil, chat_message("user", "text", [ "Plan a sourdough bake" ], T)) }) ]
    write "codex.json", [ { id: "task_e_9", title: "Sourdough timer app", turns: [
      { role: "user", input_items: [ { content: [ { content_type: "text", text: "Build a sourdough timer" } ] } ] } ] } ]
    @importer.import_into(store)

    out = StringIO.new
    Aiw::CLI.new(out, store:, importers: []).run(%w[ sourdough ])

    assert_includes out.string, "open https://chatgpt.com/c/c-1"
    assert_includes out.string, "open https://chatgpt.com/codex/tasks/task_e_9"
  end

  def test_reads_a_zipped_export
    path = File.join(@home, "Downloads", "abc123-2026-10-04-16-46-00-def.zip")
    FileUtils.mkdir_p(File.dirname(path))
    Zip::File.open(path, create: true) do |zip|
      zip.get_output_stream("chat.html") { it.write("<html></html>") }
      zip.get_output_stream("conversations.json") do |io|
        io.write(JSON.generate([ chat("c-3", "Zipped", current: "u1", mapping: { "u1" => node(nil, chat_message("user", "text", [ "hello from the zip" ], T)) }) ]))
      end
    end
    FileUtils.rm_rf(@export)

    @importer.files => [ path ]
    assert_equal [ "hello from the zip" ], @importer.parse(path).first.messages.map(&:text)
  end

  def test_reads_only_the_newest_export_when_the_zip_and_its_unzipped_folder_are_both_there
    write "conversations-000.json", []
    zip = File.join(@home, "Downloads", "abc123-2026-10-04-16-46-00-def.zip")
    FileUtils.mkdir_p(File.dirname(zip))
    Zip::File.open(zip, create: true) { |z| z.get_output_stream("chat.html") { it.write("") } }
    File.utime(Time.now - 3600, Time.now - 3600, zip)

    assert_equal [ "conversations-000.json" ], @importer.files.map { File.basename(it) }

    File.utime(Time.now + 60, Time.now + 60, zip)
    assert_equal [ zip ], @importer.files
  end

  private
    def write(name, data) = File.write(File.join(@export, name), JSON.generate(data))

    def parse_only
      conversations = @importer.files.flat_map { Array(@importer.parse(it)) }
      assert_equal 1, conversations.size
      conversations.first
    end

    def chat(id, title, current:, mapping:)
      { conversation_id: id, id:, title:, create_time: T, update_time: T + 60, current_node: current, mapping: }
    end

    def node(parent, message) = { parent:, message: }

    def chat_message(role, content_type, parts, time, system: false)
      { author: { role: }, content: { content_type:, parts: }, create_time: time, metadata: system ? { is_user_system_message: true } : {} }
    end
end
