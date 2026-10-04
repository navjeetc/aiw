module Aiw
  # What happened across assistants in a time window, built from message timestamps so a long-running
  # session counts on the days you actually worked in it.
  class Recap
    Report = Data.define(:since, :label, :entries)
    Entry = Data.define(:source, :external_id, :title, :project, :messages, :prompts, :first_at, :last_at)

    UNITS = { "h" => 3600, "d" => 86_400, "w" => 604_800 }
    UNIT_NAMES = { "h" => "hour", "d" => "day", "w" => "week" }

    # Prompts shorter than this ("yes", "next", "merge it") say nothing about what got done.
    MEANINGFUL_PROMPT = 15

    def initialize(store, now: Time.now)
      @store = store
      @now = now
    end

    def call(since: "24h", source: nil)
      start, label = window(since)

      rows = @store.db.execute(<<~SQL, [ start.utc.iso8601(3), @now.utc.iso8601(3), source, source ])
        SELECT c.id, c.source, c.external_id, c.title, c.project, m.role, m.text, m.created_at
        FROM messages m JOIN conversations c ON c.id = m.conversation_id
        WHERE m.role IN ('user', 'assistant') AND m.created_at BETWEEN ? AND ?
          AND (? IS NULL OR c.source = ? COLLATE NOCASE)
        ORDER BY m.created_at
      SQL

      entries = rows.group_by { it["id"] }.values.map { entry(it) }.sort_by(&:last_at).reverse
      Report.new(since: start, label:, entries:)
    end

    private
      def window(spec)
        case spec.to_s.strip.downcase
        when /\A(\d+)\s*([hdw])\z/
          count, unit = $1.to_i, $2
          [ @now - count * UNITS[unit], "Last #{count} #{UNIT_NAMES[unit]}#{"s" unless count == 1}" ]
        when "today"
          [ midnight(@now), "Today" ]
        when "yesterday"
          [ midnight(@now) - UNITS["d"], "Since yesterday" ]
        when /\A\d{4}-\d{2}-\d{2}\z/
          start = Time.new(*spec.split("-").map(&:to_i))
          [ start, "Since #{start.strftime('%b %-d')}" ]
        else
          raise ArgumentError, "don't understand --since #{spec.inspect}; try 24h, 3d, 1w, today, yesterday or 2026-10-01"
        end
      end

      def midnight(time) = Time.new(time.year, time.month, time.day)

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
