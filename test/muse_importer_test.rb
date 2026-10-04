require_relative "test_helper"

class MuseImporterTest < Aiw::TestCase
  def setup
    @home = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@home, "Documents"))
    FileUtils.mkdir_p(File.join(@home, "Downloads"))
    @importer = Aiw::Importers::Muse.new(@home)
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def test_finds_exports_in_documents_and_downloads
    export "Documents", []
    export "Downloads", []
    File.write(File.join(@home, "Downloads", "unrelated.zip"), "")

    assert_equal 2, @importer.files.size
  end

  def test_splits_the_chat_into_one_conversation_per_day
    export "Documents", [
      turn("assistant", "Hey, I'm your agent.", "2026-09-22T12:14:15.721+00:00"),
      turn("user", "Draft a customer outreach email for Acme", "2026-09-22T12:20:00.000+00:00"),
      turn("assistant", "", "2026-09-22T12:20:01.000+00:00"),
      turn("assistant", "Here's a draft for the outreach email.", "2026-09-22T12:21:00.000+00:00"),
      turn("user", "Compare Acme with Globex", "2026-09-23T14:00:00.000+00:00")
    ]

    days = @importer.parse(@importer.files.first)

    assert_equal %w[ muse-2026-09-22 muse-2026-09-23 ], days.map(&:external_id)
    assert_equal "Draft a customer outreach email for Acme", days.first.title
    assert_equal 3, days.first.messages.size, "empty turns are dropped"
    assert_equal "2026-09-22T12:14:15.721Z", days.first.started_at
  end

  def test_titles_a_day_without_prompts_by_date
    export "Documents", [ turn("assistant", "Good morning! Here's your brief.", "2026-09-24T12:00:00.000+00:00") ]

    assert_equal "Muse, Sep 24", @importer.parse(@importer.files.first).first.title
  end

  def test_a_newer_export_replaces_the_days_it_covers
    export "Downloads", [ turn("user", "Plan the Lisbon itinerary", "2026-09-22T12:00:00.000+00:00") ], age: 60
    export "Documents", [ turn("user", "Plan the Lisbon itinerary", "2026-09-22T12:00:00.000+00:00"),
                          turn("user", "Book the Alfama hotel", "2026-09-22T13:00:00.000+00:00") ]

    result = @importer.import_into(store)

    assert_equal 2, result.imported
    assert_equal [ "Muse" ], search("lisbon").map(&:source)
    assert_equal 2, store.db.get_first_value("SELECT count(*) FROM messages WHERE role = 'user'")
  end

  def test_skips_zips_without_a_manifest
    path = File.join(@home, "Documents", "EYI Package_broken.zip")
    Zip::File.open(path, create: true) { |zip| zip.get_output_stream("notes.txt") { it.write("hi") } }

    assert_nil @importer.parse(path)
  end

  def test_drops_image_placeholders_and_titles_by_the_first_real_prompt
    export "Documents", [
      turn("user", "better", "2026-09-25T12:00:00.000+00:00"),
      turn("user", "[image:image/png workspace/user/media_library/image/11/abc.png]", "2026-09-25T12:01:00.000+00:00"),
      turn("user", "[image:image/jpeg workspace/x.jpg] What is in this listing photo?", "2026-09-25T12:02:00.000+00:00")
    ]

    day = @importer.parse(@importer.files.first).first

    assert_equal [ "better", "What is in this listing photo?" ], day.messages.map(&:text)
    assert_equal "What is in this listing photo?", day.title
  end

  private
    def turn(role, content, created_at)
      { turn_id: "t", role:, content:, source: "runtime", created_at:, channels: [ "main" ], resources: [] }
    end

    def export(folder, turns, age: 0)
      path = File.join(@home, folder, "EYI Package_10-04-2026_#{turns.size}#{folder}.zip")
      Zip::File.open(path, create: true) do |zip|
        zip.get_output_stream("manifest.json") { it.write(JSON.generate(exported_at: "2026-10-04", turns:)) }
      end
      File.utime(Time.now - age, Time.now - age, path)
      path
    end
end
