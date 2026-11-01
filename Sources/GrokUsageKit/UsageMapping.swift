import Foundation

enum UsageSnapshotBuilder {
    static func make(
        status: UsageStatusResponse,
        daily: DailyUsageResponse,
        totalsMode: DailyQueryMode,
        now: Date
    ) -> UsageSnapshot {
        let week = UsageWindow.weekRange(periodStart: status.weeklyIncludedUsage.periodStart, now: now)
        let chart = UsageWindow.queryRange(now: now, weeklyPeriodStart: status.weeklyIncludedUsage.periodStart)
        let points = chartPoints(from: daily)
        let totals = sum(points: points, from: week.start, until: week.end)
        let today = UsageWindow.utc.startOfDay(for: now)
        return UsageSnapshot(
            availabilityRaw: combinedAvailability(status: status.availability, daily: daily.availability),
            weeklyUsedCents: status.weeklyIncludedUsage.usedCents,
            weeklyBudgetCents: status.weeklyIncludedUsage.budgetCents,
            weeklyResetAt: status.weeklyIncludedUsage.resetsAt,
            weeklyPeriodStart: status.weeklyIncludedUsage.periodStart,
            weeklyStatus: status.weeklyIncludedStatus.status,
            additionalUsageOff: status.monthlyUsage.additionalUsageOff,
            totalTokens: totals.total,
            includedTokens: totals.included,
            monthlyUsedCents: status.monthlyUsage.usedCents,
            creditsUsedCents: status.monthlyUsage.creditsUsedCents,
            monthlyLimitCents: status.monthlyUsage.limitCents,
            rangeLabel: "This week",
            rangeDetail: UsageFormat.daySpan(from: week.start, through: today),
            rangeStart: week.start,
            rangeEnd: week.end,
            chartStart: chart.start,
            chartEnd: chart.end,
            dailyPoints: points,
            fetchedAt: now,
            totalsMode: totalsMode
        )
    }

    static func makeUnavailable(status: UsageStatusResponse, now: Date) -> UsageSnapshot {
        let week = UsageWindow.weekRange(periodStart: status.weeklyIncludedUsage.periodStart, now: now)
        let chart = UsageWindow.queryRange(now: now, weeklyPeriodStart: status.weeklyIncludedUsage.periodStart)
        let today = UsageWindow.utc.startOfDay(for: now)
        return UsageSnapshot(
            availabilityRaw: status.availability,
            weeklyUsedCents: status.weeklyIncludedUsage.usedCents,
            weeklyBudgetCents: status.weeklyIncludedUsage.budgetCents,
            weeklyResetAt: status.weeklyIncludedUsage.resetsAt,
            weeklyPeriodStart: status.weeklyIncludedUsage.periodStart,
            weeklyStatus: status.weeklyIncludedStatus.status,
            additionalUsageOff: status.monthlyUsage.additionalUsageOff,
            totalTokens: 0,
            includedTokens: 0,
            monthlyUsedCents: status.monthlyUsage.usedCents,
            creditsUsedCents: status.monthlyUsage.creditsUsedCents,
            monthlyLimitCents: status.monthlyUsage.limitCents,
            rangeLabel: "This week",
            rangeDetail: UsageFormat.daySpan(from: week.start, through: today),
            rangeStart: week.start,
            rangeEnd: week.end,
            chartStart: chart.start,
            chartEnd: chart.end,
            dailyPoints: [],
            fetchedAt: now,
            totalsMode: .unfiltered
        )
    }

    static func chartPoints(from daily: DailyUsageResponse) -> [DailyPoint] {
        var points: [DailyPoint] = []
        for series in daily.series {
            let slug = series.dimensions.product
            for point in series.points {
                points.append(
                    DailyPoint(
                        dayStart: point.dayStartTime,
                        productSlug: slug,
                        tokens: point.tokens,
                        includedTokens: point.includedTokens
                    )
                )
            }
        }
        for point in daily.other.points {
            points.append(
                DailyPoint(
                    dayStart: point.dayStartTime,
                    productSlug: "other",
                    tokens: point.tokens,
                    includedTokens: point.includedTokens
                )
            )
        }
        return points
    }

    static func sum(points: [DailyPoint], from start: Date, until end: Date) -> (total: Int64, included: Int64) {
        var total: Int64 = 0
        var included: Int64 = 0
        for point in points where point.dayStart >= start && point.dayStart < end {
            total += point.tokens
            included += point.includedTokens
        }
        return (total, included)
    }

    static func combinedAvailability(status: String, daily: String) -> String {
        if status != "available" { return status }
        return daily
    }
}
