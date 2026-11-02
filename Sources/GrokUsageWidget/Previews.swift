import AppKit
import SwiftUI

#Preview("Small") {
    UsageWidgetRoot(
        family: .small,
        snapshot: .screenshotFixture,
        presentation: .fresh,
        now: UsageSnapshot.screenshotFetchedAt
    )
    .padding(12)
    .frame(width: 162, height: 162)
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Medium") {
    UsageWidgetRoot(
        family: .medium,
        snapshot: .screenshotFixture,
        presentation: .fresh,
        now: UsageSnapshot.screenshotFetchedAt
    )
    .padding(12)
    .frame(width: 344, height: 162)
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Large") {
    UsageWidgetRoot(
        family: .large,
        snapshot: .screenshotFixture,
        presentation: .fresh,
        now: UsageSnapshot.screenshotFetchedAt
    )
    .padding(12)
    .frame(width: 344, height: 344)
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Session expired") {
    UsageWidgetRoot(
        family: .medium,
        snapshot: .screenshotFixture,
        presentation: .sessionExpired,
        now: UsageSnapshot.screenshotFetchedAt
    )
    .padding(12)
    .frame(width: 344, height: 162)
    .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Cookie needed") {
    UsageWidgetRoot(
        family: .small,
        snapshot: nil,
        presentation: .needsCookie,
        now: Date()
    )
    .padding(12)
    .frame(width: 162, height: 162)
    .background(Color(nsColor: .windowBackgroundColor))
}
