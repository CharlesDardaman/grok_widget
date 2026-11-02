import AppKit
import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    var date: Date
    var snapshot: UsageSnapshot?
    var presentation: UsagePresentation
}

struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: UsageSnapshot.screenshotFetchedAt, snapshot: .screenshotFixture, presentation: .fresh)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(UsageEntry(date: UsageSnapshot.screenshotFetchedAt, snapshot: .screenshotFixture, presentation: .fresh))
            return
        }
        let now = Date()
        if let cached = UsageCache().load() {
            let stale = UsageRefresh.isStale(fetchedAt: cached.fetchedAt, now: now)
            completion(UsageEntry(date: now, snapshot: cached, presentation: stale ? .stale : .fresh))
        } else {
            completion(UsageEntry(date: now, snapshot: nil, presentation: .loading))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let now = Date()
            let loaded = await UsageLoader().load(now: now)
            let entry = UsageEntry(date: now, snapshot: loaded.snapshot, presentation: loaded.presentation)
            let timeline = Timeline(entries: [entry], policy: .after(UsageRefresh.nextRefresh(after: now)))
            completion(timeline)
        }
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: UsageEntry

    var body: some View {
        // No extra padding. Content margins stay enabled so WidgetKit insets
        // this view by `widgetContentMargins`, which clears the corner at
        // every family. A fixed 12pt pad sat inside that radius.
        UsageWidgetRoot(
            family: size(for: family),
            snapshot: entry.snapshot,
            presentation: entry.presentation,
            now: entry.date
        )
    }

    private func size(for family: WidgetFamily) -> UsageWidgetSize {
        switch family {
        case .systemSmall:
            return .small
        case .systemMedium:
            return .medium
        default:
            return .large
        }
    }
}

struct GrokUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStorage.widgetKind, provider: UsageTimelineProvider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(Color(nsColor: .windowBackgroundColor), for: .widget)
                .widgetURL(AppLink.widgetURL(for: entry.presentation))
        }
        .configurationDisplayName("Grok Usage")
        .description("Weekly included usage, token totals, and tokens per day from grok.com.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct GrokUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        GrokUsageWidget()
    }
}
