import XCTest

final class FormatTests: XCTestCase {
    func testTokenFormattingMatchesDashboardCards() {
        XCTAssertEqual(UsageFormat.tokens(967_200_000), "967.2M")
        XCTAssertEqual(UsageFormat.tokens(874_700_000), "874.7M")
        XCTAssertEqual(UsageFormat.tokens(33_000_466), "33.0M")
        XCTAssertEqual(UsageFormat.tokens(1_000_000), "1.0M")
        XCTAssertEqual(UsageFormat.tokens(1_500_000_000), "1.5B")
        XCTAssertEqual(UsageFormat.tokens(12_300), "12.3K")
        XCTAssertEqual(UsageFormat.tokens(1_000), "1.0K")
        XCTAssertEqual(UsageFormat.tokens(999), "999")
        XCTAssertEqual(UsageFormat.tokens(0), "0")
        XCTAssertEqual(UsageFormat.tokens(999_950_000), "1.0B")
    }

    func testWeeklyPercentRoundsLikeTheDashboard() {
        XCTAssertEqual(UsageFormat.percent(usedCents: 1160, budgetCents: 16159), "7%")
        XCTAssertEqual(UsageFormat.percentOneDecimal(usedCents: 1160, budgetCents: 16159), "7.2%")
        XCTAssertEqual(UsageFormat.percent(usedCents: 0, budgetCents: 0), "—")
        let fraction = Double(1160) / Double(16159)
        XCTAssertEqual(fraction, 1160.0 / 16159.0, accuracy: 0.0000001)
    }

    func testResetDate() throws {
        let reset = try XCTUnwrap(DashboardJSON.parseISO8601("2026-11-04T13:10:28.938Z"))
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let chicago = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        XCTAssertEqual(UsageFormat.resetDate(reset, timeZone: utc), "Nov 4")
        XCTAssertEqual(UsageFormat.resetDate(reset, timeZone: chicago), "Nov 4")

        let early = try XCTUnwrap(DashboardJSON.parseISO8601("2026-11-04T02:00:00.000Z"))
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(UsageFormat.resetDate(early, timeZone: utc), "Nov 4")
        XCTAssertEqual(UsageFormat.resetDate(early, timeZone: losAngeles), "Nov 3")
    }

    func testCreditCurrency() {
        XCTAssertEqual(UsageFormat.usd(cents: 50), "$0.50")
        XCTAssertEqual(UsageFormat.usd(cents: 0), "$0.00")
        XCTAssertEqual(UsageFormat.usd(cents: 12345), "$123.45")
    }

    func testDaySpanAndLastUpdated() throws {
        let start = UsageWindow.utcDate(year: 2026, month: 10, day: 28)
        let end = UsageWindow.utcDate(year: 2026, month: 11, day: 1)
        XCTAssertEqual(UsageFormat.daySpan(from: start, through: end), "Oct 28 – Nov 1")
        XCTAssertEqual(UsageFormat.daySpan(from: start, through: start), "Oct 28")

        let fetched = try XCTUnwrap(DashboardJSON.parseISO8601("2026-10-31T18:06:00.000Z"))
        let now = try XCTUnwrap(DashboardJSON.parseISO8601("2026-11-01T12:00:00.000Z"))
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        XCTAssertEqual(UsageFormat.lastUpdated(fetched, now: now, timeZone: utc), "Updated Oct 31, 6:06 PM")
        XCTAssertEqual(UsageFormat.lastUpdated(now, now: now, timeZone: utc), "Updated 12:00 PM")
    }

    func testProductNames() {
        XCTAssertEqual(ProductSlug.displayName(for: "cursor"), "Cursor")
        XCTAssertEqual(ProductSlug.displayName(for: "grok-bot"), "Grok Bot")
        XCTAssertEqual(ProductSlug.displayName(for: "grok-tasks"), "Grok Tasks")
        XCTAssertEqual(ProductSlug.displayName(for: "grok-chat"), "Grok Chat")
        XCTAssertEqual(ProductSlug.displayName(for: "grok-app-builder"), "Grok App Builder")
        XCTAssertEqual(ProductSlug.displayName(for: "other"), "Other")
        XCTAssertEqual(ProductSlug.displayName(for: "brand-new-surface"), "Brand New Surface")
        XCTAssertEqual(ProductSlug.displayName(for: ""), "Unknown")
    }

    func testScreenshotFixtureMatchesCards() {
        let snapshot = UsageSnapshot.screenshotFixture
        XCTAssertEqual(UsageSummary.line(for: snapshot), "Oct 1 – Oct 31: 7% weekly, 967.2M total, 874.7M included, $0.50 credit")
        XCTAssertEqual(snapshot.weeklyUsedCents, 1160)
        XCTAssertEqual(snapshot.weeklyBudgetCents, 16159)
        XCTAssertEqual(snapshot.creditsUsedCents, 50)
        XCTAssertNil(snapshot.monthlyLimitCents)
        XCTAssertEqual(snapshot.weeklyStatus, "metered")
        XCTAssertEqual(UsageFormat.resetDate(snapshot.weeklyResetAt, timeZone: TimeZone(secondsFromGMT: 0)!), "Nov 4")
        XCTAssertEqual(tokens(on: 16, slug: "grok-chat"), 142_000_000)
        XCTAssertEqual(tokens(on: 26, slug: "grok-chat"), 152_000_000)
        XCTAssertGreaterThan(tokens(on: 31, slug: "cursor"), 40_000_000)
        XCTAssertTrue(snapshot.isAvailable)
    }

    func testRefreshInterval() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(UsageRefresh.nextRefresh(after: now).timeIntervalSince(now), 15 * 60)
        XCTAssertFalse(UsageRefresh.isStale(fetchedAt: now.addingTimeInterval(-10 * 60), now: now))
        XCTAssertTrue(UsageRefresh.isStale(fetchedAt: now.addingTimeInterval(-30 * 60), now: now))
    }

    private func tokens(on day: Int, slug: String) -> Int64 {
        UsageSnapshot.screenshotFixture.dailyPoints
            .filter { point in
                let components = UsageWindow.utc.dateComponents([.day], from: point.dayStart)
                return components.day == day && point.productSlug == slug
            }
            .reduce(0) { $0 + $1.tokens }
    }
}
