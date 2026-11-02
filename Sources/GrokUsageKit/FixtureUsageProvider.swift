import Foundation

extension UsageSnapshot {
    /// Card values from the grok.com usage dashboard screenshot (October 2026).
    /// Weekly cents are the captured usage-status ratio that rounds to the 7% card.
    /// The daily series is a visual trace of that chart, not a captured payload.
    static let screenshotFetchedAt = DashboardJSON.parseISO8601("2026-10-31T18:06:00.000Z")!

    static let screenshotFixture: UsageSnapshot = {
        let start = UsageWindow.utcDate(year: 2026, month: 10, day: 1)
        let end = UsageWindow.utcDate(year: 2026, month: 11, day: 1)
        let reset = DashboardJSON.parseISO8601("2026-11-04T13:10:28.938Z")!
        let periodStart = DashboardJSON.parseISO8601("2026-10-28T13:10:28.938Z")!
        return UsageSnapshot(
            availabilityRaw: "available",
            weeklyUsedCents: 1160,
            weeklyBudgetCents: 16159,
            weeklyResetAt: reset,
            weeklyPeriodStart: periodStart,
            weeklyStatus: "metered",
            additionalUsageOff: false,
            totalTokens: 967_200_000,
            includedTokens: 874_700_000,
            monthlyUsedCents: 50,
            creditsUsedCents: 50,
            monthlyLimitCents: nil,
            rangeLabel: UsageFormat.daySpan(from: start, through: UsageWindow.utcDate(year: 2026, month: 10, day: 31)),
            rangeDetail: UsageFormat.daySpan(from: start, through: UsageWindow.utcDate(year: 2026, month: 10, day: 31)),
            rangeStart: start,
            rangeEnd: end,
            chartStart: start,
            chartEnd: end,
            dailyPoints: screenshotDailyPoints(),
            fetchedAt: screenshotFetchedAt,
            totalsMode: .unfiltered
        )
    }()

