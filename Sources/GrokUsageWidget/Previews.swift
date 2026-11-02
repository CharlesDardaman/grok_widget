import AppKit
import SwiftUI

#Preview("Small") {
    UsageWidgetRoot(
        family: .small,
        snapshot: .screenshotFixture,
        presentation: .fresh,
        now: UsageSnapshot.screenshotFetchedAt
    )
    .padding(WidgetPreviewChrome.margin)
    .frame(width: 162, height: 162)
    .background(Color(nsColor: .windowBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: WidgetPreviewChrome.cornerRadius, style: .continuous))
}

#Preview("Medium") {
    UsageWidgetRoot(
        family: .medium,
        snapshot: .screenshotFixture,
        presentation: .fresh,
        now: UsageSnapshot.screenshotFetchedAt
    )
    .padding(WidgetPreviewChrome.margin)
    .frame(width: 344, height: 162)
    .background(Color(nsColor: .windowBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: WidgetPreviewChrome.cornerRadius, style: .continuous))
}

#Preview("Large") {
    UsageWidgetRoot(
        family: .large,
        snapshot: .screenshotFixture,
        presentation: .fresh,
        now: UsageSnapshot.screenshotFetchedAt
    )
    .padding(WidgetPreviewChrome.margin)
    .frame(width: 344, height: 344)
    .background(Color(nsColor: .windowBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: WidgetPreviewChrome.cornerRadius, style: .continuous))
}

#Preview("Session expired") {
    UsageWidgetRoot(
        family: .medium,
        snapshot: .screenshotFixture,
        presentation: .sessionExpired,
        now: UsageSnapshot.screenshotFetchedAt
    )
    .padding(WidgetPreviewChrome.margin)
    .frame(width: 344, height: 162)
    .background(Color(nsColor: .windowBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: WidgetPreviewChrome.cornerRadius, style: .continuous))
}

#Preview("Cookie needed") {
    UsageWidgetRoot(
        family: .small,
        snapshot: nil,
        presentation: .needsCookie,
        now: Date()
    )
    .padding(WidgetPreviewChrome.margin)
    .frame(width: 162, height: 162)
    .background(Color(nsColor: .windowBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: WidgetPreviewChrome.cornerRadius, style: .continuous))
}
