module Aiw
  module Importers
    # Reads Codex sessions: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl, ~/.codex/archived_sessions,
    # and the older single-JSON rollout-*.json files from 2025. Thread names come from session_index.jsonl.
    class Codex < Importer
      SOURCE = "Codex"

      # Context Codex prepends to the user's turn; not something the user typed.
      INJECTED = [
        "# AGENTS.md instructions",
        "# In app browser",
        "# Files mentioned by the user",
        "The following is the Codex agent history",
        "Automation:"
      ]

      def self.default_root = "~/.codex"

      def files
        Dir.glob([ "sessions/**/rollout-*.json{,l}", "archived_sessions/rollout-*.json{,l}" ], base: root).map { File.join(root, it) }
      end

      def parse(path)
        path.end_with?(".jsonl") ? parse_jsonl(path) : parse_legacy(path)
      end

      private
        def parse_jsonl(path)
          meta = {}
          messages = []

          each_json_line(path) do |record|
            payload = record["payload"] || {}
            case record["type"]
            when "session_meta" then meta = payload
            when "response_item"
              message = message_from(payload, record["timestamp"])
              messages << message if message
            end
          end

          conversation(path, meta["id"], meta["cwd"], meta["timestamp"], messages) unless subagent?(meta)
        end

        def parse_legacy(path)
          data = JSON.parse(read(path))
          session = data["session"] || {}
          messages = Array(data["items"]).filter_map { message_from(it, session["timestamp"]) }

          conversation(path, session["id"], nil, session["timestamp"], messages)
        end

        def conversation(path, id, cwd, started_at, messages)
          Conversation.new(
            source: SOURCE,
            external_id: id || File.basename(path).sub(/\.jsonl?\z/, ""),
            title: thread_names[id] || truncate(messages.find { it.role == "user" }&.text),
            project: cwd,
            started_at: started_at || messages.first&.created_at,
            updated_at: messages.last&.created_at || started_at,
            path:,
            messages:)
        end

        # Guardian reviews and other helper agents Codex spawns behind the scenes.
        def subagent?(meta)
          meta["source"].is_a?(Hash) && meta["source"].key?("subagent")
        end

        def thread_names
          @thread_names ||= {}.tap do |names|
            index = File.join(root, "session_index.jsonl")
            each_json_line(index) { names[it["id"]] = it["thread_name"] } if File.exist?(index)
          end
        end

        def message_from(item, timestamp)
          return unless item["type"] == "message" && %w[ user assistant ].include?(item["role"])

          text = Array(item["content"])
            .filter_map { it["text"] if %w[ input_text output_text ].include?(it["type"]) }
            .map { clean(it) }
            .reject { |block| block.empty? || INJECTED.any? { block.start_with?(it) } }
            .join("\n")

          Message.new(role: item["role"], text:, created_at: timestamp) unless text.empty?
        end
    end
  end
end
