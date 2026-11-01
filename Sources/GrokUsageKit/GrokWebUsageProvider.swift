import Foundation

struct DashboardFetchResult: Sendable {
    var snapshot: UsageSnapshot
    var usageStatusData: Data
    var dailyUsageData: Data?
    var dailyRequest: DailyUsageRequest?
}

enum CaptureName: String, Sendable {
    case usageStatus
    case dailyUsage
    case dailyRequest
}

final class ResponseCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CaptureName: Data] = [:]

    func record(_ name: CaptureName, data: Data) {
        lock.lock()
        storage[name] = data
        lock.unlock()
    }

    func data(_ name: CaptureName) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[name]
    }
}

final class LoginRedirectInterceptor: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var redirectedToLogin = false

    var didRedirectToLogin: Bool {
        lock.lock()
        defer { lock.unlock() }
        return redirectedToLogin
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if RedirectPolicy.shouldTreatAsSessionExpired(responseURL: response.url, nextURL: request.url) {
            lock.lock()
            redirectedToLogin = true
            lock.unlock()
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

struct DashboardClient {
    var cookieHeader: String
    var configuration: URLSessionConfiguration

    init(cookieHeader: String, sessionConfiguration: URLSessionConfiguration = .ephemeral) {
        self.cookieHeader = cookieHeader
        let configuration = sessionConfiguration.copy() as? URLSessionConfiguration ?? .ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.configuration = configuration
    }

    func makeUsageStatusRequest() -> URLRequest {
        makeRequest(url: DashboardEndpoints.usageStatus, method: "GET", body: nil)
    }

    func makeDailyRequest(body: Data) -> URLRequest {
        makeRequest(url: DashboardEndpoints.queryDailyUsage, method: "POST", body: body)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let interceptor = LoginRedirectInterceptor()
        let session = URLSession(configuration: configuration, delegate: interceptor, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if interceptor.didRedirectToLogin {
                throw UsageFetchError.sessionExpired
            }
            throw UsageFetchError.network(UsageFetchError.redact(error.localizedDescription, cookie: cookieHeader))
        }

        if interceptor.didRedirectToLogin {
            throw UsageFetchError.sessionExpired
        }
        guard let http = response as? HTTPURLResponse else {
            throw UsageFetchError.network("No HTTP response")
        }
        if RedirectPolicy.isLogin(http.url) || (300..<400).contains(http.statusCode) {
            throw UsageFetchError.sessionExpired
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw UsageFetchError.sessionExpired
        }
        if let mime = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(), mime.contains("html") {
            throw UsageFetchError.sessionExpired
        }
        if let prefix = String(data: data.prefix(128), encoding: .utf8)?.lowercased(),
           prefix.contains("<html") || prefix.contains("<!doctype") {
            throw UsageFetchError.sessionExpired
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 400 || http.statusCode == 422 {
                throw UsageFetchError.rejectedQuery(http.statusCode)
            }
            throw UsageFetchError.httpStatus(http.statusCode)
        }
        return (data, http)
    }

    private func makeRequest(url: URL, method: String, body: Data?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(DashboardEndpoints.referer, forHTTPHeaderField: "Referer")
        request.setValue(DashboardEndpoints.surfaceValue, forHTTPHeaderField: DashboardEndpoints.surfaceHeader)
        request.setValue(DashboardEndpoints.userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(DashboardEndpoints.origin, forHTTPHeaderField: "Origin")
        }
        return request
    }
}

struct GrokWebUsageProvider: UsageProvider {
    var cookieHeader: String
    var client: DashboardClient
    var filterAttempts: [DailyFilterAttempt]

    init(
        cookieHeader: String,
        sessionConfiguration: URLSessionConfiguration = .ephemeral,
        filterAttempts: [DailyFilterAttempt] = DailyFilterAttempt.defaultChain
    ) {
        let normalized = CookieHeader.normalize(cookieHeader)
        self.cookieHeader = normalized
        self.client = DashboardClient(cookieHeader: normalized, sessionConfiguration: sessionConfiguration)
        self.filterAttempts = filterAttempts
    }

    func fetchUsage(now: Date) async throws -> UsageSnapshot {
        try await fetchRaw(now: now).snapshot
    }

    func fetchRaw(now: Date = Date(), capture: ResponseCapture = ResponseCapture()) async throws -> DashboardFetchResult {
        guard !cookieHeader.isEmpty else { throw UsageFetchError.missingCookie }

        let (statusData, _) = try await client.send(client.makeUsageStatusRequest())
        capture.record(.usageStatus, data: statusData)
        let status: UsageStatusResponse
        do {
            status = try DashboardJSON.decode(UsageStatusResponse.self, from: statusData)
        } catch {
            throw UsageFetchError.decoding(UsageFetchError.redact(error.localizedDescription, cookie: cookieHeader))
        }

        guard status.availability == "available" else {
            return DashboardFetchResult(
                snapshot: UsageSnapshotBuilder.makeUnavailable(status: status, now: now),
                usageStatusData: statusData,
                dailyUsageData: nil,
                dailyRequest: nil
            )
        }

        let range = UsageWindow.queryRange(now: now, weeklyPeriodStart: status.weeklyIncludedUsage.periodStart)
        let daily = try await fetchDaily(range: range, capture: capture)
        let snapshot = UsageSnapshotBuilder.make(
            status: status,
            daily: daily.decoded,
            totalsMode: daily.mode,
            now: now
        )
        return DashboardFetchResult(
            snapshot: snapshot,
            usageStatusData: statusData,
            dailyUsageData: daily.data,
            dailyRequest: daily.request
        )
    }

    private func fetchDaily(
        range: DateInterval,
        capture: ResponseCapture
    ) async throws -> (data: Data, decoded: DailyUsageResponse, mode: DailyQueryMode, request: DailyUsageRequest) {
        var lastError: Error = UsageFetchError.rejectedQuery(400)
        for attempt in filterAttempts {
            let request = DailyUsageRequest.make(range: range, usageTypes: attempt.usageTypes)
            let body = try DashboardJSON.encode(request)
            capture.record(.dailyRequest, data: body)
            do {
                let (data, _) = try await client.send(client.makeDailyRequest(body: body))
                capture.record(.dailyUsage, data: data)
                let decoded: DailyUsageResponse
                do {
                    decoded = try DashboardJSON.decode(DailyUsageResponse.self, from: data)
                } catch {
                    throw UsageFetchError.decoding(UsageFetchError.redact(error.localizedDescription, cookie: cookieHeader))
                }
                return (data, decoded, attempt.mode, request)
            } catch let error as UsageFetchError {
                switch error {
                case .rejectedQuery:
                    lastError = error
                    continue
                default:
                    throw error
                }
            }
        }
        throw lastError
    }
}
