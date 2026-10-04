require "set"

module Aiw
  # Interactive recap: assistants start collapsed; expand one to see its conversations, and collapse a
  # conversation to hide its prompts. The state machine (#handle, #screen) is separate from the terminal
  # loop (#run) so it can be tested without a terminal.
  class RecapBrowser
    Row = Data.define(:text, :key) # key is [group] or [group, entry] for rows the cursor can land on

    HELP = "↑↓ move · enter/space expand or collapse · ←→ close/open · a all · q quit"

    KEYS = {
      "\e[A" => :up, "\eOA" => :up, "k" => :up,
      "\e[B" => :down, "\eOB" => :down, "j" => :down,
      "\e[C" => :right, "\eOC" => :right, "l" => :right,
      "\e[D" => :left, "\eOD" => :left, "h" => :left,
      "\r" => :toggle, "\n" => :toggle, " " => :toggle,
      "a" => :all, "q" => :quit, "\e" => :quit, "\u0003" => :quit
    }

    def initialize(view, color: false)
      @view = view
      @color = color
      @open_groups = Set.new
      @closed_entries = Set.new
      @cursor = [ 0 ]
      @scroll = 0
    end

    def run(input: $stdin, output: $stdout)
      require "io/console"
      output.print "\e[?1049h\e[?25l" # alternate screen, hide cursor
      loop do
        height, width = output.winsize
        output.print "\e[H" + screen(height, width).map { "#{it}\e[K" }.join("\r\n") + "\e[J"
        break if handle(read_key(input)) == :quit
      end
    ensure
      output.print "\e[?25h\e[?1049l"
    end

    def handle(key)
      case KEYS.fetch(key, key)
      when :up     then move(-1)
      when :down   then move(1)
      when :toggle then toggle
      when :right  then open
      when :left   then close
      when :all    then toggle_all
      when :quit   then return :quit
      end
      nil
    end

    def rows
      [ Row.new(@view.header, nil), Row.new("", nil) ] +
        @view.groups.each_with_index.flat_map do |(source, entries), group|
          opened = @open_groups.include?(group)
          [ Row.new("#{opened ? "▾" : "▸"} #{@view.group_line(source, entries)}", [ group ]) ] +
            (opened ? entries.each_with_index.flat_map { |entry, index| entry_rows(entry, group, index) } : [])
        end
    end

    # The visible window: keeps the cursor on screen and, when there's room, the details under it too.
    def screen(height, width)
      rows = self.rows
      body = [ height - 1, 1 ].max
      current = rows.index { it.key == @cursor }
      extent = current
      extent += 1 while rows[extent + 1] && rows[extent + 1].key.nil?

      @scroll = extent - body + 1 if extent >= @scroll + body
      @scroll = current if current < @scroll
      @scroll = @scroll.clamp(0, [ rows.size - body, 0 ].max)

      lines = rows[@scroll, body].map { |row| fit("#{row.key == @cursor ? marker : "  "}#{row.text}", width) }
      lines.fill("", lines.size...body) + [ fit(dim(HELP), width) ]
    end

    private
      def entry_rows(entry, group, index)
        details = @closed_entries.include?([ group, index ]) ? [] : @view.entry_details(entry)
        [ Row.new("    #{@view.entry_line(entry)}", [ group, index ]) ] + details.map { Row.new("      #{it}", nil) }
      end

      def move(step)
        keys = rows.filter_map(&:key)
        @cursor = keys[(keys.index(@cursor) + step).clamp(0, keys.size - 1)]
      end

      def toggle
        group, entry = @cursor
        if entry
          toggle_in(@closed_entries, @cursor)
        else
          toggle_in(@open_groups, group)
        end
      end

      def open
        group, entry = @cursor
        entry ? @closed_entries.delete(@cursor) : @open_groups.add(group)
      end

      # On a conversation, ← jumps back to its assistant and folds it.
      def close
        group, = @cursor
        @open_groups.delete(group)
        @cursor = [ group ]
      end

      def toggle_all
        if @open_groups.size == @view.groups.size
          @open_groups.clear
          @cursor = [ @cursor.first ]
        else
          @open_groups.merge(0...@view.groups.size)
        end
      end

      def toggle_in(set, item) = set.include?(item) ? set.delete(item) : set.add(item)

      def read_key(input)
        input.raw do |io|
          key = io.getc
          if key == "\e" && IO.select([ io ], nil, nil, 0.03) # arrow keys arrive as escape sequences
            rest = io.read_nonblock(8, exception: false)
            key += rest if rest.is_a?(String)
          end
          key
        end
      end

      # Cuts a line to the terminal width without counting color codes, so nothing wraps.
      def fit(line, width)
        visible = 0
        out = +""
        line.scan(/\e\[[\d;?]*[A-Za-z]|./m) do |token|
          if token.start_with?("\e[")
            out << token
          elsif visible < width - 1
            out << token
            visible += 1
          else
            return out + (@color ? "…\e[0m" : "…")
          end
        end
        out
      end

      def marker = @color ? "\e[36m❯\e[0m " : "> "
      def dim(text) = @color ? "\e[2m#{text}\e[0m" : text
  end
end