    private static func screenshotDailyPoints() -> [DailyPoint] {
        struct Row {
            var day: Int
            var slug: String
            var tokens: Int64
        }
        // Heights follow the October chart: quiet until the 13th, spikes on the
        // 16th and 26th (Grok Chat), Cursor rising through the last week.
        let rows: [Row] = [
            Row(day: 13, slug: "grok-chat", tokens: 8_000_000),
            Row(day: 13, slug: "cursor", tokens: 1_200_000),
            Row(day: 13, slug: "grok-bot", tokens: 400_000),
            Row(day: 13, slug: "grok-tasks", tokens: 300_000),
            Row(day: 13, slug: "grok-app-builder", tokens: 200_000),
            Row(day: 14, slug: "grok-chat", tokens: 22_000_000),
            Row(day: 14, slug: "cursor", tokens: 2_000_000),
            Row(day: 14, slug: "grok-bot", tokens: 500_000),
            Row(day: 14, slug: "grok-tasks", tokens: 400_000),
            Row(day: 14, slug: "grok-app-builder", tokens: 200_000),
            Row(day: 15, slug: "grok-chat", tokens: 36_000_000),
            Row(day: 15, slug: "cursor", tokens: 4_000_000),
            Row(day: 15, slug: "grok-bot", tokens: 800_000),
            Row(day: 15, slug: "grok-tasks", tokens: 500_000),
            Row(day: 15, slug: "grok-app-builder", tokens: 300_000),
            Row(day: 16, slug: "grok-chat", tokens: 142_000_000),
            Row(day: 16, slug: "cursor", tokens: 3_000_000),
            Row(day: 16, slug: "grok-bot", tokens: 1_200_000),
            Row(day: 16, slug: "grok-tasks", tokens: 800_000),
            Row(day: 16, slug: "grok-app-builder", tokens: 400_000),
            Row(day: 17, slug: "grok-chat", tokens: 48_000_000),
            Row(day: 17, slug: "cursor", tokens: 4_000_000),
            Row(day: 17, slug: "grok-bot", tokens: 600_000),
            Row(day: 17, slug: "grok-tasks", tokens: 400_000),
            Row(day: 17, slug: "grok-app-builder", tokens: 200_000),
            Row(day: 20, slug: "grok-chat", tokens: 6_000_000),
            Row(day: 20, slug: "cursor", tokens: 10_000_000),
            Row(day: 20, slug: "grok-bot", tokens: 400_000),
            Row(day: 20, slug: "grok-tasks", tokens: 300_000),
            Row(day: 20, slug: "grok-app-builder", tokens: 200_000),
            Row(day: 21, slug: "grok-chat", tokens: 10_000_000),
            Row(day: 21, slug: "cursor", tokens: 16_000_000),
            Row(day: 21, slug: "grok-bot", tokens: 500_000),
            Row(day: 21, slug: "grok-tasks", tokens: 400_000),
            Row(day: 21, slug: "grok-app-builder", tokens: 200_000),
            Row(day: 22, slug: "grok-chat", tokens: 30_000_000),
            Row(day: 22, slug: "cursor", tokens: 28_000_000),
            Row(day: 22, slug: "grok-bot", tokens: 800_000),
            Row(day: 22, slug: "grok-tasks", tokens: 600_000),
            Row(day: 22, slug: "grok-app-builder", tokens: 300_000),
            Row(day: 23, slug: "grok-chat", tokens: 26_000_000),
            Row(day: 23, slug: "cursor", tokens: 22_000_000),
            Row(day: 23, slug: "grok-bot", tokens: 700_000),
            Row(day: 23, slug: "grok-tasks", tokens: 500_000),
            Row(day: 23, slug: "grok-app-builder", tokens: 300_000),
            Row(day: 24, slug: "grok-chat", tokens: 8_000_000),
            Row(day: 24, slug: "cursor", tokens: 6_000_000),
            Row(day: 24, slug: "grok-bot", tokens: 400_000),
            Row(day: 24, slug: "grok-tasks", tokens: 300_000),
            Row(day: 24, slug: "grok-app-builder", tokens: 200_000),
            Row(day: 25, slug: "grok-chat", tokens: 12_000_000),
            Row(day: 25, slug: "cursor", tokens: 8_000_000),
            Row(day: 25, slug: "grok-bot", tokens: 400_000),
            Row(day: 25, slug: "grok-tasks", tokens: 400_000),
            Row(day: 25, slug: "grok-app-builder", tokens: 200_000),
            Row(day: 26, slug: "grok-chat", tokens: 152_000_000),
            Row(day: 26, slug: "cursor", tokens: 6_000_000),
            Row(day: 26, slug: "grok-bot", tokens: 1_000_000),
            Row(day: 26, slug: "grok-tasks", tokens: 800_000),
            Row(day: 26, slug: "grok-app-builder", tokens: 400_000),
            Row(day: 27, slug: "grok-chat", tokens: 28_000_000),
            Row(day: 27, slug: "cursor", tokens: 14_000_000),
            Row(day: 27, slug: "grok-bot", tokens: 600_000),
            Row(day: 27, slug: "grok-tasks", tokens: 400_000),
            Row(day: 27, slug: "grok-app-builder", tokens: 200_000),
            Row(day: 28, slug: "grok-chat", tokens: 26_000_000),
            Row(day: 28, slug: "cursor", tokens: 14_000_000),
            Row(day: 28, slug: "grok-bot", tokens: 500_000),
            Row(day: 28, slug: "grok-tasks", tokens: 400_000),
            Row(day: 28, slug: "grok-app-builder", tokens: 200_000),
            Row(day: 29, slug: "grok-chat", tokens: 30_000_000),
            Row(day: 29, slug: "cursor", tokens: 18_000_000),
            Row(day: 29, slug: "grok-bot", tokens: 600_000),
            Row(day: 29, slug: "grok-tasks", tokens: 500_000),
            Row(day: 29, slug: "grok-app-builder", tokens: 200_000),
            Row(day: 30, slug: "grok-chat", tokens: 36_000_000),
            Row(day: 30, slug: "cursor", tokens: 24_000_000),
            Row(day: 30, slug: "grok-bot", tokens: 700_000),
            Row(day: 30, slug: "grok-tasks", tokens: 500_000),
            Row(day: 30, slug: "grok-app-builder", tokens: 300_000),
            Row(day: 31, slug: "grok-chat", tokens: 48_000_000),
            Row(day: 31, slug: "cursor", tokens: 62_000_000),
            Row(day: 31, slug: "grok-bot", tokens: 800_000),
            Row(day: 31, slug: "grok-tasks", tokens: 600_000),
            Row(day: 31, slug: "grok-app-builder", tokens: 300_000),
        ]
        return rows.map { row in
            DailyPoint(
                dayStart: UsageWindow.utcDate(year: 2026, month: 10, day: row.day),
                productSlug: row.slug,
                tokens: row.tokens,
                includedTokens: row.tokens
            )
        }
    }
}
