import XCTest

final class ProjectConsistencyTests: XCTestCase {
    func testSharedIdentifiersMatchEntitlementsAndProject() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appEntitlements = try String(contentsOf: root.appendingPathComponent("Sources/GrokWidgetApp/GrokWidget.entitlements"), encoding: .utf8)
        let widgetEntitlements = try String(contentsOf: root.appendingPathComponent("Sources/GrokUsageWidget/GrokUsageWidget.entitlements"), encoding: .utf8)
        let project = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)

        for text in [appEntitlements, widgetEntitlements] {
            XCTAssertTrue(text.contains(SharedStorage.appGroupID))
            XCTAssertTrue(text.contains(SharedStorage.keychainAccessGroupSuffix))
            XCTAssertTrue(text.contains("com.apple.security.network.client"))
            XCTAssertTrue(text.contains("com.apple.security.app-sandbox"))
        }
        XCTAssertTrue(project.contains("MACOSX_DEPLOYMENT_TARGET: \"14.0\""))
        XCTAssertTrue(project.contains("com.charlesdardaman.grok-widget.widget"))
        XCTAssertTrue(project.contains("CODE_SIGN_STYLE: Automatic"))
        XCTAssertTrue(readme.contains("DEVELOPMENT_TEAM"))
        XCTAssertTrue(readme.contains("Edit Widgets"))
        XCTAssertTrue(readme.contains("CODE_SIGNING_ALLOWED=NO"))
    }
}
