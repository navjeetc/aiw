module Aiw
  # Turns a Recap::Report into lines for the terminal or Markdown. Shared by the printed recap and the
  # interactive browser.
  class RecapView
    RESUME = {
      "Claude Code" => "claude --resume %s",
      "Codex"       => "codex resume %s",
      "Claude"      => "open https://claude.ai/chat/%s",
      "ChatGPT"     => "open https://chatgpt.com/c/%s"
    }

    # How to get back to a conversation, if there's a way. Codex cloud tasks ("task_…") live on the web.
    def self.resume_command(source, id)
      template = source == "Codex" && id.start_with?("task_") ? "open https://chatgpt.com/codex/tasks/%s" : RESUME[source]
      format(template, id) if template
    end

    # How many of your prompts to show under each conversation.
    PROMPTS = 3

    attr_reader :report, :groups

    def initialize(report, color: false)
      @report = report
      @color = color
      # Busiest assistant first; ties go to the most recently active (entries arrive newest first).
      @groups = report.entries.group_by(&:source).each_with_index.sort_by { |(_, entries), index| [ -entries.size, index ] }.map(&:first)
    end

    def header
      bold("#{report.label} · #{pluralize(report.entries.size, "conversation")} in #{pluralize(groups.size, "assistant")}")
    end

    def group_line(source, entries)
      "#{bold(source)} (#{entries.size})  " +
        dim("#{pluralize(entries.sum(&:messages), "message")} · last active #{time(entries.map(&:last_at).max)}")
    end

    def entry_line(entry)
      [ bold(entry.title || "Untitled"), dim(project(entry.project)), pluralize(entry.messages, "message"),
        dim(span(entry.first_at, entry.last_at)) ].compact.join("  ·  ")
    end

    def entry_details(entry)
      lines = entry.prompts.first(PROMPTS).map { "• #{clip(it)}" }
      lines << dim("… and #{pluralize(entry.prompts.size - PROMPTS, "more prompt")}") if entry.prompts.size > PROMPTS
      resume = self.class.resume_command(entry.source, entry.external_id)
      lines << dim(resume) if resume
      lines
    end

    # Everything expanded, as the plain printed recap.
    def lines
      [ header ] + groups.flat_map do |source, entries|
        [ "", "#{bold(source)} (#{entries.size})" ] +
          entries.flat_map { |entry| [ "  #{entry_line(entry)}" ] + entry_details(entry).map { "    #{it}" } }
      end
    end

    def markdown
      [ "## #{report.label}: #{pluralize(report.entries.size, "conversation")} in #{pluralize(groups.size, "assistant")}" ] +
        groups.flat_map do |source, entries|
          [ "", "### #{source}", "" ] + entries.flat_map do |entry|
            [ "- **#{entry.title || "Untitled"}**#{" (#{project(entry.project)})" if entry.project} · " \
              "#{pluralize(entry.messages, "message")} · #{span(entry.first_at, entry.last_at)}" ] +
              entry.prompts.first(PROMPTS).map { "  - #{clip(it)}" }
          end
        end
    end

    private
      def project(path) = (File.basename(path) if path)

      def time(timestamp)
        local = Time.parse(timestamp).localtime
        local.to_date == Date.today ? local.strftime("%H:%M") : local.strftime("%b %-d %H:%M")
      end

      def span(first_at, last_at)
        first, last = Time.parse(first_at).localtime, Time.parse(last_at).localtime
        day = first.to_date == Date.today ? "" : first.strftime("%b %-d ")
        return "#{day}#{first.strftime("%H:%M")}" if (last - first) < 60
        last.to_date == first.to_date ? "#{day}#{first.strftime("%H:%M")}–#{last.strftime("%H:%M")}" :
          "#{day}#{first.strftime("%H:%M")} → #{last.strftime("%b %-d %H:%M")}"
      end

      def clip(text, length = 100) = text.length > length ? "#{text[0, length - 1]}…" : text
      def pluralize(count, word) = "#{count} #{word}#{"s" unless count == 1}"

      # Both return nil for nil so empty fields drop out of a compact join.
      def bold(text) = text && (@color ? "\e[1m#{text}\e[0m" : text)
      def dim(text) = text && (@color ? "\e[2m#{text}\e[0m" : text)
  end
end
