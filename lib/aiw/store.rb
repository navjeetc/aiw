require "fileutils"

module Aiw
  # SQLite database holding every imported conversation, with an FTS5 index over message text.
  class Store
    attr_reader :db

    def initialize(path = Aiw.db_path)
      FileUtils.mkdir_p(File.dirname(path)) unless path == ":memory:"
      @db = SQLite3::Database.new(path)
      @db.results_as_hash = true
      @db.busy_timeout = 5000
      migrate
    end

    # Files are only re-read when their size or mtime changed since the last import.
    def unchanged?(path, stat)
      row = db.get_first_row("SELECT size, mtime FROM files WHERE path = ?", [ path ])
      row && row["size"] == stat.size && row["mtime"] == stat.mtime.to_i
    end

    # Remembers files that held nothing worth indexing too, so they aren't re-read on every search.
    def seen(path, stat)
      db.execute(<<~SQL, [ path, stat.size, stat.mtime.to_i ])
        INSERT INTO files (path, size, mtime) VALUES (?, ?, ?)
        ON CONFLICT (path) DO UPDATE SET size = excluded.size, mtime = excluded.mtime
      SQL
    end

    def save(conversation)
      db.transaction do
        existing = db.get_first_value(
          "SELECT id FROM conversations WHERE source = ? AND external_id = ?",
          [ conversation.source, conversation.external_id ])
        db.execute("DELETE FROM messages WHERE conversation_id = ?", [ existing ]) if existing

        db.execute(<<~SQL, conversation.to_h.values_at(:source, :external_id, :title, :project, :started_at, :updated_at, :path))
          INSERT INTO conversations (source, external_id, title, project, started_at, updated_at, path)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT (source, external_id) DO UPDATE SET
            title = excluded.title, project = excluded.project, started_at = excluded.started_at,
            updated_at = excluded.updated_at, path = excluded.path
        SQL
        id = existing || db.last_insert_row_id

        index(id, "title", conversation.title, conversation.started_at) if conversation.title
        conversation.messages.each { |message| index(id, message.role, message.text, message.created_at) }
      end
    end

    # Forgets everything so the next import re-reads every file, e.g. after an importer learns new tricks.
    def reset
      db.execute_batch("DELETE FROM messages; DELETE FROM conversations; DELETE FROM files;")
    end

    private
      def migrate
        db.execute_batch(<<~SQL)
          CREATE TABLE IF NOT EXISTS conversations (
            id INTEGER PRIMARY KEY,
            source TEXT NOT NULL,
            external_id TEXT NOT NULL,
            title TEXT,
            project TEXT,
            started_at TEXT,
            updated_at TEXT,
            path TEXT,
            UNIQUE (source, external_id)
          );

          CREATE TABLE IF NOT EXISTS files (
            path TEXT PRIMARY KEY,
            size INTEGER NOT NULL,
            mtime INTEGER NOT NULL
          );

          CREATE VIRTUAL TABLE IF NOT EXISTS messages USING fts5(
            text,
            role UNINDEXED,
            conversation_id UNINDEXED,
            created_at UNINDEXED,
            tokenize = 'porter unicode61'
          );
        SQL
      end

      def index(conversation_id, role, text, created_at)
        db.execute("INSERT INTO messages (text, role, conversation_id, created_at) VALUES (?, ?, ?, ?)",
          [ text, role, conversation_id, created_at ])
      end
  end
end
