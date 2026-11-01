import XCTest

final class MappingTests: XCTestCase {
    func testSamplesMapOntoThisWeek() throws {
        let status = try DashboardJSON.decode(UsageStatusResponse.self, from: FixtureLoader.data("usage_status_sample"))
        let daily = try DashboardJSON.decode(DailyUsageResponse.self, from: FixtureLoader.data("daily_usage_sample"))
        let now = try XCTUnwrap(DashboardJSON.parseISO8601("2026-11-01T18:00:00.000Z"))
        let snapshot = UsageSnapshotBuilder.make(status: status, daily: daily, totalsMode: .unfiltered, now: now)

        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.rangeLabel, "This week")
        XCTAssertEqual(snapshot.rangeDetail, "Oct 28 – Nov 1")
        XCTAssertEqual(snapshot.totalTokens, 33_000_466)
        XCTAssertEqual(snapshot.includedTokens, 33_000_466)
        XCTAssertEqual(UsageFormat.tokens(snapshot.totalTokens), "33.0M")
        XCTAssertEqual(snapshot.weeklyStatus, "metered")
        XCTAssertEqual(snapshot.creditsUsedCents, 0)
        XCTAssertEqual(snapshot.monthlyUsedCents, 0)
        XCTAssertNil(snapshot.monthlyLimitCents)
        XCTAssertEqual(UsageFormat.percent(usedCents: snapshot.weeklyUsedCents, budgetCents: snapshot.weeklyBudgetCents), "7%")
        XCTAssertEqual(
            Set(snapshot.dailyPoints.map(\.productSlug)),
            ["cursor", "grok-bot", "grok-tasks", "other"]
        )
        XCTAssertEqual(snapshot.totalsMode, .unfiltered)
        XCTAssertNil(snapshot.totalsModeCaption)
    }

    func testWeeklySumSkipsDaysOutsideThePeriodAndKeepsIncludedSeparate() throws {
        let status = try DashboardJSON.decode(UsageStatusResponse.self, from: FixtureLoader.data("usage_status_sample"))
        let beforeDay = UsageWindow.utcDate(year: 2026, month: 10, day: 19)
        let insideDay = UsageWindow.utcDate(year: 2026, month: 11, day: 1)
        let series = DailyUsageSeries(
            dimensions: DailyUsageSeries.Dimensions(product: "cursor"),
            costRank: 1,
            tokenRank: 1,
            totalContractedCost: JSONDecimal(0),
            totalTokens: 15_000_000,
            totalIncludedTokens: 5_000_000,
            points: [
                DailyUsagePoint(dayStartTime: beforeDay, contractedCost: JSONDecimal(0), tokens: 5_000_000, includedTokens: 1_000_000),
                DailyUsagePoint(dayStartTime: insideDay, contractedCost: JSONDecimal(Decimal(string: "1.25")!), tokens: 10_000_000, includedTokens: 4_000_000),
            ]
        )
        let daily = DailyUsageResponse(
            availability: "available",
            startTime: beforeDay,
            endTime: UsageWindow.utcDate(year: 2026, month: 11, day: 2),
            totalContractedCost: JSONDecimal(0),
            totalTokens: 15_000_150,
            totalIncludedTokens: 5_000_090,
            series: [series],
            other: DailyUsageOther(
                totalContractedCost: JSONDecimal(0),
                totalTokens: 150,
                totalIncludedTokens: 90,
                points: [
                    DailyUsagePoint(dayStartTime: beforeDay, contractedCost: JSONDecimal(0), tokens: 50, includedTokens: 50),
                    DailyUsagePoint(dayStartTime: insideDay, contractedCost: JSONDecimal(0), tokens: 100, includedTokens: 40),
                ]
            )
        )
        let now = try XCTUnwrap(DashboardJSON.parseISO8601("2026-11-01T18:00:00.000Z"))
        let snapshot = UsageSnapshotBuilder.make(status: status, daily: daily, totalsMode: .includedOnly, now: now)
        XCTAssertEqual(snapshot.totalTokens, 10_000_100)
        XCTAssertEqual(snapshot.includedTokens, 4_000_040)
        XCTAssertEqual(snapshot.totalsModeCaption, "Query filter: included only")
        XCTAssertNotEqual(snapshot.totalTokens, snapshot.includedTokens)
    }

    func testNonAvailableStatusBecomesUnavailable() throws {
        var status = try DashboardJSON.decode(UsageStatusResponse.self, from: FixtureLoader.data("usage_status_sample"))
        status.availability = "maintenance"
        let now = try XCTUnwrap(DashboardJSON.parseISO8601("2026-11-01T18:00:00.000Z"))
        let snapshot = UsageSnapshotBuilder.makeUnavailable(status: status, now: now)
        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertEqual(snapshot.availabilityRaw, "maintenance")
        XCTAssertTrue(snapshot.dailyPoints.isEmpty)
        XCTAssertEqual(UsageSummary.line(for: snapshot), "Usage unavailable (maintenance).")
    }

    func testQueryWindowCoversFourteenDaysAndTheWeeklyPeriod() throws {
        let now = try XCTUnwrap(DashboardJSON.parseISO8601("2026-11-01T18:00:00.000Z"))
        let period = try XCTUnwrap(DashboardJSON.parseISO8601("2026-10-28T13:10:28.938Z"))
        let range = UsageWindow.queryRange(now: now, weeklyPeriodStart: period)
        XCTAssertEqual(range.start, UsageWindow.utcDate(year: 2026, month: 10, day: 19))
        XCTAssertEqual(range.end, UsageWindow.utcDate(year: 2026, month: 11, day: 2))

        let earlyPeriod = UsageWindow.utcDate(year: 2026, month: 10, day: 1)
        let extended = UsageWindow.queryRange(now: now, weeklyPeriodStart: earlyPeriod)
        XCTAssertEqual(extended.start, earlyPeriod)

        let week = UsageWindow.weekRange(periodStart: period, now: now)
        XCTAssertEqual(week.start, UsageWindow.utcDate(year: 2026, month: 10, day: 28))
        XCTAssertEqual(week.end, UsageWindow.utcDate(year: 2026, month: 11, day: 2))
    }

    func testLoginURLsAndCookieNormalization() {
        XCTAssertTrue(RedirectPolicy.isLogin(URL(string: "https://grok.com/login")))
        XCTAssertTrue(RedirectPolicy.isLogin(URL(string: "https://accounts.x.ai/sign-in")))
        XCTAssertFalse(RedirectPolicy.isLogin(URL(string: "https://grok.com/dashboard/api/dashboard/v2/usage-status")))
        XCTAssertEqual(CookieHeader.normalize("  Cookie: session=abc  "), "session=abc")
        XCTAssertEqual(CookieHeader.normalize("session=abc"), "session=abc")
    }

    func testRedactsCookieFromMessages() {
        let cookie = "sso=super-secret-value"
        let text = UsageFetchError.redact("failed for \(cookie)", cookie: cookie)
        XCTAssertFalse(text.contains("super-secret"))
        XCTAssertTrue(text.contains("[redacted]"))
        XCTAssertTrue(UsageFetchError.sessionExpired.localizedDescription.contains("Re-paste"))
        XCTAssertFalse(UsageFetchError.sessionExpired.localizedDescription.contains(cookie))
    }
}
