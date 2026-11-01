import Foundation

struct LoadedUsage {
    var snapshot: UsageSnapshot?
    var presentation: UsagePresentation
}

struct UsageLoader {
    var store: any CookieStoring
    var cache: UsageCache
    var makeProvider: (String) -> any UsageProvider

    init(
        store: any CookieStoring = KeychainCookieStore(),
        cache: UsageCache = UsageCache(),
        makeProvider: @escaping (String) -> any UsageProvider = { cookie in
            GrokWebUsageProvider(cookieHeader: cookie)
        }
    ) {
        self.store = store
        self.cache = cache
        self.makeProvider = makeProvider
    }

    func load(now: Date) async -> LoadedUsage {
        let cached = cache.load()
        let cookie: String?
        do {
            cookie = try store.load()
        } catch {
            return LoadedUsage(snapshot: cached, presentation: .failed(error.localizedDescription))
        }
        guard let cookie, !CookieHeader.normalize(cookie).isEmpty else {
            return LoadedUsage(snapshot: nil, presentation: .needsCookie)
        }
        do {
            let snapshot = try await makeProvider(cookie).fetchUsage(now: now)
            try? cache.save(snapshot)
            if !snapshot.isAvailable {
                return LoadedUsage(snapshot: snapshot, presentation: .unavailable)
            }
            return LoadedUsage(snapshot: snapshot, presentation: .fresh)
        } catch UsageFetchError.sessionExpired {
            return LoadedUsage(snapshot: cached, presentation: .sessionExpired)
        } catch {
            let message = UsageFetchError.redact(error.localizedDescription, cookie: cookie)
            return LoadedUsage(snapshot: cached, presentation: .failed(message))
        }
    }
}
