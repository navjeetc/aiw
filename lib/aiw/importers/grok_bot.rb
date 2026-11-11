module Aiw
  module Importers
    # Reads the Grok Bot desktop app's local transcript copies. The app keeps its state as JSON blobs whose
    # filenames are base32-encoded keys, e.g. "sand.client.slice.account.<account>.transcript.replicas.<bot id>".
    # Each Grok bot (e.g. Travel, Recipes) is one ongoing conversation; names come from the "roster" blob.
    # The full history lives on xAI's servers, so this covers what the app has cached locally.
    class GrokBot < Importer
      SOURCE = "Grok Bot"

      BASE32 = "abcdefghijklmnopqrstuvwxyz234567"

      def self.default_root = "~/Library/Application Support/Grok Bot/sand-client-persistence"

      def self.encode(key)
        key.unpack1("B*").scan(/.{1,5}/).map { BASE32[it.ljust(5, "0").to_i(2)] }.join
      end

      def self.decode(name)
        name.downcase.chars.filter_map { BASE32.index(it) }.map { "%05b" % it }.join.scan(/.{8}/).map { it.to_i(2).chr }.join
      end

      def files
        blobs.filter_map { |path, key| path if key.include?(".transcript.replicas.") }
      end

      def parse(path)
        id = blobs.fetch(path).split(".").last
        entries = JSON.parse(read(path)).dig("value", "entries") || []
        messages = entries.filter_map { message_from(it) }

        Conversation.new(
          source: SOURCE,
          external_id: id,
          title: bot_names[id] || truncate(messages.find { it.role == "user" }&.text),
          project: nil,
          started_at: messages.first&.created_at,
          updated_at: messages.last&.created_at,
          path:,
          messages:)
      end

      private
        def blobs
          @blobs ||= Dir.glob(File.join(root, "*.blob")).to_h { [ it, self.class.decode(File.basename(it, ".blob")) ] }
        end

        def bot_names
          @bot_names ||= begin
            roster = blobs.key(blobs.values.find { it.end_with?(".roster.last-roster") })
            rows = roster ? JSON.parse(read(roster)).dig("value", "rows") : []
            Array(rows).to_h { [ it["id"], it["name"] ] }
          end
        end

        # You type "message" entries with role user; the bot answers with "send-message" text.
        # Widgets, drafts, permission prompts and other UI cards are left out.
        def message_from(entry)
          role, text =
            case entry["kind"]
            when "message"      then [ entry["role"], entry["content"] ]
            when "send-message" then [ "assistant", entry.dig("message", "content") ] if entry.dig("message", "type") == "text"
            end
          return unless %w[ user assistant ].include?(role) && entry["timestampMs"]

          text = clean(text)
          Message.new(role:, text:, created_at: Time.at(entry["timestampMs"] / 1000.0).utc.iso8601(3)) unless text.empty?
        end
    end
  end
end
