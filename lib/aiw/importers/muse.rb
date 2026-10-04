require "zip"

module Aiw
  module Importers
    # Reads exports from Meta's Muse desktop app ("EYI Package_<date>_<n>.zip" in ~/Documents or ~/Downloads).
    # Muse is one long-running chat, so it's split into one conversation per local day; otherwise every
    # search would land on the same single hit. Each export holds the whole history, so a newer export
    # simply replaces the days it covers.
    class Muse < Importer
      SOURCE = "Muse"

      FOLDERS = %w[ Documents Downloads ]

      def self.default_root = "~"

      # Oldest first, so the newest export has the last word on any day they share.
      def files
        FOLDERS.flat_map { Dir.glob(File.join(root, it, "EYI Package_*.zip")) }.sort_by { File.mtime(it) }
      end

      def parse(path)
        turns = manifest(path)&.fetch("turns", nil)
        return unless turns

        messages = turns.filter_map { message_from(it) }
        messages.group_by { Time.parse(it.created_at).localtime.to_date }.map { |day, of_day| conversation(day, of_day, path) }
      rescue Zip::Error => error
        warn "aiw: could not read #{path}: #{error.message}" if ENV["AIW_DEBUG"]
        nil
      end

      private
        def manifest(path)
          Zip::File.open(path) do |zip|
            entry = zip.find_entry("manifest.json")
            JSON.parse(entry.get_input_stream.read) if entry
          end
        end

        # Attachments appear inline as "[image:image/png workspace/user/media_library/…]".
        def message_from(turn)
          text = clean(turn["content"].to_s.gsub(/\[image:[^\]]*\]/, ""))
          return if text.empty? || !%w[ user assistant ].include?(turn["role"])

          Message.new(role: turn["role"], text:, created_at: Time.parse(turn["created_at"]).utc.iso8601(3))
        end

        def conversation(day, messages, path)
          prompts = messages.select { it.role == "user" }.map(&:text)
          first_prompt = prompts.find { it.length >= Recap::MEANINGFUL_PROMPT } || prompts.first
          Conversation.new(
            source: SOURCE,
            external_id: "muse-#{day.iso8601}",
            title: first_prompt ? truncate(first_prompt) : "Muse, #{day.strftime("%b %-d")}",
            project: nil,
            started_at: messages.first.created_at,
            updated_at: messages.last.created_at,
            path:,
            messages:)
        end
    end
  end
end
