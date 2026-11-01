import Foundation
import XCTest

enum FixtureLoader {
    static func data(_ name: String, file: StaticString = #filePath) throws -> Data {
        let bundle = Bundle(for: FormatTests.self)
        if let url = bundle.url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        if let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") {
            return try Data(contentsOf: url)
        }
        let sourceFixtures = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).json")
        if FileManager.default.fileExists(atPath: sourceFixtures.path) {
            return try Data(contentsOf: sourceFixtures)
        }
        throw NSError(
            domain: "FixtureLoader",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing \(name).json in \(bundle.bundlePath)"]
        )
    }
}

func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("grok-widget-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

final class MemoryCookieStore: CookieStoring {
    var value: String?
    func save(_ cookieHeader: String) throws { value = CookieHeader.normalize(cookieHeader) }
    func load() throws -> String? { value }
    func clear() throws { value = nil }
    func hasCookie() throws -> Bool { !(value ?? "").isEmpty }
}

struct ScriptedProvider: UsageProvider {
    var result: Result<UsageSnapshot, UsageFetchError>
    func fetchUsage(now: Date) async throws -> UsageSnapshot {
        try result.get()
    }
}
