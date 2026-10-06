require "json"
require "time"
require "sqlite3"

module Aiw
  Conversation = Data.define(:source, :external_id, :title, :project, :started_at, :updated_at, :path, :messages)
  Message = Data.define(:role, :text, :created_at)

  def self.db_path
    ENV.fetch("AIW_DB") { File.expand_path("~/.aiw/history.sqlite3") }
  end
end

require_relative "aiw/store"
require_relative "aiw/importer"
require_relative "aiw/importers/claude_code"
require_relative "aiw/importers/codex"
require_relative "aiw/importers/grok_bot"
require_relative "aiw/importers/muse"
require_relative "aiw/importers/claude"
require_relative "aiw/importers/chatgpt"
require_relative "aiw/search"
require_relative "aiw/recap"
require_relative "aiw/recap_view"
require_relative "aiw/recap_browser"
require_relative "aiw/cli"
