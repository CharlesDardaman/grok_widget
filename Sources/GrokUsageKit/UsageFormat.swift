import Foundation

enum UsageFormat {
    /// Dashboard style: `967.2M`, `33.0M`, `12.3K`. Values under 1,000 stay integers.
    static func tokens(_ value: Int64) -> String {
        let negative = value < 0
        let magnitude: Double
        if value == Int64.min {
            magnitude = Double(Int64.max)
        } else {
            magnitude = Double(negative ? -value : value)
        }
        let body = scaledTokens(magnitude)
        return negative ? "-" + body : body
    }

    /// Whole percent, matching the dashboard card. 1160/16159 displays as `7%`.
    static func percent(usedCents: Int, budgetCents: Int) -> String {
        guard budgetCents > 0 else { return "—" }
        let value = (Double(usedCents) / Double(budgetCents)) * 100
        return "\(Int(value.rounded()))%"
    }

    /// One decimal, so 1160/16159 is `7.2%`.
    static func percentOneDecimal(usedCents: Int, budgetCents: Int) -> String {
        guard budgetCents > 0 else { return "—" }
        let value = (Double(usedCents) / Double(budgetCents)) * 100
        return oneDecimal(value) + "%"
    }

    static func usd(cents: Int) -> String {
        let dollars = NSDecimalNumber(value: cents).dividing(by: NSDecimalNumber(value: 100))
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        formatter.currencyCode = "USD"
        return formatter.string(from: dollars) ?? "$0.00"
    }

    static func resetDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    static func daySpan(from start: Date, through end: Date, timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!) -> String {
        let startText = resetDate(start, timeZone: timeZone)
        let endText = resetDate(end, timeZone: timeZone)
        if startText == endText { return startText }
        return "\(startText) – \(endText)"
    }

    static func lastUpdated(_ date: Date, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "h:mm a"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
        }
        return "Updated \(formatter.string(from: date))"
    }

    private static func scaledTokens(_ magnitude: Double) -> String {
        let units: [(threshold: Double, divisor: Double, suffix: String)] = [
            (1_000_000_000, 1_000_000_000, "B"),
            (1_000_000, 1_000_000, "M"),
            (1_000, 1_000, "K"),
        ]
        for (index, unit) in units.enumerated() where magnitude >= unit.threshold {
            let scaled = magnitude / unit.divisor
            if scaled >= 999.95, index > 0 {
                let larger = units[index - 1]
                return oneDecimal(magnitude / larger.divisor) + larger.suffix
            }
            return oneDecimal(scaled) + unit.suffix
        }
        return String(Int(magnitude.rounded()))
    }

    private static func oneDecimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}

enum ProductSlug {
    static let stackOrder = ["grok-chat", "grok-bot", "grok-app-builder", "grok-tasks", "cursor", "other"]

    static func shortName(for slug: String) -> String {
        switch slug {
        case "grok-chat":
            return "Chat"
        case "grok-bot":
            return "Bot"
        case "grok-app-builder":
            return "Builder"
        case "grok-tasks":
            return "Tasks"
        case "cursor":
            return "Cursor"
        case "other":
            return "Other"
        default:
            return displayName(for: slug)
        }
    }

    static func displayName(for slug: String) -> String {
        switch slug {
        case "cursor":
            return "Cursor"
        case "grok-bot":
            return "Grok Bot"
        case "grok-tasks":
            return "Grok Tasks"
        case "grok-chat":
            return "Grok Chat"
        case "grok-app-builder":
            return "Grok App Builder"
        case "other":
            return "Other"
        default:
            if slug.isEmpty { return "Unknown" }
            return slug.split(separator: "-").map { part in
                guard let first = part.first else { return "" }
                return String(first).uppercased() + part.dropFirst().lowercased()
            }.joined(separator: " ")
        }
    }

    static func sortIndex(_ slug: String) -> Int {
        stackOrder.firstIndex(of: slug) ?? (stackOrder.count + 1)
    }
}

enum UsageSummary {
    static func line(for snapshot: UsageSnapshot) -> String {
        guard snapshot.isAvailable else {
            return "Usage unavailable (\(snapshot.availabilityRaw))."
        }
        let weekly = UsageFormat.percent(usedCents: snapshot.weeklyUsedCents, budgetCents: snapshot.weeklyBudgetCents)
        let total = UsageFormat.tokens(snapshot.totalTokens)
        let included = UsageFormat.tokens(snapshot.includedTokens)
        let credit = UsageFormat.usd(cents: snapshot.creditsUsedCents)
        return "\(snapshot.rangeLabel): \(weekly) weekly, \(total) total, \(included) included, \(credit) credit"
    }
}
