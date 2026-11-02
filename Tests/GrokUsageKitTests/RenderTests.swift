import AppKit
import SwiftUI
import XCTest

@MainActor
final class RenderTests: XCTestCase {
    func testRendersFixtureAndStatusStates() throws {
        let directory = URL(fileURLWithPath: "/tmp/grok-widget-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cases: [(String, UsageWidgetSize, UsagePresentation, UsageSnapshot?)] = [
            ("small", .small, .fresh, .screenshotFixture),
            ("medium", .medium, .fresh, .screenshotFixture),
            ("large", .large, .fresh, .screenshotFixture),
            ("medium-expired", .medium, .sessionExpired, .screenshotFixture),
            ("small-cookie", .small, .needsCookie, nil),
            ("large-unavailable", .large, .unavailable, unavailableSnapshot()),
        ]
        for item in cases {
            let data = try png(family: item.1, presentation: item.2, snapshot: item.3)
            let url = directory.appendingPathComponent("\(item.0).png")
            try data.write(to: url)
            XCTAssertEqual(data.prefix(8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), item.0)
            XCTAssertGreaterThan(data.count, 2_000, item.0)
        }
    }

    private func png(family: UsageWidgetSize, presentation: UsagePresentation, snapshot: UsageSnapshot?) throws -> Data {
        let size = family.previewSize
        let view = UsageWidgetRoot(
            family: family,
            snapshot: snapshot,
            presentation: presentation,
            now: UsageSnapshot.screenshotFetchedAt
        )
        .padding(12)
        .frame(width: size.width, height: size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        guard let image = renderer.nsImage else {
            XCTFail("ImageRenderer returned nil for \(family)")
            return Data()
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("PNG conversion failed for \(family)")
            return Data()
        }
        return png
    }

    private func unavailableSnapshot() -> UsageSnapshot {
        var snapshot = UsageSnapshot.screenshotFixture
        snapshot.availabilityRaw = "unavailable"
        return snapshot
    }
}
