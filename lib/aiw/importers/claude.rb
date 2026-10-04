require "zip"

module Aiw
  module Importers
    # Reads claude.ai exports (Settings → Privacy → Export data). The current export arrives as several zips;
    # the chats are in conversations-NNN.zip (older exports: data-*.zip), each holding a conversations.json.
    # Exports are snapshots, so new chats need a fresh export.
    class Claude < Importer
      SOURCE = "Claude"

      FOLDERS = %w[ Downloads Documents ]
      PATTERNS = %w[ conversations-*.zip data-*.zip ]

      def self.default_root = "~"

      # Oldest first, so the newest export has the last word on any conversation they share.
      def files
        FOLDERS.product(PATTERNS).flat_map { |folder, pattern| Dir.glob(File.join(root, folder, pattern)) }.sort_by { File.mtime(it) }
      end

      def parse(path)
        chats = conversations_json(path)
        return unless chats.is_a?(Array) && chats.all? { it.is_a?(Hash) && it.key?("chat_messages") } # ChatGPT's file looks different

        chats.map { conversation(it, path) }
      rescue Zip::Error => error
        warn "aiw: could not read #{path}: #{error.message}" if ENV["AIW_DEBUG"]
        nil
      end

      private
        def conversations_json(path)
          Zip::File.open(path) do |zip|
            entry = zip.glob("**/conversations.json").first
            JSON.parse(entry.get_input_stream.read) if entry
          end
        end

        def conversation(chat, path)
          messages = Array(chat["chat_messages"]).filter_map { message_from(it) }

          Conversation.new(
            source: SOURCE,
            external_id: chat["uuid"],
            title: chat["name"].to_s.strip.empty? ? truncate(messages.find { it.role == "user" }&.text) : chat["name"].strip,
            project: nil,
            started_at: timestamp(chat["created_at"]),
            updated_at: messages.last&.created_at || timestamp(chat["updated_at"]),
            path:,
            messages:)
        end

        # Text and voice-note blocks only; thinking, tool calls and injected prompts are left out.
        def message_from(message)
          blocks = Array(message["content"]).select { %w[ text voice_note ].include?(it["type"]) }
          text = clean(blocks.any? ? blocks.map { it["text"] }.join("\n\n") : message["text"])
          role = message["sender"] == "human" ? "user" : "assistant"

          Message.new(role:, text:, created_at: timestamp(message["created_at"])) unless text.empty?
        end

        def timestamp(value) = (Time.parse(value).utc.iso8601(3) if value)
    end
  end
end
