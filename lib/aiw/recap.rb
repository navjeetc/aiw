module Aiw
  # What happened across assistants in a time window, built from message timestamps so a long-running
  # session counts on the days you actually worked in it.
  class Recap
    Report = Data.define(:since, :label, :entries)
    Entry = Data.define(:source, :external_id, :title, :project, :messages, :prompts, :first_at, :last_at)

    # Prompts shorter than this ("yes", "next", "merge it") say nothing about what got done.
    MEANINGFUL_PROMPT = 15

    def initialize(store, now: Time.now)
      @store = store
      @now = now
    end

    def call(since: "24h", source: nil)
      window = Window.parse(since, now: @now)

      rows = @store.db.execute(<<~SQL, [ *window.bounds, source, source ])
        SELECT c.id, c.source, c.external_id, c.title, c.project, m.role, m.text, m.created_at
        FROM messages m JOIN conversations c ON c.id = m.conversation_id
        WHERE m.role IN ('user', 'assistant') AND m.created_at BETWEEN ? AND ?
          AND (? IS NULL OR c.source = ? COLLATE NOCASE)
        ORDER BY m.created_at
      SQL

      entries = rows.group_by { it["id"] }.values.map { entry(it) }.sort_by(&:last_at).reverse
      Report.new(since: window.start, label: window.label, entries:)
    end

    private
      def entry(rows)
        first = rows.first
        prompts = rows.select { it["role"] == "user" }
          .map { it["text"].gsub(/\s+/, " ").strip }
          .select { it.length >= MEANINGFUL_PROMPT && !it.start_with?("<") } # "<pasted_content …" is a paste, not a request
          .uniq

        Entry.new(
          source: first["source"], external_id: first["external_id"], title: first["title"], project: first["project"],
          messages: rows.size, prompts:, first_at: first["created_at"], last_at: rows.last["created_at"])
      end
  end
end
