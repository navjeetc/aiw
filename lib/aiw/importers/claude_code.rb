module Aiw
  module Importers
    # Reads Claude Code transcripts: ~/.claude/projects/<project>/<session-id>.jsonl
    # (subagent transcripts live in nested directories and are skipped).
    class ClaudeCode < Importer
      SOURCE = "Claude Code"

      def self.default_root = "~/.claude/projects"

      def files
        Dir.glob(File.join(root, "*", "*.jsonl"))
      end

      def parse(path)
        messages = []
        titles = {}
        cwd = nil

        each_json_line(path) do |record|
          case record["type"]
          when "custom-title" then titles[:custom] = record["customTitle"]
          when "ai-title"     then titles[:ai] = record["aiTitle"]
          when "user", "assistant"
            next if machine_generated?(record)
            cwd ||= record["cwd"]
            text = message_text(record)
            messages << Message.new(role: record["type"], text:, created_at: record["timestamp"]) unless text.empty?
          end
        end

        Conversation.new(
          source: SOURCE,
          external_id: File.basename(path, ".jsonl"),
          title: titles[:custom] || titles[:ai] || truncate(messages.find { it.role == "user" }&.text),
          project: cwd,
          started_at: messages.first&.created_at,
          updated_at: messages.last&.created_at,
          path:,
          messages:)
      end

      private
        # Subagent turns, image placeholders, scheduled /loop prompts and context-compaction summaries.
        def machine_generated?(record)
          record["isSidechain"] || record["isMeta"] || record["isCompactSummary"]
        end

        # User prompts arrive as a string or as text blocks; assistant replies as text blocks.
        # Thinking, tool calls and tool results are left out — they're noise for "where did I do X".
        def message_text(record)
          content = record.dig("message", "content")
          text = content.is_a?(String) ? content : Array(content).filter_map { it["text"] if it["type"] == "text" }.join("\n")
          clean(text)
        end
    end
  end
end
