require "shellwords"

module Aiw
  # Full-text search over all imported messages, collapsed to one hit per conversation.
  #
  # The index stems words ("packing", "packed" and "pack" all become "pack"), which finds related forms.
  # Messages containing the exact words you typed rank first, and exact: true keeps only those.
  class Search
    Hit = Data.define(:source, :external_id, :title, :project, :updated_at, :snippet, :matches, :exact)

    def initialize(store)
      @store = store
      @patterns = {}
      @store.db.create_function("aiw_exact", 2) do |result, text, pattern|
        result.result = exact_pattern(pattern).match?(text.to_s) ? 1 : 0
      end
    end

    # Every word must appear in the same message; "quoted words" match as a phrase.
    # With a window, only messages sent inside it count.
    def call(query, source: nil, limit: 20, exact: false, window: nil)
      terms = self.class.terms(query)
      return [] if terms.empty?

      match = terms.map { %("#{it.gsub('"', '""')}") }.join(" ")
      pattern = terms.map { |term| "(?=.*\\b#{term.split.map { Regexp.escape(it) }.join('\W+')}\\b)" }.join

      from, to = window&.bounds

      rows = @store.db.execute(<<~SQL, [ pattern, match, from, from, to, exact ? 1 : 0, source, source, limit ])
        WITH ranked AS MATERIALIZED (
          SELECT conversation_id, rank, aiw_exact(text, ?) AS exact,
                 snippet(messages, 0, char(1), char(2), '…', 14) AS snippet
          FROM messages WHERE messages MATCH ? AND (? IS NULL OR created_at BETWEEN ? AND ?)
        ),
        best AS (
          SELECT *, row_number() OVER (PARTITION BY conversation_id ORDER BY exact DESC, rank) AS position,
                    count(*) OVER (PARTITION BY conversation_id) AS matches
          FROM ranked WHERE exact >= ?
        )
        SELECT c.source, c.external_id, c.title, c.project, c.updated_at, best.snippet, best.matches, best.exact = 1 AS exact
        FROM best JOIN conversations c ON c.id = best.conversation_id
        WHERE best.position = 1 AND (? IS NULL OR c.source = ? COLLATE NOCASE)
        ORDER BY best.exact DESC, best.rank
        LIMIT ?
      SQL

      rows.map { |row| Hit.new(**row.transform_keys(&:to_sym), exact: row["exact"] == 1) }
    end

    def self.terms(query)
      Shellwords.split(query)
    rescue ArgumentError
      query.split
    end

    private
      def exact_pattern(pattern)
        @patterns[pattern] ||= Regexp.new(pattern, Regexp::IGNORECASE | Regexp::MULTILINE)
      end
  end
end
