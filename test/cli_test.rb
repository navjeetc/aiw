require_relative "test_helper"

class CLITest < Aiw::TestCase
  def test_prints_the_version
    assert_match(/\A\d+\.\d+\.\d+\z/, Aiw::VERSION)

    %w[ -v --version ].each do |flag|
      assert_equal "aiw #{Aiw::VERSION}\n", run_cli(flag), flag
    end
  end

  def test_the_version_wins_over_everything_else
    assert_equal "aiw #{Aiw::VERSION}\n", run_cli("recap", "--since", "1w", "-v")
  end

  def test_help_lists_the_version_flag
    assert_match(/-v, --version\s+Print the version/, run_cli("help"))
  end

  private
    def run_cli(*argv)
      out = StringIO.new
      Aiw::CLI.new(out, store:, importers: []).run(argv)
      out.string
    end
end
