import Foundation

enum UsageWindow {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static func utcDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = utc
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        guard let date = components.date else {
            preconditionFailure("Invalid UTC date \(year)-\(month)-\(day)")
        }
        return date
    }

    /// Inclusive UTC midnight through the exclusive midnight after `now`'s UTC day.
    /// The start reaches back `sparklineDays` and also covers the weekly period
    /// when that period began earlier.
    static func queryRange(now: Date, weeklyPeriodStart: Date, sparklineDays: Int = 14) -> DateInterval {
        let today = utc.startOfDay(for: now)
        let daysBack = max(sparklineDays - 1, 0)
        let sparklineStart = utc.date(byAdding: .day, value: -daysBack, to: today) ?? today
        let periodDay = utc.startOfDay(for: weeklyPeriodStart)
        let start = min(sparklineStart, periodDay)
        let end = utc.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        if end <= start {
            return DateInterval(start: start, duration: 86_400)
        }
        return DateInterval(start: start, end: end)
    }

    /// UTC days that overlap the weekly included period, through the end of `now`'s UTC day.
    /// Daily buckets are midnight-aligned, so the period's first partial day is included.
    static func weekRange(periodStart: Date, now: Date) -> DateInterval {
        let start = utc.startOfDay(for: periodStart)
        let today = utc.startOfDay(for: now)
        let end = utc.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        if end <= start {
            return DateInterval(start: start, duration: 86_400)
        }
        return DateInterval(start: start, end: end)
    }
}
