module Aiw
  # A time window from a --since value: 24h, 3d, 1w, today, yesterday or a date like 2026-10-01.
  # Shared by search and recap so both read time the same way.
  class Window < Data.define(:start, :finish, :label)
    UNITS = { "h" => 3600, "d" => 86_400, "w" => 604_800 }
    UNIT_NAMES = { "h" => "hour", "d" => "day", "w" => "week" }

    def self.parse(spec, now: Time.now)
      start, label =
        case spec.to_s.strip.downcase
        when /\A(\d+)\s*([hdw])\z/
          count, unit = $1.to_i, $2
          [ now - count * UNITS[unit], count == 1 ? "Last #{UNIT_NAMES[unit]}" : "Last #{count} #{UNIT_NAMES[unit]}s" ]
        when "today"
          [ midnight(now), "Today" ]
        when "yesterday"
          [ midnight(now) - UNITS["d"], "Since yesterday" ]
        when /\A\d{4}-\d{2}-\d{2}\z/
          date = Time.new(*spec.split("-").map(&:to_i))
          [ date, "Since #{date.strftime('%b %-d')}" ]
        else
          raise ArgumentError, "don't understand --since #{spec.inspect}; try 24h, 3d, 1w, today, yesterday or 2026-10-01"
        end

      new(start:, finish: now, label:)
    end

    def self.midnight(time) = Time.new(time.year, time.month, time.day)

    # Bounds in the format messages are stored in, for comparing in SQL.
    def bounds = [ start.utc.iso8601(3), finish.utc.iso8601(3) ]
  end
end
