import Foundation

/// A cookie reduced to the fields needed to build a `Cookie` header.
/// WebKit stays in the app target; tests use this snapshot.
struct HTTPCookieSnapshot: Equatable, Sendable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expiresDate: Date?

    init(name: String, value: String, domain: String, path: String, expiresDate: Date?) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expiresDate = expiresDate
    }

    init(_ cookie: HTTPCookie) {
        self.init(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            path: cookie.path,
            expiresDate: cookie.expiresDate
        )
    }
}

enum GrokCookieScope {
    /// `grok.com` and any subdomain. A leading dot is ignored.
    /// `notgrok.com` and `grok.com.evil.com` are rejected.
    static func isGrokDomain(_ domain: String) -> Bool {
        var host = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while host.hasPrefix(".") {
            host.removeFirst()
        }
        if let colon = host.firstIndex(of: ":") {
            host = String(host[..<colon])
        }
        while host.hasSuffix(".") {
            host.removeLast()
        }
        return host == "grok.com" || host.hasSuffix(".grok.com")
    }
}

enum CookieHeaderBuilder {
    /// Cookie header for grok.com only. Names are sorted so the result is stable.
    /// Expired cookies are dropped. Session cookies (`expiresDate == nil`) are kept.
    /// Returns nil when nothing qualifies. Never includes a `Cookie:` prefix.
    static func header(from cookies: [HTTPCookieSnapshot], now: Date = Date()) -> String? {
        let kept = cookies.filter { cookie in
            !cookie.name.isEmpty
                && !cookie.value.isEmpty
                && GrokCookieScope.isGrokDomain(cookie.domain)
                && !isExpired(cookie, now: now)
        }
        .sorted { lhs, rhs in
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            if lhs.path != rhs.path { return lhs.path < rhs.path }
            return lhs.value < rhs.value
        }
        guard !kept.isEmpty else { return nil }
        return kept.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    private static func isExpired(_ cookie: HTTPCookieSnapshot, now: Date) -> Bool {
        guard let expiresDate = cookie.expiresDate else { return false }
        return expiresDate <= now
    }
}

enum AppLink {
    static let signIn = URL(string: "grokwidget://sign-in")!
    static let showApp = URL(string: "grokwidget://open")!
    static let openUsage = URL(string: "grokwidget://open-usage")!
    static let dashboard = URL(string: "https://grok.com/dashboard/usage")!

    static func isAppLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "grokwidget"
    }

    static func isSignIn(_ url: URL) -> Bool {
        isAppLink(url) && url.host?.lowercased() == "sign-in"
    }

    static func isOpenUsage(_ url: URL) -> Bool {
        isAppLink(url) && url.host?.lowercased() == "open-usage"
    }

    static func isDashboard(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "grok.com"
            && url.path == "/dashboard/usage"
    }

    /// A signed-in click should open the browser. On macOS, WidgetKit does that
    /// for an https widgetURL. A custom scheme only launches the containing app,
    /// which is what a desktop click was doing.
    static func opensDashboard(_ url: URL) -> Bool {
        isOpenUsage(url) || isDashboard(url)
    }

    /// Sign-in needed and an expired session open the sign-in sheet.
    /// Every other state, including stale, opens the dashboard in the browser.
    /// One link covers every widget size.
    static func widgetURL(for presentation: UsagePresentation) -> URL {
        switch presentation {
        case .needsCookie, .sessionExpired:
            return signIn
        case .fresh, .stale, .loading, .unavailable, .failed:
            return dashboard
        }
    }
}

enum ReharvestOutcome: Equatable, Sendable {
    case recovered
    case signInAgain
    case saveFailed(String)
}

/// Reads cookies, keeps grok.com ones, probes usage-status, then saves.
/// A missing or rejected session does not write the Keychain.
struct SessionReharvest: Sendable {
    var readCookies: @Sendable () async -> [HTTPCookieSnapshot]
    var probe: @Sendable (String) async -> Bool
    var save: @Sendable (String) throws -> Void

    func run(now: Date = Date()) async -> ReharvestOutcome {
        let cookies = await readCookies()
        guard let header = CookieHeaderBuilder.header(from: cookies, now: now) else {
            return .signInAgain
        }
        let accepted = await probe(header)
        guard accepted else { return .signInAgain }
        do {
            try save(header)
            return .recovered
        } catch {
            return .saveFailed(UsageFetchError.redact(error.localizedDescription, cookie: header))
        }
    }
}

enum UsageStatusProbe {
    /// True only when usage-status returns HTTP 200 and a JSON object.
    static func succeeds(
        cookieHeader: String,
        sessionConfiguration: URLSessionConfiguration = .ephemeral
    ) async -> Bool {
        let client = DashboardClient(cookieHeader: cookieHeader, sessionConfiguration: sessionConfiguration)
        do {
            let (data, response) = try await client.send(client.makeUsageStatusRequest())
            guard (200..<300).contains(response.statusCode) else { return false }
            let json = try JSONSerialization.jsonObject(with: data)
            return json is [String: Any]
        } catch {
            return false
        }
    }
}
