import XCTest

final class ProviderTests: XCTestCase {
    private let cookie = "session=test-fixture"

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testHeadersAndUnfilteredBody() throws {
        let configuration = URLSessionConfiguration.ephemeral
        let client = DashboardClient(cookieHeader: cookie, sessionConfiguration: configuration)
        let status = client.makeUsageStatusRequest()
        XCTAssertEqual(status.httpMethod, "GET")
        XCTAssertEqual(status.value(forHTTPHeaderField: "Cookie"), cookie)
        XCTAssertEqual(status.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(status.value(forHTTPHeaderField: "Referer"), "https://grok.com/dashboard/usage")
        XCTAssertEqual(status.value(forHTTPHeaderField: "x-cursor-dashboard-surface"), "v2")
        XCTAssertTrue(status.value(forHTTPHeaderField: "User-Agent")?.contains("Safari") == true)
        XCTAssertNil(status.value(forHTTPHeaderField: "Origin"))

        let body = try DashboardJSON.encode(DailyUsageRequest.make(
            range: DateInterval(start: UsageWindow.utcDate(year: 2026, month: 11, day: 1), duration: 86_400),
            usageTypes: nil
        ))
        let daily = client.makeDailyRequest(body: body)
        XCTAssertEqual(daily.httpMethod, "POST")
        XCTAssertEqual(daily.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(daily.value(forHTTPHeaderField: "Origin"), "https://grok.com")
        XCTAssertEqual(daily.value(forHTTPHeaderField: "Cookie"), cookie)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(object["filters"])
    }

    func testFetchDecodesBothEndpoints() async throws {
        let statusData = try FixtureLoader.data("usage_status_sample")
        let dailyData = try FixtureLoader.data("daily_usage_sample")
        let postCount = CountBox()
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("usage-status") {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), self.cookie)
                return (200, statusData, ["Content-Type": "application/json"])
            }
            postCount.value += 1
            let body = try XCTUnwrap(Self.bodyData(request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertNil(object["filters"])
            XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://grok.com")
            return (200, dailyData, ["Content-Type": "application/json"])
        }

        let provider = try makeProvider()
        let now = try XCTUnwrap(DashboardJSON.parseISO8601("2026-11-01T18:00:00.000Z"))
        let snapshot = try await provider.fetchUsage(now: now)
        XCTAssertEqual(postCount.value, 1)
        XCTAssertEqual(snapshot.totalTokens, 33_000_466)
        XCTAssertEqual(snapshot.weeklyStatus, "metered")
        XCTAssertEqual(UsageFormat.percent(usedCents: snapshot.weeklyUsedCents, budgetCents: snapshot.weeklyBudgetCents), "7%")
        XCTAssertEqual(snapshot.totalsMode, .unfiltered)
    }

    func testSessionExpiredDoesNotIncludeCookie() async throws {
        MockURLProtocol.handler = { _ in
            (401, Data("{}".utf8), ["Content-Type": "application/json"])
        }
        let provider = try makeProvider()
        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected session expiration")
        } catch let error as UsageFetchError {
            XCTAssertEqual(error, .sessionExpired)
            XCTAssertFalse(error.localizedDescription.contains(cookie))
            XCTAssertTrue(error.localizedDescription.contains("Sign in again"))
        }
    }

    func testHTMLResponseIsSessionExpired() async throws {
        MockURLProtocol.handler = { _ in
            (200, Data("<!DOCTYPE html><html>login</html>".utf8), ["Content-Type": "text/html"])
        }
        let provider = try makeProvider()
        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected session expiration")
        } catch UsageFetchError.sessionExpired {
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testRejectedUnfilteredQueryFallsBack() async throws {
        let statusData = try FixtureLoader.data("usage_status_sample")
        let dailyData = try FixtureLoader.data("daily_usage_sample")
        let bodies = ListBox()
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("usage-status") {
                return (200, statusData, ["Content-Type": "application/json"])
            }
            let body = try XCTUnwrap(Self.bodyData(request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            bodies.values.append(object)
            if bodies.values.count == 1 {
                return (400, Data("{\"error\":\"filters\"}".utf8), ["Content-Type": "application/json"])
            }
            return (200, dailyData, ["Content-Type": "application/json"])
        }
        let provider = try makeProvider()
        let snapshot = try await provider.fetchUsage(now: Date(timeIntervalSince1970: 1_762_000_000))
        XCTAssertEqual(bodies.values.count, 2)
        XCTAssertNil(bodies.values[0]["filters"])
        let filters = try XCTUnwrap(bodies.values[1]["filters"] as? [String: Any])
        XCTAssertEqual(filters["usageTypes"] as? [String], ["included", "on-demand"])
        XCTAssertEqual(snapshot.totalsMode, .includedAndOnDemand)
    }

    func testUnauthorizedDoesNotRetryDailyQuery() async throws {
        let calls = CountBox()
        MockURLProtocol.handler = { _ in
            calls.value += 1
            return (403, Data(), ["Content-Type": "application/json"])
        }
        let provider = try makeProvider()
        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected session expiration")
        } catch UsageFetchError.sessionExpired {
            XCTAssertEqual(calls.value, 1)
        }
    }

    func testUnavailableSkipsDailyQuery() async throws {
        var status = try DashboardJSON.decode(UsageStatusResponse.self, from: FixtureLoader.data("usage_status_sample"))
        status.availability = "unavailable"
        let data = try DashboardJSON.encode(status)
        let sawDaily = FlagBox()
        MockURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("query-daily-usage") == true {
                sawDaily.value = true
            }
            return (200, data, ["Content-Type": "application/json"])
        }
        let provider = try makeProvider()
        let snapshot = try await provider.fetchUsage()
        XCTAssertFalse(sawDaily.value)
        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertEqual(snapshot.availabilityRaw, "unavailable")
    }

