import XCTest

final class HeaderBox: @unchecked Sendable {
    var values: [String] = []
}

final class CookieHeaderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testHeaderKeepsGrokDomainsAndDropsOthers() throws {
        let header = CookieHeaderBuilder.header(from: [
            cookie(name: "SID", value: "google-secret", domain: ".google.com"),
            cookie(name: "SID", value: "google-host", domain: "google.com"),
            cookie(name: "n", value: "not-grok", domain: "notgrok.com"),
            cookie(name: "e", value: "evil", domain: "grok.com.evil.com"),
            cookie(name: "sso", value: "grok-secret", domain: ".grok.com"),
            cookie(name: "sso-sub", value: "accounts-secret", domain: "accounts.grok.com"),
            cookie(name: "host", value: "host-secret", domain: "grok.com"),
            cookie(name: "blank", value: "", domain: "grok.com"),
        ], now: now)

        let value = try XCTUnwrap(header)
        XCTAssertEqual(value, "host=host-secret; sso=grok-secret; sso-sub=accounts-secret")
        XCTAssertFalse(value.contains("google"))
        XCTAssertFalse(value.contains("not-grok"))
        XCTAssertFalse(value.contains("evil"))
        XCTAssertFalse(value.contains("Cookie:"))
    }

    func testHeaderDropsExpiredCookiesAndSortsByNameThenPath() {
        let header = CookieHeaderBuilder.header(from: [
            cookie(name: "b", value: "later", domain: "grok.com", path: "/z"),
            cookie(name: "b", value: "earlier", domain: ".grok.com", path: "/a"),
            cookie(name: "a", value: "first", domain: "GROK.COM"),
            cookie(name: "old", value: "expired-secret", domain: "grok.com", expiresDate: now.addingTimeInterval(-1)),
            cookie(name: "edge", value: "still-valid", domain: "grok.com", expiresDate: now.addingTimeInterval(1)),
            cookie(name: "session", value: "no-expiry", domain: ".grok.com", expiresDate: nil),
        ], now: now)

        XCTAssertEqual(
            header,
            "a=first; b=earlier; b=later; edge=still-valid; session=no-expiry"
        )
    }

    func testHeaderIsNilWhenNothingBelongsToGrok() {
        let header = CookieHeaderBuilder.header(from: [
            cookie(name: "SID", value: "google-secret", domain: ".google.com"),
            cookie(name: "old", value: "expired-secret", domain: "grok.com", expiresDate: now),
        ], now: now)
        XCTAssertNil(header)
    }

    func testDomainMatcherRejectsLookalikes() {
        XCTAssertTrue(GrokCookieScope.isGrokDomain("grok.com"))
        XCTAssertTrue(GrokCookieScope.isGrokDomain(".grok.com"))
        XCTAssertTrue(GrokCookieScope.isGrokDomain("accounts.grok.com"))
        XCTAssertFalse(GrokCookieScope.isGrokDomain("notgrok.com"))
        XCTAssertFalse(GrokCookieScope.isGrokDomain("grok.com.evil.com"))
        XCTAssertFalse(GrokCookieScope.isGrokDomain("google.com"))
        XCTAssertFalse(GrokCookieScope.isGrokDomain(".google.com"))
        XCTAssertFalse(GrokCookieScope.isGrokDomain("evilgrok.com"))
    }

    func testExpiredSessionThenReharvestSavesFreshGrokCookiesOnly() async {
        let saved = HeaderBox()
        let probeCount = CountBox()
        let harvest = SessionReharvest(
            readCookies: {
                [
                    self.cookie(name: "old", value: "expired-secret", domain: ".grok.com", expiresDate: self.now.addingTimeInterval(-60)),
                    self.cookie(name: "sso", value: "grok-secret", domain: ".grok.com"),
                    self.cookie(name: "SID", value: "google-secret", domain: ".google.com"),
                ]
            },
            probe: { header in
                probeCount.value += 1
                XCTAssertTrue(header.contains("sso=grok-secret"))
                XCTAssertFalse(header.contains("expired-secret"))
                XCTAssertFalse(header.contains("google-secret"))
                return true
            },
            save: { saved.values.append($0) }
        )

        let outcome = await harvest.run(now: now)
        XCTAssertEqual(outcome, .recovered)
        XCTAssertEqual(probeCount.value, 1)
        XCTAssertEqual(saved.values, ["sso=grok-secret"])
    }

    func testReharvestDoesNotSaveWhenProbeRejects() async {
        let saved = FlagBox()
        let harvest = SessionReharvest(
            readCookies: { [self.cookie(name: "sso", value: "grok-secret", domain: "grok.com")] },
            probe: { _ in false },
            save: { _ in saved.value = true }
        )

        let outcome = await harvest.run(now: now)
        XCTAssertEqual(outcome, .signInAgain)
        XCTAssertFalse(saved.value)
    }

    func testReharvestDoesNotProbeWhenCookiesAreMissingOrExpired() async {
        let probeCount = CountBox()
        let saved = FlagBox()
        let harvest = SessionReharvest(
            readCookies: {
                [
                    self.cookie(name: "SID", value: "google-secret", domain: "google.com"),
                    self.cookie(name: "old", value: "expired-secret", domain: "grok.com", expiresDate: self.now.addingTimeInterval(-5)),
                ]
            },
            probe: { _ in
                probeCount.value += 1
                return true
            },
            save: { _ in saved.value = true }
        )

        let outcome = await harvest.run(now: now)
        XCTAssertEqual(outcome, .signInAgain)
        XCTAssertEqual(probeCount.value, 0)
        XCTAssertFalse(saved.value)
    }

    func testReharvestSaveFailureDoesNotRevealTheCookie() async {
        struct SaveError: LocalizedError {
            var errorDescription: String? { "could not store sso=grok-secret" }
        }
        let harvest = SessionReharvest(
            readCookies: { [self.cookie(name: "sso", value: "grok-secret", domain: ".grok.com")] },
            probe: { _ in true },
            save: { _ in throw SaveError() }
        )

        let outcome = await harvest.run(now: now)
        guard case .saveFailed(let message) = outcome else {
            return XCTFail("Expected save failure, got \(outcome)")
        }
        XCTAssertFalse(message.contains("grok-secret"))
        XCTAssertTrue(message.contains("[redacted]"))
    }

    func testSignInLink() {
        XCTAssertTrue(AppLink.isSignIn(AppLink.signIn))
        XCTAssertTrue(AppLink.isSignIn(URL(string: "grokwidget://sign-in/extra")!))
        XCTAssertFalse(AppLink.isSignIn(URL(string: "grokwidget://open")!))
        XCTAssertFalse(AppLink.isSignIn(AppLink.openUsage))
        XCTAssertFalse(AppLink.isSignIn(URL(string: "https://grok.com/sign-in")!))
        XCTAssertEqual(AppLink.signIn.scheme, "grokwidget")
        XCTAssertEqual(AppLink.signIn.host, "sign-in")
        XCTAssertTrue(AppLink.isAppLink(AppLink.showApp))
        XCTAssertTrue(AppLink.isOpenUsage(AppLink.openUsage))
        XCTAssertEqual(AppLink.dashboard.absoluteString, "https://grok.com/dashboard/usage")
        XCTAssertEqual(AppLink.dashboard.absoluteString, DashboardEndpoints.referer)
    }

    func testEveryWidgetStateHasALink() {
        let signIn = URL(string: "grokwidget://sign-in")!
        XCTAssertEqual(AppLink.widgetURL(for: .needsCookie), signIn)
        XCTAssertEqual(AppLink.widgetURL(for: .sessionExpired), signIn)
        for presentation in [UsagePresentation.fresh, .stale, .loading, .unavailable, .failed("offline")] {
            let link = AppLink.widgetURL(for: presentation)
            XCTAssertEqual(link, AppLink.openUsage)
            XCTAssertEqual(link.absoluteString, "grokwidget://open-usage")
            XCTAssertFalse(AppLink.isSignIn(link))
        }
    }

    func testProbeAccepts200JSONAndRejectsExpiredSession() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        URLProtocol.registerClass(MockURLProtocol.self)

        MockURLProtocol.handler = { _ in
            (200, Data("{\"availability\":\"available\"}".utf8), ["Content-Type": "application/json"])
        }
        let accepted = await UsageStatusProbe.succeeds(cookieHeader: "sso=grok-secret", sessionConfiguration: configuration)
        XCTAssertTrue(accepted)

        MockURLProtocol.handler = { _ in
            (401, Data("{}".utf8), ["Content-Type": "application/json"])
        }
        let expired = await UsageStatusProbe.succeeds(cookieHeader: "sso=grok-secret", sessionConfiguration: configuration)
        XCTAssertFalse(expired)

        MockURLProtocol.handler = { _ in
            (200, Data("<!DOCTYPE html><html>login</html>".utf8), ["Content-Type": "text/html"])
        }
        let html = await UsageStatusProbe.succeeds(cookieHeader: "sso=grok-secret", sessionConfiguration: configuration)
        XCTAssertFalse(html)
    }

    private func cookie(
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        expiresDate: Date? = nil
    ) -> HTTPCookieSnapshot {
        HTTPCookieSnapshot(name: name, value: value, domain: domain, path: path, expiresDate: expiresDate)
    }
}
