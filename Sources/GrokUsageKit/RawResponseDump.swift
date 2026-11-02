import Foundation

struct RawResponseDump {
    var directory: URL
    var fileManager: FileManager = .default

    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/grok_widget", isDirectory: true)
    }

    static let usageStatusFilename = "last_usage_status.json"
    static let dailyUsageFilename = "last_daily_usage.json"
    static let dailyRequestFilename = "last_daily_usage_request.json"
    static let errorFilename = "last_error.txt"

    func write(result: DashboardFetchResult, cookie: String) throws -> [URL] {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        urls.append(try write(data: result.usageStatusData, to: Self.usageStatusFilename, redacting: cookie))
        if let daily = result.dailyUsageData {
            urls.append(try write(data: daily, to: Self.dailyUsageFilename, redacting: cookie))
        }
        if let request = result.dailyRequest {
            let body = try DashboardJSON.encode(request)
            urls.append(try write(data: body, to: Self.dailyRequestFilename, redacting: cookie))
        }
        let errorURL = directory.appendingPathComponent(Self.errorFilename)
        try? fileManager.removeItem(at: errorURL)
        return urls
    }

    func writeFailure(capture: ResponseCapture, error: Error, cookie: String) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = capture.data(.usageStatus) {
            _ = try? write(data: data, to: Self.usageStatusFilename, redacting: cookie)
        }
        if let data = capture.data(.dailyUsage) {
            _ = try? write(data: data, to: Self.dailyUsageFilename, redacting: cookie)
        }
        if let data = capture.data(.dailyRequest) {
            _ = try? write(data: data, to: Self.dailyRequestFilename, redacting: cookie)
        }
        let message = UsageFetchError.redact(error.localizedDescription, cookie: cookie)
        let url = directory.appendingPathComponent(Self.errorFilename)
        try Data(message.utf8).write(to: url, options: .atomic)
    }

    @discardableResult
    func write(data: Data, to filename: String, redacting cookie: String) throws -> URL {
        if containsSecret(data, cookie: cookie) {
            throw DumpError.refusedToWriteSecret
        }
        let output = prettyJSON(data) ?? data
        if containsSecret(output, cookie: cookie) {
            throw DumpError.refusedToWriteSecret
        }
        let url = directory.appendingPathComponent(filename)
        try output.write(to: url, options: .atomic)
        return url
    }

    private func containsSecret(_ data: Data, cookie: String) -> Bool {
        let secret = CookieHeader.normalize(cookie)
        guard !secret.isEmpty else { return false }
        return data.range(of: Data(secret.utf8)) != nil
    }

    private func prettyJSON(_ data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
}

enum DumpError: Error, Equatable, LocalizedError {
    case refusedToWriteSecret

    var errorDescription: String? {
        switch self {
        case .refusedToWriteSecret:
            return "Refused to write a response that contained the session cookie."
        }
    }
}

enum DumpParseError: Error, Equatable, LocalizedError {
    case missingOut
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .missingOut:
            return "Missing the directory after --out."
        case .unknown(let argument):
            return "Unknown argument \(argument)."
        }
    }
}

struct DumpOptions: Equatable {
    var outputDirectory: URL?
    var help = false

    static func parse(_ arguments: [String]) throws -> DumpOptions {
        var options = DumpOptions()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--help", "-h":
                options.help = true
            case "--out":
                index += 1
                guard index < arguments.count else { throw DumpParseError.missingOut }
                options.outputDirectory = URL(fileURLWithPath: arguments[index], isDirectory: true)
            default:
                throw DumpParseError.unknown(argument)
            }
            index += 1
        }
        return options
    }

    static let helpText = """
    grok-usage-dump [--out directory]

    Reads the grok.com session cookie from the Keychain, fetches usage-status
    and query-daily-usage, and writes the raw JSON. The cookie is never printed
    or accepted as an argument. Default directory:
    ~/Library/Application Support/grok_widget
    """
}

struct DumpCommand {
    var arguments: [String]
    var loadCookie: () throws -> String?
    var fetch: (String, ResponseCapture) async throws -> DashboardFetchResult
    var writeOutput: (String) -> Void

    func run() async -> Int32 {
        let options: DumpOptions
        do {
            options = try DumpOptions.parse(arguments)
        } catch {
            writeOutput(error.localizedDescription)
            return 1
        }
        if options.help {
            writeOutput(DumpOptions.helpText)
            return 0
        }

        let cookie: String?
        do {
            cookie = try loadCookie()
        } catch {
            writeOutput(error.localizedDescription)
            return 1
        }
        guard let cookie, !CookieHeader.normalize(cookie).isEmpty else {
            writeOutput("No session cookie in the Keychain. Open Grok Widget and sign in to grok.com.")
            return 2
        }

        let capture = ResponseCapture()
        let dump = RawResponseDump(directory: options.outputDirectory ?? RawResponseDump.defaultDirectory)
        do {
            let result = try await fetch(cookie, capture)
            let urls = try dump.write(result: result, cookie: cookie)
            writeOutput(UsageSummary.line(for: result.snapshot))
            for url in urls {
                writeOutput(url.path)
            }
            return 0
        } catch {
            try? dump.writeFailure(capture: capture, error: error, cookie: cookie)
            writeOutput(UsageFetchError.redact(error.localizedDescription, cookie: cookie))
            writeOutput(dump.directory.path)
            return 1
        }
    }
}
