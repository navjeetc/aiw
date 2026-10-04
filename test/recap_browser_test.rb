require_relative "test_helper"

class RecapBrowserTest < Aiw::TestCase
  def setup
    import_fixtures
    Aiw::Importers::GrokBot.new(File.join(FIXTURES, "grok_bot")).import_into(store)
    report = Aiw::Recap.new(store, now: Time.utc(2026, 8, 31)).call(since: "2026-07-01")
    @browser = Aiw::RecapBrowser.new(Aiw::RecapView.new(report))
  end

  def test_starts_with_every_assistant_collapsed
    assert_equal [ "> ▸ Grok Bot (1)", "  ▸ Codex (1)", "  ▸ Claude Code (1)" ], assistants
    refute_includes screen, "Lisbon"
  end

  def test_expands_one_assistant_at_a_time
    press "j", "\r"

    assert_includes screen, "> ▾ Codex (1)"
    assert_includes screen, "Rotate load balancer certs"
    refute_includes screen, "Nginx staging setup"
  end

  def test_collapses_again
    press "\r", "\r"

    refute_includes screen, "Find a hotel in Lisbon"
  end

  def test_moves_through_conversations_and_hides_their_prompts
    press "\r", "j"
    assert_includes screen, ">     Travel"
    assert_includes screen, "• Find a hotel in Lisbon near Alfama for October"

    press " "
    refute_includes screen, "• Find a hotel in Lisbon"
  end

  def test_left_arrow_folds_back_to_the_assistant
    press "\e[C", "\e[B", "\e[D"

    assert_equal "> ▸ Grok Bot (1)", assistants.first
  end

  def test_expands_and_collapses_everything
    press "a"
    assert_equal 3, assistants.count { it.include?("▾") }

    press "a"
    assert_equal 0, assistants.count { it.include?("▾") }
  end

  def test_scrolls_to_keep_the_cursor_on_screen
    press "a", *[ "j" ] * 5

    lines = @browser.screen(4, 80)
    assert lines.any? { it.start_with?("> ") }, "cursor scrolled out of view: #{lines.inspect}"
  end

  def test_fits_lines_to_the_terminal_width
    assert @browser.screen(20, 12).all? { it.length <= 12 }
  end

  def test_quits
    assert_equal :quit, @browser.handle("q")
    assert_equal :quit, @browser.handle("\u0003")
  end

  private
    def press(*keys) = keys.each { @browser.handle(it) }

    def screen = @browser.screen(40, 200).join("\n")

    def assistants
      @browser.screen(40, 200).grep(/[▸▾]/).map { it.sub(/\)\s.*/, ")") }
    end
end
