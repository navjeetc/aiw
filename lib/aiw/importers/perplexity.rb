require "zip"

module Aiw
  module Importers
    # Reads Perplexity exports (Settings → Account → Data export; the link arrives by email). The download is
    # user_data_export_<date>_….zip holding conversations-<date>-<id>.json and a user-data spreadsheet;
    # browsers that unzip downloads leave a folder with the same two files. Each thread becomes one
    # conversation, each entry a question and its answer. Exports are full snapshots, so only the newest
    # one is read.
    class Perplexity < Importer
      SOURCE = "Perplexity"

      FOLDERS = %w[ Documents Downloads ]
      ZIP = "user_data_export_*.zip"
      CONVERSATIONS = /\Aconversations-[^\/]*\.json\z/
      CITATION = /\[\d+\](?!\()/ # [1] markers that point at sources; Markdown links like [1](url) stay

      def self.default_root = "~"

      def files
        zips = FOLDERS.flat_map { Dir.glob(File.join(root, it, ZIP)) }
        unzipped = FOLDERS.flat_map { Dir.glob(File.join(root, it, "*", "conversations-*.json")) }
          .select { Dir.glob(File.join(File.dirname(it), "user-data-*.xlsx")).any? }

        latest = (zips + unzipped).max_by { File.mtime(it) }
        latest ? [ latest ] : []
      end

      def parse(path)
        json = path.end_with?(".zip") ? conversations_json(path) : read(path)
        return unless json

        Array(JSON.parse(json)["conversations"]).filter_map { thread(it, path) if it.is_a?(Hash) }
      rescue Zip::Error => error
        warn "aiw: could not read #{path}: #{error.message}" if ENV["AIW_DEBUG"]
        nil
      end

      private
        def conversations_json(path)
          Zip::File.open(path) do |zip|
            entry = zip.entries.find { File.basename(it.name).match?(CONVERSATIONS) }
            entry&.get_input_stream&.read&.force_encoding(Encoding::UTF_8)&.scrub
          end
        end

        def thread(thread, path)
          messages = Array(thread["entries"]).flat_map do |entry|
            at = timestamp(entry["created_at"]) || timestamp(thread["created_at"])
            [ message("user", entry["query"], at), message("assistant", entry["answer"].to_s.gsub(CITATION, ""), at) ]
          end.compact

          Conversation.new(
            source: SOURCE,
            external_id: thread["context_uuid"],
            # Perplexity often titles a thread with the whole first question, so long titles are cut down too.
            title: truncate(thread["context_title"].to_s.strip.empty? ? messages.find { it.role == "user" }&.text : thread["context_title"]),
            project: nil,
            started_at: timestamp(thread["created_at"]) || messages.first&.created_at,
            updated_at: messages.last&.created_at || timestamp(thread["updated_at"]),
            path:,
            messages:)
        end

        def message(role, text, created_at)
          text = clean(text)
          Message.new(role:, text:, created_at:) unless text.empty?
        end

        def timestamp(value) = (Time.parse(value).utc.iso8601(3) if value.is_a?(String) && !value.empty?)
    end
  end
end
