require "zip"

module Aiw
  module Importers
    # Reads ChatGPT exports (Settings → Data controls → Export data). Browsers often unzip the download into a
    # folder, so both are accepted in ~/Documents and ~/Downloads, recognized by the chat.html viewer that
    # ships alongside the conversations. Large accounts get conversations-000.json, -001.json, … (older
    # exports: one conversations.json). codex.json holds Codex cloud tasks, which are filed under Codex.
    # Exports are snapshots, so new chats need a fresh export.
    class ChatGPT < Importer
      SOURCE = "ChatGPT"

      FOLDERS = %w[ Documents Downloads ]
      CONVERSATIONS = /\Aconversations(-\d+)?\.json\z/
      ZIP = "*-20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.zip" # ChatGPT names zips <hash>-<date>-<time>….zip

      def self.default_root = "~"

      # Each export is a full snapshot, so only the newest one matters. Browsers often leave both the zip
      # and an unzipped copy; reading both would just do the work twice.
      def files
        latest = (export_folders + FOLDERS.flat_map { Dir.glob(File.join(root, it, ZIP)) }).max_by { exported_at(it) }
        return [] unless latest
        return [ latest ] if latest.end_with?(".zip")

        Dir.children(latest).sort.select { exported_file?(it) }.map { File.join(latest, it) }
      end

      def parse(path)
        if path.end_with?(".zip")
          parse_zip(path)
        else
          conversations_from(File.basename(path), read(path), path)
        end
      end

      private
        def export_folders
          FOLDERS.flat_map { Dir.glob(File.join(root, it, "*", "chat.html")) }.map { File.dirname(it) }
        end

        def exported_file?(name) = name.match?(CONVERSATIONS) || name == "codex.json"

        def exported_at(path) = File.mtime(path.end_with?(".zip") ? path : File.join(path, "chat.html"))

        def parse_zip(path)
          Zip::File.open(path) do |zip|
            next unless zip.find_entry("chat.html")

            zip.entries.select { exported_file?(File.basename(it.name)) }
              .flat_map { conversations_from(File.basename(it.name), it.get_input_stream.read, path) }
          end
        rescue Zip::Error => error
          warn "aiw: could not read #{path}: #{error.message}" if ENV["AIW_DEBUG"]
          nil
        end

        def conversations_from(name, json, path)
          data = JSON.parse(json)
          return [] unless data.is_a?(Array)

          if name == "codex.json"
            data.filter_map { codex_task(it, path) }
          else
            data.filter_map { chat(it, path) if it.is_a?(Hash) && it.key?("mapping") }
          end
        end

        def chat(conversation, path)
          started_at = timestamp(conversation["create_time"])
          messages = active_branch(conversation).filter_map { message_from(it, started_at) }

          Conversation.new(
            source: SOURCE,
            external_id: conversation["conversation_id"] || conversation["id"],
            title: conversation["title"].to_s.strip.empty? ? truncate(messages.find { it.role == "user" }&.text) : conversation["title"].strip,
            project: nil,
            started_at:,
            updated_at: messages.last&.created_at || timestamp(conversation["update_time"]),
            path:,
            messages:)
        end

        # Messages along the branch the chat currently shows (edits create sibling branches), oldest first.
        def active_branch(conversation)
          mapping = conversation["mapping"] || {}
          node_id = conversation["current_node"]
          return mapping.values.filter_map { it["message"] }.sort_by { it["create_time"].to_f } unless mapping[node_id]

          messages = []
          while (node = mapping[node_id])
            messages.unshift(node["message"]) if node["message"]
            node_id = node["parent"]
          end
          messages
        end

        # Plain and multimodal text only; reasoning ("thoughts", "reasoning_recap"), tool calls and
        # custom-instruction messages are left out.
        def message_from(message, fallback_time)
          role = message.dig("author", "role")
          content = message["content"] || {}
          return unless %w[ user assistant ].include?(role) && %w[ text multimodal_text ].include?(content["content_type"])
          return if message.dig("metadata", "is_user_system_message")

          text = clean(Array(content["parts"]).grep(String).join("\n"))
          Message.new(role:, text:, created_at: timestamp(message["create_time"]) || fallback_time) unless text.empty?
        end

        # Cloud tasks carry no timestamps, so they're searchable but stay out of time-based recaps.
        def codex_task(task, path)
          messages = Array(task["turns"]).filter_map do |turn|
            items = turn["role"] == "user" ? turn["input_items"] : turn["output_items"]
            text = clean(Array(items).flat_map { Array(it["content"]) }.filter_map { it["text"] }.join("\n"))
            Message.new(role: turn["role"] == "user" ? "user" : "assistant", text:, created_at: nil) unless text.empty?
          end

          Conversation.new(
            source: "Codex", external_id: task["id"], title: task["title"].to_s.strip.empty? ? truncate(messages.first&.text) : task["title"],
            project: nil, started_at: nil, updated_at: nil, path:, messages:)
        end

        def timestamp(epoch) = (Time.at(epoch.to_f).utc.iso8601(3) if epoch)
    end
  end
end
