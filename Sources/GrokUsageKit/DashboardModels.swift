import Foundation

struct JSONDecimal: Codable, Equatable, Sendable {
    var value: Decimal

    init(_ value: Decimal) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a decimal string"
            )
        }
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(NSDecimalNumber(decimal: value).stringValue)
    }
}

struct UsageStatusResponse: Codable, Equatable, Sendable {
    var availability: String
    var monthlyUsage: MonthlyUsage
    var weeklyIncludedStatus: WeeklyIncludedStatus
    var weeklyIncludedUsage: WeeklyIncludedUsage
}

struct MonthlyUsage: Codable, Equatable, Sendable {
    var usedCents: Int
    var limitCents: Int?
    var additionalUsageOff: Bool
    var creditsUsedCents: Int
    var periodStart: Date
    var resetsAt: Date
}

struct WeeklyIncludedStatus: Codable, Equatable, Sendable {
    var status: String
}

struct WeeklyIncludedUsage: Codable, Equatable, Sendable {
    var usedCents: Int
    var budgetCents: Int
    var resetCounter: Int
    var periodStart: Date
    var resetsAt: Date
}

struct DailyUsageResponse: Codable, Equatable, Sendable {
    var availability: String
    var startTime: Date
    var endTime: Date
    var totalContractedCost: JSONDecimal
    var totalTokens: Int64
    var totalIncludedTokens: Int64
    var series: [DailyUsageSeries]
    var other: DailyUsageOther
}

struct DailyUsageSeries: Codable, Equatable, Sendable {
    var dimensions: Dimensions
    var costRank: Int
    var tokenRank: Int
    var totalContractedCost: JSONDecimal
    var totalTokens: Int64
    var totalIncludedTokens: Int64
    var points: [DailyUsagePoint]

    struct Dimensions: Codable, Equatable, Sendable {
        var product: String
    }
}

struct DailyUsageOther: Codable, Equatable, Sendable {
    var totalContractedCost: JSONDecimal
    var totalTokens: Int64
    var totalIncludedTokens: Int64
    var points: [DailyUsagePoint]
}

struct DailyUsagePoint: Codable, Equatable, Sendable {
    var dayStartTime: Date
    var contractedCost: JSONDecimal
    var tokens: Int64
    var includedTokens: Int64
}

struct DailyUsageRequest: Codable, Equatable, Sendable {
    var scope: String = "user"
    var startTime: String
    var endTime: String
    var groupBy: [String] = ["product"]
    var filters: Filters?
    var topN: Int = 5

    struct Filters: Codable, Equatable, Sendable {
        var usageTypes: [String]
    }

    static func make(range: DateInterval, usageTypes: [String]?) -> DailyUsageRequest {
        DailyUsageRequest(
            startTime: DashboardJSON.requestTimestamp(range.start),
            endTime: DashboardJSON.requestTimestamp(range.end),
            filters: usageTypes.map { Filters(usageTypes: $0) }
        )
    }
}

enum DashboardEndpoints {
    static let usageStatus = URL(string: "https://grok.com/dashboard/api/dashboard/v2/usage-status?scope=user")!
    static let queryDailyUsage = URL(string: "https://grok.com/dashboard/api/dashboard/v2/query-daily-usage")!
    static let referer = "https://grok.com/dashboard/usage"
    static let origin = "https://grok.com"
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"
    static let surfaceHeader = "x-cursor-dashboard-surface"
    static let surfaceValue = "v2"
}

enum DashboardJSON {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder().decode(type, from: data)
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder().encode(value)
    }

    static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    /// Matches the captured request body, for example `2026-11-01T00:00:00.000Z`.
    static func requestTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter.string(from: date)
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = parseISO8601(value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognized date"
                )
            }
            return date
        }
        return decoder
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(requestTimestamp(date))
        }
        return encoder
    }
}
