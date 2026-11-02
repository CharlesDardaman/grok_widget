import Foundation

enum DailyQueryMode: String, Codable, Equatable, Sendable {
    /// No `filters` object. Total tokens can include on-demand usage.
    case unfiltered
    /// Explicit `usageTypes` of included and on-demand, used if the server rejects a missing filter.
    case includedAndOnDemand
    /// Included usage only. Totals may match included tokens.
    case includedOnly
}

struct DailyFilterAttempt: Equatable, Sendable {
    var mode: DailyQueryMode
    var usageTypes: [String]?

    /// Unfiltered first, then the two explicit filters. Adjust the on-demand
    /// slug here if a captured 400 shows a different accepted value.
    static let defaultChain: [DailyFilterAttempt] = [
        DailyFilterAttempt(mode: .unfiltered, usageTypes: nil),
        DailyFilterAttempt(mode: .includedAndOnDemand, usageTypes: ["included", "on-demand"]),
        DailyFilterAttempt(mode: .includedOnly, usageTypes: ["included"]),
    ]
}

struct DailyPoint: Codable, Equatable, Sendable, Identifiable {
    var dayStart: Date
    var productSlug: String
    var tokens: Int64
    var includedTokens: Int64

    var id: String { "\(productSlug)|\(dayStart.timeIntervalSinceReferenceDate)" }

    var productName: String { ProductSlug.displayName(for: productSlug) }
}

struct UsageSnapshot: Codable, Equatable, Sendable {
    var availabilityRaw: String
    var weeklyUsedCents: Int
    var weeklyBudgetCents: Int
    var weeklyResetAt: Date
    var weeklyPeriodStart: Date
    var weeklyStatus: String?
    var additionalUsageOff: Bool
    var totalTokens: Int64
    var includedTokens: Int64
    /// `monthlyUsage.usedCents`. Shown when it differs from credit usage.
    var monthlyUsedCents: Int
    /// `monthlyUsage.creditsUsedCents`. Primary "Credit usage" dollar amount.
    var creditsUsedCents: Int
    var monthlyLimitCents: Int?
    /// Short label for the totals, such as "This week" or "Oct 1 – Oct 31".
    var rangeLabel: String
    /// Concrete dates covered by the totals.
    var rangeDetail: String
    var rangeStart: Date
    var rangeEnd: Date
    var chartStart: Date
    var chartEnd: Date
    var dailyPoints: [DailyPoint]
    var fetchedAt: Date
    var totalsMode: DailyQueryMode

    var isAvailable: Bool { availabilityRaw == "available" }

    var weeklyFraction: Double {
        guard weeklyBudgetCents > 0 else { return 0 }
        let fraction = Double(weeklyUsedCents) / Double(weeklyBudgetCents)
        if fraction.isNaN || fraction.isInfinite { return 0 }
        return fraction
    }

    var totalsModeCaption: String? {
        switch totalsMode {
        case .unfiltered:
            return nil
        case .includedAndOnDemand:
            return "Query filter: included + on-demand"
        case .includedOnly:
            return "Query filter: included only"
        }
    }
}

enum UsagePresentation: Equatable, Sendable {
    case fresh
    case stale
    case loading
    case unavailable
    case needsCookie
    case sessionExpired
    case failed(String)
}
