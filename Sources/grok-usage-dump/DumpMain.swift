import Foundation

@main
enum GrokUsageDumpMain {
    static func main() async {
        let command = DumpCommand(
            arguments: Array(CommandLine.arguments.dropFirst()),
            loadCookie: { try KeychainCookieStore().load() },
            fetch: { cookie, capture in
                try await GrokWebUsageProvider(cookieHeader: cookie).fetchRaw(capture: capture)
            },
            writeOutput: { print($0) }
        )
        let code = await command.run()
        exit(code)
    }
}
