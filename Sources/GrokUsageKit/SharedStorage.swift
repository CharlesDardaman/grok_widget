import Foundation

enum SharedStorage {
    static let appGroupID = "group.com.charlesdardaman.grok-widget"
    static let keychainService = "com.charlesdardaman.grok-widget"
    static let keychainAccount = "dashboard-session-cookie"
    /// Suffix after the team ID. The entitlement is
    /// `$(AppIdentifierPrefix)` plus this string.
    static let keychainAccessGroupSuffix = "com.charlesdardaman.grok-widget.shared"
    static let keychainAccessGroupInfoKey = "GrokKeychainAccessGroup"
    static let widgetKind = "com.charlesdardaman.grok-widget.usage"

    /// Team IDs are 10 alphanumeric characters. A missing team leaves a value
    /// like `.com.charlesdardaman...`, which is not a real access group.
    static func resolvedKeychainAccessGroup(bundle: Bundle = .main) -> String? {
        guard let raw = bundle.object(forInfoDictionaryKey: keychainAccessGroupInfoKey) as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let prefix = trimmed.split(separator: ".").first else { return nil }
        let team = String(prefix)
        let isTeamID = team.count == 10 && team.allSatisfy { $0.isLetter || $0.isNumber }
        guard isTeamID else { return nil }
        return trimmed
    }
}

enum UsageRefresh {
    static let interval: TimeInterval = 15 * 60
    static let staleAfter: TimeInterval = 30 * 60

    static func nextRefresh(after date: Date) -> Date {
        date.addingTimeInterval(interval)
    }

    static func isStale(fetchedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) >= staleAfter
    }
}
