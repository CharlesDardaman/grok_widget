import Foundation

enum UsageFetchError: Error, Equatable, LocalizedError, Sendable {
    case missingCookie
    case sessionExpired
    case rejectedQuery(Int)
    case httpStatus(Int)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingCookie:
            return "No session cookie is saved. Paste the Cookie header in Grok Widget."
        case .sessionExpired:
            return "Session expired. Re-paste the cookie in Grok Widget."
        case .rejectedQuery(let code):
            return "The daily usage query was rejected (\(code))."
        case .httpStatus(let code):
            return "grok.com returned HTTP \(code)."
        case .decoding(let message):
            return "Couldn't read the usage response. \(message)"
        case .network(let message):
            return message
        }
    }

    static func redact(_ text: String, cookie: String) -> String {
        let trimmed = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        return text.replacingOccurrences(of: trimmed, with: "[redacted]")
    }
}

enum CookieHeader {
    static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("cookie:") {
            value = String(value.dropFirst("cookie:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }
}

enum RedirectPolicy {
    static func shouldTreatAsSessionExpired(responseURL: URL?, nextURL: URL?) -> Bool {
        isLogin(responseURL) || isLogin(nextURL)
    }

    static func isLogin(_ url: URL?) -> Bool {
        guard let url else { return false }
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let haystack = host + path
        let markers = ["login", "sign-in", "signin", "log-in", "/oauth", "/auth/"]
        return markers.contains { haystack.contains($0) }
    }
}
