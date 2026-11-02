import AppKit
import SwiftUI

enum UsageWidgetSize: String, CaseIterable, Identifiable, Hashable {
    case small
    case medium
    case large

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var previewSize: CGSize {
        switch self {
        case .small:
            return CGSize(width: 162, height: 162)
        case .medium:
            return CGSize(width: 344, height: 162)
        case .large:
            return CGSize(width: 344, height: 344)
        }
    }
}

/// Chrome for hosts that are not a WidgetKit container. The desktop widget
/// leaves content margins enabled, so WidgetKit insets `containerBackground`
/// by `widgetContentMargins` and the view adds no padding of its own. That
/// environment value is zero in ImageRenderer, SwiftUI previews, and the
/// settings card. Those hosts pad by `margin` and clip to the continuous
/// corner so the weekly header clears the radius at the preview size.
enum WidgetPreviewChrome {
    static let margin: CGFloat = 16
    static let cornerRadius: CGFloat = 22
}

struct UsageWidgetRoot: View {
    var family: UsageWidgetSize
    var snapshot: UsageSnapshot?
    var presentation: UsagePresentation
    var now: Date

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        switch presentation {
        case .loading:
            StatusPane(
                title: "Loading usage",
                message: "Fetching grok.com.",
                symbol: "arrow.triangle.2.circlepath"
            )
        case .needsCookie:
            StatusPane(
                title: "Sign in needed",
                message: "Open Grok Widget and sign in to grok.com.",
                symbol: "key"
            )
        case .unavailable:
            StatusPane(
                title: "Unavailable",
                message: unavailableMessage,
                symbol: "exclamationmark.triangle"
            )
        case .sessionExpired where snapshot == nil:
            StatusPane(
                title: "Session expired",
                message: "Sign in again in Grok Widget.",
                symbol: "person.crop.circle.badge.exclamationmark"
            )
        case .failed(let message) where snapshot == nil:
            StatusPane(
                title: "Couldn't refresh",
                message: message,
                symbol: "wifi.exclamationmark"
            )
        default:
            if let snapshot {
                dataLayout(snapshot)
            } else {
                StatusPane(
                    title: "No usage yet",
                    message: "Open Grok Widget and fetch the dashboard.",
                    symbol: "chart.bar"
                )
            }
        }
    }

    private var unavailableMessage: String {
        let raw = snapshot?.availabilityRaw ?? "unavailable"
        if raw == "available" || raw == "unavailable" || raw.isEmpty {
            return "Usage data isn't available right now."
        }
        return "Usage data isn't available (\(raw))."
    }

    private func dataLayout(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let banner = bannerText {
                Banner(text: banner)
            }
            switch family {
            case .small:
                SmallUsageView(snapshot: snapshot, now: now, stale: showsStale)
            case .medium:
                MediumUsageView(snapshot: snapshot, now: now, stale: showsStale)
            case .large:
                LargeUsageView(snapshot: snapshot, now: now, stale: showsStale)
            }
            Spacer(minLength: 0)
        }
    }

    private var showsStale: Bool {
        switch presentation {
        case .stale, .sessionExpired, .failed:
            return snapshot != nil
        default:
            return false
        }
    }

    private var bannerText: String? {
        switch presentation {
        case .sessionExpired:
            return "Session expired. Sign in again."
        case .failed(let message):
            return message
        case .stale:
            return "Stale"
        default:
            return nil
        }
    }
}

struct SmallUsageView: View {
    var snapshot: UsageSnapshot
    var now: Date
    var stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WeeklyBlock(snapshot: snapshot, compact: true)
            Spacer(minLength: 0)
            UpdatedLine(date: snapshot.fetchedAt, now: now, stale: stale)
        }
    }
}

struct MediumUsageView: View {
    var snapshot: UsageSnapshot
    var now: Date
    var stale: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            WeeklyBlock(snapshot: snapshot, compact: true)
                .frame(width: 112)
            VStack(alignment: .leading, spacing: 4) {
                TokenStats(snapshot: snapshot)
                StackedTokenChart(
                    snapshot: snapshot,
                    dayLimit: 14,
                    plotHeight: 22,
                    showsScale: false,
                    showsLegend: true,
                    legendStyle: .compact
                )
                UpdatedLine(date: snapshot.fetchedAt, now: now, stale: stale)
            }
        }
    }
}

struct LargeUsageView: View {
    var snapshot: UsageSnapshot
    var now: Date
    var stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WeeklyBlock(snapshot: snapshot, compact: false)
            TokenStats(snapshot: snapshot)
            StackedTokenChart(
                snapshot: snapshot,
                dayLimit: nil,
                plotHeight: 72,
                showsScale: true,
                showsLegend: true,
                legendStyle: .full
            )
            UpdatedLine(date: snapshot.fetchedAt, now: now, stale: stale)
            Spacer(minLength: 0)
        }
    }
}

struct WeeklyBlock: View {
    var snapshot: UsageSnapshot
    var compact: Bool

    var body: some View {
        let percent = UsageFormat.percent(
            usedCents: snapshot.weeklyUsedCents,
            budgetCents: snapshot.weeklyBudgetCents
        )
        VStack(alignment: .leading, spacing: 4) {
            Text("Weekly included")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(percent)
                    .font(.system(size: compact ? 28 : 40, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            UsageProgressBar(fraction: snapshot.weeklyFraction)
            Text("Resets \(UsageFormat.resetDate(snapshot.weeklyResetAt))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let status = snapshot.weeklyStatus, !status.isEmpty {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if snapshot.additionalUsageOff {
                Text("Additional usage off")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weekly included usage \(percent), resets \(UsageFormat.resetDate(snapshot.weeklyResetAt))")
    }
}

struct UsageProgressBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width * CGFloat(min(max(fraction, 0), 1))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(Color.primary)
                    .frame(width: max(fraction > 0 ? 4 : 0, width))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

struct TokenStats: View {
    var snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(snapshot.rangeLabel)
                    .font(.caption.weight(.semibold))
                if snapshot.rangeDetail != snapshot.rangeLabel {
                    Text(snapshot.rangeDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                StatTile(title: "Total", value: UsageFormat.tokens(snapshot.totalTokens))
                StatTile(title: "Included", value: UsageFormat.tokens(snapshot.includedTokens))
                StatTile(
                    title: "Tokens today",
                    value: UsageFormat.tokens(ChartSeries.tokensToday(in: snapshot))
                )
            }
            if let caption = snapshot.totalsModeCaption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}

struct StatTile: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct UpdatedLine: View {
    var date: Date
    var now: Date
    var stale: Bool

    var body: some View {
        Text(stale ? "Stale · \(UsageFormat.lastUpdated(date, now: now))" : UsageFormat.lastUpdated(date, now: now))
            .font(.caption2)
            .foregroundStyle(stale ? Color.orange : Color.secondary)
            .lineLimit(1)
    }
}

struct Banner: View {
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(2)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct StatusPane: View {
    var title: String
    var message: String
    var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}
