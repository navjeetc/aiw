module Aiw
  # Base for importers that read conversations from local files.
  # Subclasses define #files and #parse(path) → a Conversation, an array of them, or nil to skip.
  class Importer
    Result = Data.define(:imported, :skipped, :failed)

    attr_reader :root

    def initialize(root = self.class.default_root)
      @root = File.expand_path(root)
    end

    def import_into(store)
      imported = skipped = failed = 0

      files.each do |path|
        stat = File.stat(path)
        if store.unchanged?(path, stat)
          skipped += 1
        else
          conversations = Array(parse(path)).select { it.messages.any? }
          store.transaction { conversations.each { store.save(it) } }
          if conversations.any?
            imported += conversations.size
          else
            skipped += 1
          end
          store.seen(path, stat)
        end
      rescue JSON::ParserError, SystemCallError => error
        warn "aiw: could not import #{path}: #{error.message}" if ENV["AIW_DEBUG"]
        failed += 1
      end

      Result.new(imported:, skipped:, failed:)
    end

    private
      def each_json_line(path)
        File.foreach(path) do |line|
          yield JSON.parse(line)
        rescue JSON::ParserError
          next # a session still being written can end with a partial line
        end
      end

      # Strips machinery that assistants inject into the user's turn (<system-reminder> and friends)
      # and the U+FFFC placeholder apps leave where an image was attached.
      def clean(text)
        text.to_s.gsub(%r{<([a-z][\w-]*)[^>]*>.*?</\1>}m, "").delete("￼").strip
      end

      # First line that reads like a person wrote it, not leftover markup.
      def truncate(text, length = 80)
        line = text.to_s.lines.map(&:strip).find { it.match?(/\A[^<>\s]/) }.to_s
        line.length > length ? "#{line[0, length - 1]}…" : line
      end
  end
end
