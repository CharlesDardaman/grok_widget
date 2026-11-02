import Foundation

protocol UsageProvider {
    func fetchUsage(now: Date) async throws -> UsageSnapshot
}

extension UsageProvider {
    func fetchUsage() async throws -> UsageSnapshot {
        try await fetchUsage(now: Date())
    }
}

struct FixtureUsageProvider: UsageProvider {
    func fetchUsage(now: Date) async throws -> UsageSnapshot {
        UsageSnapshot.screenshotFixture
    }
}
