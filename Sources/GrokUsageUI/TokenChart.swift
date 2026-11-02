import SwiftUI

struct ChartDay: Identifiable {
    var day: Date
    var segments: [ChartSegment]
    var id: Date { day }
    var total: Int64 { segments.reduce(0) { $0 + $1.tokens } }
}

struct ChartSegment: Identifiable {
    var slug: String
    var tokens: Int64
    var id: String { slug }
}

enum ChartSeries {
    static func days(in snapshot: UsageSnapshot, limit: Int?) -> [ChartDay] {
        let calendar = UsageWindow.utc
        var buckets: [Date: [String: Int64]] = [:]
        var cursor = calendar.startOfDay(for: snapshot.chartStart)
        while cursor < snapshot.chartEnd {
            buckets[cursor] = [:]
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        for point in snapshot.dailyPoints {
            let day = calendar.startOfDay(for: point.dayStart)
            guard day >= snapshot.chartStart && day < snapshot.chartEnd else { continue }
            buckets[day, default: [:]][point.productSlug, default: 0] += point.tokens
        }
        var days = buckets.keys.sorted().map { day -> ChartDay in
            let segments = (buckets[day] ?? [:])
                .filter { $0.value > 0 }
                .map { ChartSegment(slug: $0.key, tokens: $0.value) }
                .sorted { ProductSlug.sortIndex($0.slug) < ProductSlug.sortIndex($1.slug) }
            return ChartDay(day: day, segments: segments)
        }
        if let limit, days.count > limit {
            days = Array(days.suffix(limit))
        }
        return days
    }

    /// Tokens on the last UTC day of the chart window. That day is the chart's
    /// last bar, including a day the series reports with no points. An empty
    /// window is 0. `limit` is ignored so a shorter chart still agrees.
    static func tokensToday(in snapshot: UsageSnapshot) -> Int64 {
        days(in: snapshot, limit: nil).last?.total ?? 0
    }

    static func legend(for days: [ChartDay]) -> [ChartSegment] {
        var totals: [String: Int64] = [:]
        for day in days {
            for segment in day.segments {
                totals[segment.slug, default: 0] += segment.tokens
            }
        }
        return totals
            .filter { $0.value > 0 }
            .map { ChartSegment(slug: $0.key, tokens: $0.value) }
            .sorted { ProductSlug.sortIndex($0.slug) < ProductSlug.sortIndex($1.slug) }
    }
}

enum UsagePalette {
    static func color(for slug: String) -> Color {
        switch slug {
        case "grok-bot":
            return Color(red: 0.96, green: 0.62, blue: 0.16)
        case "cursor":
            return Color(red: 0.33, green: 0.52, blue: 0.98)
        case "grok-app-builder":
            return Color(red: 0.16, green: 0.68, blue: 0.64)
        case "grok-tasks":
            return Color(red: 0.93, green: 0.40, blue: 0.26)
        case "grok-chat":
            return Color(red: 0.55, green: 0.36, blue: 0.76)
        default:
            return Color(red: 0.62, green: 0.64, blue: 0.68)
        }
    }
}

struct StackedTokenChart: View {
    var snapshot: UsageSnapshot
    var dayLimit: Int?
    var plotHeight: CGFloat
    var showsScale: Bool
    var showsLegend: Bool
    var legendStyle: LegendStyle

    enum LegendStyle {
        case compact
        case full
    }

    var body: some View {
        let days = ChartSeries.days(in: snapshot, limit: dayLimit)
        let legend = ChartSeries.legend(for: days)
        let maxTotal = max(days.map(\.total).max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 4) {
            Text("Tokens per day")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            if days.allSatisfy({ $0.total == 0 }) {
                Text("No tokens in this window")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: plotHeight, alignment: .center)
            } else {
                HStack(alignment: .top, spacing: 4) {
                    if showsScale {
                        Text(UsageFormat.tokens(maxTotal))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: 48, alignment: .leading)
                    }
                    bars(days: days, maxTotal: maxTotal)
                }
                .accessibilityLabel("Tokens per day by product, peak \(UsageFormat.tokens(maxTotal))")
                if let first = days.first?.day, let last = days.last?.day {
                    HStack {
                        Text(UsageFormat.resetDate(first, timeZone: TimeZone(secondsFromGMT: 0)!))
                        Spacer(minLength: 0)
                        Text(UsageFormat.resetDate(last, timeZone: TimeZone(secondsFromGMT: 0)!))
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, showsScale ? 52 : 0)
                }
            }
            if showsLegend && !legend.isEmpty {
                legendView(legend)
            }
        }
    }

    @ViewBuilder
    private func legendView(_ legend: [ChartSegment]) -> some View {
        switch legendStyle {
        case .compact:
            HStack(spacing: 6) {
                ForEach(legend) { segment in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(UsagePalette.color(for: segment.slug))
                            .frame(width: 5, height: 5)
                        Text(ProductSlug.shortName(for: segment.slug))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        case .full:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 4)], alignment: .leading, spacing: 2) {
                ForEach(legend) { segment in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(UsagePalette.color(for: segment.slug))
                            .frame(width: 6, height: 6)
                        Text(ProductSlug.displayName(for: segment.slug))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func bars(days: [ChartDay], maxTotal: Int64) -> some View {
        HStack(alignment: .bottom, spacing: days.count > 20 ? 1 : 2) {
            ForEach(days) { day in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ForEach(day.segments.reversed()) { segment in
                        Rectangle()
                            .fill(UsagePalette.color(for: segment.slug))
                            .frame(height: height(segment.tokens, maxTotal: maxTotal))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: plotHeight)
                .background(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1)
                }
            }
        }
    }

    private func height(_ tokens: Int64, maxTotal: Int64) -> CGFloat {
        guard maxTotal > 0, tokens > 0 else { return 0 }
        return CGFloat(Double(tokens) / Double(maxTotal)) * plotHeight
    }
}