    func testLoaderNeedsCookieAndSessionExpired() async throws {
        let directory = try makeTempDirectory()
        let cache = UsageCache(directory: directory)
        try cache.save(.screenshotFixture)
        let store = MemoryCookieStore()
        let empty = UsageLoader(store: store, cache: cache, makeProvider: { _ in
            ScriptedProvider(result: .success(.screenshotFixture))
        })
        let missing = await empty.load(now: Date())
        XCTAssertEqual(missing.presentation, .needsCookie)
        XCTAssertNil(missing.snapshot)

        store.value = cookie
        let expired = UsageLoader(store: store, cache: cache, makeProvider: { _ in
            ScriptedProvider(result: .failure(.sessionExpired))
        })
        let failed = await expired.load(now: Date())
        XCTAssertEqual(failed.presentation, .sessionExpired)
        XCTAssertEqual(failed.snapshot?.totalTokens, 967_200_000)

        let fresh = UsageLoader(store: store, cache: cache, makeProvider: { _ in
            ScriptedProvider(result: .success(.screenshotFixture))
        })
        let loaded = await fresh.load(now: UsageSnapshot.screenshotFetchedAt)
        XCTAssertEqual(loaded.presentation, .fresh)
        XCTAssertEqual(cache.load()?.includedTokens, 874_700_000)
    }

    func testCacheRoundTripAndDumpRedaction() throws {
        let directory = try makeTempDirectory()
        let cache = UsageCache(directory: directory)
        try cache.save(.screenshotFixture)
        let loaded = try XCTUnwrap(cache.load())
        XCTAssertEqual(loaded.totalTokens, 967_200_000)
        XCTAssertEqual(loaded.weeklyBudgetCents, 16159)
        XCTAssertEqual(loaded.dailyPoints.count, UsageSnapshot.screenshotFixture.dailyPoints.count)
        XCTAssertEqual(loaded.fetchedAt.timeIntervalSince1970, UsageSnapshot.screenshotFetchedAt.timeIntervalSince1970, accuracy: 0.002)

        let dump = RawResponseDump(directory: directory)
        XCTAssertThrowsError(try dump.write(data: Data("session=test-fixture".utf8), to: "last_usage_status.json", redacting: cookie))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("last_usage_status.json").path))

        let clean = try FixtureLoader.data("usage_status_sample")
        let url = try dump.write(data: clean, to: RawResponseDump.usageStatusFilename, redacting: cookie)
        let written = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(written.contains("\"usedCents\" : 1160") || written.contains("\"usedCents\": 1160"))
        XCTAssertFalse(written.contains(cookie))
    }

    func testDumpWithoutCookieDoesNotFetch() async {
        let command = DumpCommand(
            arguments: [],
            loadCookie: { nil },
            fetch: { _, _ in
                XCTFail("fetch should not run")
                return DashboardFetchResult(snapshot: .screenshotFixture, usageStatusData: Data(), dailyUsageData: nil, dailyRequest: nil)
            },
            writeOutput: { _ in }
        )
        let code = await command.run()
        XCTAssertEqual(code, 2)
    }

    func testDumpHelpAndUnknownArgument() async {
        var lines: [String] = []
        let help = DumpCommand(arguments: ["--help"], loadCookie: { "session=test-fixture" }, fetch: { _, _ in
            XCTFail("fetch should not run")
            return DashboardFetchResult(snapshot: .screenshotFixture, usageStatusData: Data(), dailyUsageData: nil, dailyRequest: nil)
        }, writeOutput: { lines.append($0) })
        let helpCode = await help.run()
        XCTAssertEqual(helpCode, 0)
        XCTAssertTrue(lines.joined(separator: "\n").contains("grok-usage-dump"))
        XCTAssertFalse(lines.joined(separator: "\n").contains("session=test-fixture"))

        let unknown = DumpCommand(arguments: ["--cookie", "session=test-fixture"], loadCookie: { nil }, fetch: { _, _ in
            DashboardFetchResult(snapshot: .screenshotFixture, usageStatusData: Data(), dailyUsageData: nil, dailyRequest: nil)
        }, writeOutput: { _ in })
        let unknownCode = await unknown.run()
        XCTAssertEqual(unknownCode, 1)
    }

    private func makeProvider() throws -> GrokWebUsageProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let provider = GrokWebUsageProvider(cookieHeader: "Cookie: \(cookie)", sessionConfiguration: configuration)
        provider.client.configuration.protocolClasses = [MockURLProtocol.self]
        URLProtocol.registerClass(MockURLProtocol.self)
        return provider
    }

    private static func bodyData(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class CountBox: @unchecked Sendable {
    var value = 0
}

final class FlagBox: @unchecked Sendable {
    var value = false
}

final class ListBox: @unchecked Sendable {
    var values: [[String: Any]] = []
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data, [String: String]))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, data, headers) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url ?? DashboardEndpoints.usageStatus,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
