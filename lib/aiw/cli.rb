require "optparse"

module Aiw
  class CLI
    IMPORTERS = [ Importers::ClaudeCode, Importers::Claude, Importers::Codex, Importers::GrokBot, Importers::Muse ]

    USAGE = <<~TEXT
      Usage:
        aiw search WORDS... [options]   Which assistant did I do this in?
        aiw WORDS...                    Same as search
        aiw import                      Pick up new sessions from every assistant
        aiw rebuild                     Re-read every session from scratch
        aiw recap [--since 3d]          What did I work on lately? (default: last 24 hours)
        aiw stats                       What's in the index

      Options:
    TEXT

    def self.start(argv, out: $stdout) = new(out).run(argv)

    def initialize(out, store: nil, importers: nil)
      @out = out
      @store = store
      @importers = importers
      @color = out.tty? && !ENV["NO_COLOR"]
    end

    def run(argv)
      options = { limit: 20, refresh: true }
      parser = option_parser(options)
      args = parser.parse(argv)
      options[:source] = known_source(options[:source]) if options[:source]

      case args.first
      when nil, "help" then @out.puts parser
      when "import"    then import(verbose: true)
      when "rebuild"   then store.reset.then { import(verbose: true) }
      when "stats"     then stats
      when "recap"     then recap(**options)
      when "search"    then search(args.drop(1).join(" "), **options)
      else                  search(args.join(" "), **options)
      end
    rescue OptionParser::ParseError, ArgumentError => error
      warn "aiw: #{error.message}"
      exit 1
    end

    private
      def option_parser(options)
        OptionParser.new do |o|
          o.banner = USAGE
          o.on("-a", "--apps", "Only list which assistants matched") { options[:apps] = true }
          o.on("-e", "--exact", "Only the exact words, not related forms (packing, not packed)") { options[:exact] = true }
          o.on("-s", "--source NAME", "Only search one assistant, e.g. Codex") { options[:source] = it }
          o.on("-n", "--limit N", Integer, "Max conversations to show (default 20)") { options[:limit] = it }
          o.on("--since SPAN", "Recap window: 24h, 3d, 1w, today, yesterday, 2026-10-01") { options[:since] = it }
          o.on("--markdown", "Recap as Markdown, for notes or a standup") { options[:markdown] = true }
          o.on("--all", "Recap: print everything instead of the collapsible view") { options[:all] = true }
          o.on("--no-import", "Skip the quick refresh first") { options[:refresh] = false }
        end
      end

      def known_source(name)
        sources = IMPORTERS.map { it::SOURCE }
        wanted = name.downcase.delete("^a-z0-9")
        sources.find { it.downcase.delete("^a-z0-9") == wanted } ||
          sources.find { it.downcase.delete("^a-z0-9").start_with?(wanted) } or
          raise ArgumentError, "#{name} isn't indexed yet. aiw currently reads: #{sources.join(", ")}"
      end

      def store
        @store ||= Store.new
      end

      def importers
        @importers ||= IMPORTERS.map(&:new)
      end

      def import(verbose: false)
        importers.each do |importer|
          next unless Dir.exist?(importer.root)

          result = importer.import_into(store)
          if verbose
            @out.puts format("%-12s %4d imported, %4d unchanged%s", importer.class::SOURCE, result.imported, result.skipped,
              result.failed.positive? ? ", #{result.failed} failed (AIW_DEBUG=1 for details)" : "")
          end
        end
      end

      def stats
        rows = store.db.execute(<<~SQL)
          SELECT source, count(*) AS conversations, min(started_at) AS first, max(updated_at) AS last
          FROM conversations GROUP BY source ORDER BY source
        SQL
        return @out.puts("Nothing imported yet. Run: aiw import") if rows.empty?

        rows.each do |row|
          @out.puts format("%-12s %5d conversations  %s → %s",
            row["source"], row["conversations"], date(row["first"]), date(row["last"]))
        end
        @out.puts "\nDatabase: #{Aiw.db_path}"
      end

      def search(query, apps: false, source: nil, limit: 20, exact: false, refresh: true, **)
        return @out.puts("What should I look for? e.g. aiw nginx staging") if query.strip.empty?

        import if refresh
        hits = Search.new(store).call(query, source:, exact:, limit: 1_000)
        return @out.puts("No assistant conversations mention “#{query}”.") if hits.empty?

        tally = hits.map(&:source).tally.sort_by { -it.last }
        @out.puts bold("Found in: ") + tally.map { |name, count| "#{name} (#{count})" }.join(", ")
        return if apps

        shown = hits.first(limit)
        shown.each_with_index do |hit, index|
          if !hit.exact && (index.zero? || shown[index - 1].exact)
            @out.puts dim("\n── Related word forms (use -e for exact words only) ──")
          end
          print_hit(hit)
        end
        @out.puts dim("\n…and #{hits.size - limit} more (show them with -n #{hits.size})") if hits.size > limit
      end

      def recap(since: "24h", source: nil, markdown: false, all: false, refresh: true, **)
        import if refresh
        report = Recap.new(store).call(since:, source:)
        return @out.puts("#{report.label}: no assistant activity.") if report.entries.empty?

        view = RecapView.new(report, color: @color && !markdown)
        if markdown
          @out.puts view.markdown
        elsif interactive? && !all
          RecapBrowser.new(view, color: @color).run(output: @out)
        else
          @out.puts view.lines
        end
      end

      # Only a person at a terminal gets the collapsible view; pipes and files get the full list.
      def interactive?
        @out.tty? && $stdin.tty?
      end

      def print_hit(hit)
        resume = RecapView::RESUME[hit.source]
        @out.puts
        @out.puts [ bold(hit.source.ljust(12)), date(hit.updated_at), dim(project(hit.project)), hit.title ].compact.join("  ")
        @out.puts "  " + highlight(hit.snippet.gsub(/\s+/, " "))
        @out.puts dim("  #{format(resume, hit.external_id)}") if resume
      end

      def project(path)
        File.basename(path) if path
      end

      def date(timestamp)
        Time.parse(timestamp).localtime.strftime("%Y-%m-%d") if timestamp
      rescue ArgumentError
        timestamp
      end

      def highlight(snippet)
        @color ? snippet.gsub("\u0001", "\e[1;33m").gsub("\u0002", "\e[0m") : snippet.delete("\u0001\u0002")
      end

      def bold(text) = text && (@color ? "\e[1m#{text}\e[0m" : text)
      def dim(text) = text && (@color ? "\e[2m#{text}\e[0m" : text)
  end
end
