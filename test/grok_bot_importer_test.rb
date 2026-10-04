require_relative "test_helper"

class GrokBotImporterTest < Aiw::TestCase
  def setup
    @importer = Aiw::Importers::GrokBot.new(File.join(FIXTURES, "grok_bot"))
  end

  def test_finds_only_transcripts
    assert_equal 1, @importer.files.size
  end

  def test_names_the_conversation_after_the_bot
    conversation = @importer.parse(@importer.files.first)

    assert_equal "Grok Bot", conversation.source
    assert_equal "bot-1", conversation.external_id
    assert_equal "Travel", conversation.title
    assert_equal "2026-08-20T14:00:00.000Z", conversation.started_at
  end

  def test_keeps_what_you_typed_and_what_the_bot_replied
    messages = @importer.parse(@importer.files.first).messages

    assert_equal %w[ assistant user assistant ], messages.map(&:role)
    assert_equal "Find a hotel in Lisbon near Alfama for October", messages[1].text
    refute messages.any? { it.text.include?("gondola") }, "widgets are UI cards, not conversation"
  end

  def test_decodes_blob_names
    key = "sand.client.slice.account.google-oauth2%7C42.transcript.replicas.bot-1"
    assert_equal key, Aiw::Importers::GrokBot.decode(Aiw::Importers::GrokBot.encode(key))
  end

  def test_searchable_and_in_recaps
    @importer.import_into(store)

    assert_equal [ "Grok Bot" ], search("lisbon hotel").map(&:source)
    assert_equal [ "Travel" ], Aiw::Recap.new(store, now: Time.utc(2026, 8, 21)).call(since: "1d").entries.map(&:title)
  end
end
