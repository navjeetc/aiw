require_relative "test_helper"

class PerplexityImporterTest < Aiw::TestCase
  def setup
    @home = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@home, "Documents"))
    FileUtils.mkdir_p(File.join(@home, "Downloads"))
    @importer = Aiw::Importers::Perplexity.new(@home)
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def test_reads_only_the_newest_export
    export "Downloads", [ thread ], name: "user_data_export_2026-10-01_old.zip", age: 60
    newest = export "Documents", [ thread ], name: "user_data_export_2026-11-27_new.zip"
    File.write(File.join(@home, "Downloads", "unrelated.zip"), "")

    assert_equal [ newest ], @importer.files
  end

  def test_reads_an_unzipped_export_folder
    folder = File.join(@home, "Downloads", "user_data_export_2026-11-27_abc")
    FileUtils.mkdir_p(folder)
    File.write(File.join(folder, "conversations-20261127-abc.json"), JSON.generate(conversations: [ thread ]))
    File.write(File.join(folder, "user-data-20261127-abc.xlsx"), "")

    assert_equal [ "conversations-20261127-abc.json" ], @importer.files.map { File.basename(it) }
    assert_equal "Nginx staging setup", @importer.parse(@importer.files.first).first.title
  end

  def test_turns_each_thread_into_a_conversation
    export "Downloads", [ thread ]

    conversation = @importer.parse(@importer.files.first).first

    assert_equal "Perplexity", conversation.source
    assert_equal "ctx-1", conversation.external_id
    assert_equal "Nginx staging setup", conversation.title
    assert_equal "2026-09-15T10:00:00.123Z", conversation.started_at
    assert_equal "2026-09-15T10:05:00.000Z", conversation.updated_at
    assert_equal [ [ "user", "How do I proxy nginx to staging?" ], [ "assistant", "Use proxy_pass." ],
                   [ "user", "And add TLS?" ], [ "assistant", "Run certbot." ] ],
      conversation.messages.map { [ it.role, it.text ] }
  end

  def test_strips_citation_markers_but_keeps_links
    export "Downloads", [ thread(entries: [ entry("Where is the export?", "Open account details[1][2]. See [the docs](https://x.test)[3].") ]) ]

    answer = @importer.parse(@importer.files.first).first.messages.last.text

    assert_equal "Open account details. See [the docs](https://x.test).", answer
  end

  def test_skips_empty_questions_and_answers
    export "Downloads", [ thread(entries: [ entry("", "An answer with no question"), entry("A failed question", "") ]) ]

    messages = @importer.parse(@importer.files.first).first.messages

    assert_equal [ [ "assistant", "An answer with no question" ], [ "user", "A failed question" ] ],
      messages.map { [ it.role, it.text ] }
  end

  def test_titles_an_untitled_thread_by_its_first_question
    export "Downloads", [ thread(title: "") ]

    assert_equal "How do I proxy nginx to staging?", @importer.parse(@importer.files.first).first.title
  end

  def test_shortens_a_title_that_is_the_whole_question
    export "Downloads", [ thread(title: "I want to automate booking a pickleball court every Thursday because the Windmill Road courts are always gone") ]

    title = @importer.parse(@importer.files.first).first.title

    assert_equal 80, title.length
    assert title.end_with?("…")
  end

  def test_imports_into_the_store
    export "Downloads", [ thread ]

    assert_equal 1, @importer.import_into(store).imported
    assert_equal [ "Perplexity" ], search("certbot").map(&:source)
  end

  def test_skips_zips_without_conversations
    path = File.join(@home, "Downloads", "user_data_export_broken.zip")
    Zip::File.open(path, create: true) { |zip| zip.get_output_stream("notes.txt") { it.write("hi") } }

    assert_nil @importer.parse(path)
  end

  private
    def entry(query, answer, created_at = "2026-09-15T10:00:00.123456Z")
      { entry_uuid: "e", query:, answer:, created_at:, label: nil, query_status: "COMPLETED", engine_mode: "pro" }
    end

    def thread(title: "Nginx staging setup", entries: nil)
      entries ||= [ entry("How do I proxy nginx to staging?", "Use proxy_pass."),
                    entry("And add TLS?", "Run certbot.", "2026-09-15T10:05:00Z") ]
      { context_uuid: "ctx-1", context_title: title, created_at: "2026-09-15T10:00:00.123456Z",
        updated_at: "2026-09-15T10:05:00Z", mode: "COPILOT", collection_uuid: nil, entries: }
    end

    def export(folder, threads, name: "user_data_export_2026-11-27_abc.zip", age: 0)
      path = File.join(@home, folder, name)
      Zip::File.open(path, create: true) do |zip|
        zip.get_output_stream("conversations-20261127-abc.json") { it.write(JSON.generate(conversations: threads)) }
        zip.get_output_stream("user-data-20261127-abc.xlsx") { it.write("") }
      end
      File.utime(Time.now - age, Time.now - age, path)
      path
    end
end
