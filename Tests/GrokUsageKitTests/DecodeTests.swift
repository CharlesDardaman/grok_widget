import XCTest

final class DecodeTests: XCTestCase {
    func testUsageStatusSample() throws {
        let status = try DashboardJSON.decode(UsageStatusResponse.self, from: FixtureLoader.data("usage_status_sample"))
        XCTAssertEqual(status.availability, "available")
        XCTAssertEqual(status.monthlyUsage.usedCents, 0)
        XCTAssertNil(status.monthlyUsage.limitCents)
        XCTAssertFalse(status.monthlyUsage.additionalUsageOff)
        XCTAssertEqual(status.monthlyUsage.creditsUsedCents, 0)
        XCTAssertEqual(status.weeklyIncludedStatus.status, "metered")
        XCTAssertEqual(status.weeklyIncludedUsage.usedCents, 1160)
        XCTAssertEqual(status.weeklyIncludedUsage.budgetCents, 16159)
        XCTAssertEqual(status.weeklyIncludedUsage.resetCounter, 3)
        XCTAssertEqual(
            status.weeklyIncludedUsage.resetsAt,
            DashboardJSON.parseISO8601("2026-11-04T13:10:28.938Z")
        )
        XCTAssertEqual(
            status.weeklyIncludedUsage.periodStart,
            DashboardJSON.parseISO8601("2026-10-28T13:10:28.938Z")
        )
        XCTAssertEqual(UsageFormat.percent(usedCents: 1160, budgetCents: 16159), "7%")
        XCTAssertEqual(UsageFormat.usd(cents: status.monthlyUsage.creditsUsedCents), "$0.00")
    }

    func testDailyUsageSample() throws {
        let daily = try DashboardJSON.decode(DailyUsageResponse.self, from: FixtureLoader.data("daily_usage_sample"))
        XCTAssertEqual(daily.availability, "available")
        XCTAssertEqual(daily.totalContractedCost.value, 0)
        XCTAssertEqual(daily.totalTokens, 33_000_466)
        XCTAssertEqual(daily.totalIncludedTokens, 33_000_466)
        XCTAssertEqual(daily.series.map(\.dimensions.product), ["cursor", "grok-bot", "grok-tasks"])
        XCTAssertEqual(daily.series.map(\.tokenRank), [3, 1, 2])
        XCTAssertEqual(
            daily.series.map { ProductSlug.displayName(for: $0.dimensions.product) },
            ["Cursor", "Grok Bot", "Grok Tasks"]
        )
        XCTAssertEqual(daily.series[0].points[0].tokens, 67_043)
        XCTAssertEqual(daily.series[0].points[0].contractedCost.value, 0)
        XCTAssertEqual(daily.series[1].totalTokens, 32_427_034)
        XCTAssertEqual(daily.series[2].totalTokens, 506_389)
        XCTAssertEqual(daily.other.totalTokens, 0)
        XCTAssertEqual(daily.other.points.count, 1)

        let summed = daily.series.reduce(Int64(0)) { $0 + $1.totalTokens } + daily.other.totalTokens
        XCTAssertEqual(summed, daily.totalTokens)
        let included = daily.series.reduce(Int64(0)) { $0 + $1.totalIncludedTokens } + daily.other.totalIncludedTokens
        XCTAssertEqual(included, daily.totalIncludedTokens)
    }

    func testDecimalStringsRejectNumbers() {
        let data = Data("{\"value\":0}".utf8)
        struct Box: Decodable { var value: JSONDecimal }
        XCTAssertThrowsError(try DashboardJSON.decode(Box.self, from: data))
        let parsed = try? DashboardJSON.decode(Box.self, from: Data("{\"value\":\"0.0000000000\"}".utf8))
        XCTAssertEqual(parsed?.value.value, 0)
        let price = try? DashboardJSON.decode(Box.self, from: Data("{\"value\":\"1.2500000000\"}".utf8))
        XCTAssertEqual(price?.value.value, Decimal(string: "1.25"))
    }

    func testRequestOmitsFiltersUntilSet() throws {
        let unfiltered = DailyUsageRequest(
            startTime: "2026-11-01T00:00:00.000Z",
            endTime: "2026-11-02T00:00:00.000Z",
            filters: nil
        )
        let object = try jsonObject(unfiltered)
        XCTAssertNil(object["filters"])
        XCTAssertEqual(object["scope"] as? String, "user")
        XCTAssertEqual(object["groupBy"] as? [String], ["product"])
        XCTAssertEqual(object["topN"] as? Int, 5)
        XCTAssertEqual(object["startTime"] as? String, "2026-11-01T00:00:00.000Z")

        let filtered = DailyUsageRequest(
            startTime: "2026-11-01T00:00:00.000Z",
            endTime: "2026-11-02T00:00:00.000Z",
            filters: DailyUsageRequest.Filters(usageTypes: ["included", "on-demand"])
        )
        let filteredObject = try jsonObject(filtered)
        let filters = try XCTUnwrap(filteredObject["filters"] as? [String: Any])
        XCTAssertEqual(filters["usageTypes"] as? [String], ["included", "on-demand"])
    }

    func testRequestTimestamp() throws {
        let date = try XCTUnwrap(DashboardJSON.parseISO8601("2026-11-01T00:00:00.000Z"))
        XCTAssertEqual(DashboardJSON.requestTimestamp(date), "2026-11-01T00:00:00.000Z")
    }

    func testEndpointsAreTheCapturedURLs() {
        XCTAssertEqual(
            DashboardEndpoints.usageStatus.absoluteString,
            "https://grok.com/dashboard/api/dashboard/v2/usage-status?scope=user"
        )
        XCTAssertEqual(
            DashboardEndpoints.queryDailyUsage.absoluteString,
            "https://grok.com/dashboard/api/dashboard/v2/query-daily-usage"
        )
        XCTAssertEqual(DashboardEndpoints.referer, "https://grok.com/dashboard/usage")
        XCTAssertEqual(DashboardEndpoints.origin, "https://grok.com")
        XCTAssertTrue(DashboardEndpoints.userAgent.contains("Safari"))
        XCTAssertEqual(DailyFilterAttempt.defaultChain.map(\.mode), [.unfiltered, .includedAndOnDemand, .includedOnly])
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
