import Foundation

struct UsageCache {
    var directory: URL
    var fileManager: FileManager

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else if let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: SharedStorage.appGroupID
        ) {
            self.directory = container
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.directory = support.appendingPathComponent("grok_widget", isDirectory: true)
        }
    }

    var snapshotURL: URL {
        directory.appendingPathComponent("usage-snapshot.json")
    }

    func save(_ snapshot: UsageSnapshot) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try DashboardJSON.encode(snapshot)
        try data.write(to: snapshotURL, options: .atomic)
    }

    func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? DashboardJSON.decode(UsageSnapshot.self, from: data)
    }
}
