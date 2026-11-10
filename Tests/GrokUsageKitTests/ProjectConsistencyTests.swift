import Foundation
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
        XCTAssertTrue(readme.contains("Sign in to grok.com"))
        XCTAssertTrue(readme.contains("./scripts/install.sh"))
        XCTAssertTrue(readme.contains("GrokWidgetApp"))
        XCTAssertTrue(project.contains("GrokWidgetApp:"))
        XCTAssertTrue(project.contains("GrokWidgetExtension:"))
        XCTAssertTrue(project.contains("executable: GrokWidget"))

        let appScheme = try String(
            contentsOf: root.appendingPathComponent("GrokWidget.xcodeproj/xcshareddata/xcschemes/GrokWidgetApp.xcscheme"),
            encoding: .utf8
        )
        XCTAssertTrue(appScheme.contains("BuildableName = \"GrokWidget.app\""))
        XCTAssertFalse(appScheme.contains("wasCreatedForAppExtension"))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("GrokWidget.xcodeproj/xcshareddata/xcschemes/GrokWidget.xcscheme").path
            )
        )

        let signIn = try String(contentsOf: root.appendingPathComponent("Sources/GrokWidgetApp/SignInWebView.swift"), encoding: .utf8)
        let widget = try String(contentsOf: root.appendingPathComponent("Sources/GrokUsageWidget/GrokUsageWidget.swift"), encoding: .utf8)
        XCTAssertTrue(signIn.contains("customUserAgent = DashboardEndpoints.userAgent"))
        XCTAssertTrue(signIn.contains("WKWebsiteDataStore(forIdentifier:"))
        XCTAssertFalse(signIn.contains("HTTPCookieStorage"))
        XCTAssertFalse(signIn.contains("binarycookies"))
        XCTAssertFalse(signIn.contains("WKWebsiteDataStore.default()"))
        XCTAssertTrue(widget.contains(".widgetURL(AppLink.widgetURL(for: entry.presentation))"))
        XCTAssertFalse(widget.contains("widgetURL(entry.presentation == .sessionExpired"))
        XCTAssertFalse(widget.contains("contentMarginsDisabled"))
        XCTAssertFalse(widget.contains(".padding(12)"))
        let info = try String(contentsOf: root.appendingPathComponent("Config/InfoAdditions.plist"), encoding: .utf8)
        XCTAssertTrue(info.contains("grokwidget"))
        let links = try String(contentsOf: root.appendingPathComponent("Sources/GrokUsageKit/CookieHarvest.swift"), encoding: .utf8)
        XCTAssertTrue(links.contains("URL(string: \"grokwidget://sign-in\")"))
        XCTAssertTrue(appEntitlements.contains("com.apple.security.cs.allow-jit"))

        let app = try String(contentsOf: root.appendingPathComponent("Sources/GrokWidgetApp/GrokWidgetApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains(".onOpenURL"))
        XCTAssertTrue(app.contains(".handlesExternalEvents(matching: [\"*\"])"))
        XCTAssertTrue(app.contains(".widgetURL") == false)
        XCTAssertFalse(app.contains("URLTrace"))
        XCTAssertFalse(app.contains("osascript"))
        XCTAssertFalse(app.contains("System Events"))

        let install = try String(contentsOf: root.appendingPathComponent("scripts/install.sh"), encoding: .utf8)
        XCTAssertTrue(install.contains("pkill -x GrokWidget"))
        XCTAssertTrue(install.contains("pluginkit -r"))
        XCTAssertTrue(install.contains("lsregister\" -u"))
        XCTAssertTrue(install.contains("killall chronod"))
        XCTAssertTrue(install.contains("--clean"))
        XCTAssertTrue(install.contains("open \"$dest\""))
        XCTAssertFalse(install.contains("osascript"))
        XCTAssertFalse(install.contains("System Events"))
    }

    func testResignKeepsTheFreeTeamProfileFresh() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resign = try String(contentsOf: root.appendingPathComponent("scripts/resign.sh"), encoding: .utf8)
        let agent = try String(contentsOf: root.appendingPathComponent("scripts/install-resign-agent.sh"), encoding: .utf8)
        let makefile = try String(contentsOf: root.appendingPathComponent("Makefile"), encoding: .utf8)
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)

        XCTAssertTrue(resign.contains("-allowProvisioningUpdates"))
        XCTAssertTrue(resign.contains("codesign --verify --deep --strict"))
        XCTAssertTrue(resign.contains("ExpirationDate"))
        XCTAssertTrue(resign.contains("pluginkit -a"))
        XCTAssertTrue(resign.contains("display notification"))
        XCTAssertTrue(resign.contains("group.com.charlesdardaman.grok-widget"))
        XCTAssertTrue(resign.contains("com.charlesdardaman.grok-widget.shared"))
        XCTAssertTrue(resign.contains("--simulate-failure"))
        XCTAssertTrue(resign.contains("--simulate-expiring"))
        XCTAssertFalse(resign.contains("pluginkit -r"))

        XCTAssertTrue(agent.contains("com.charlesdardaman.grok-widget.resign"))
        XCTAssertTrue(agent.contains("StartCalendarInterval"))
        XCTAssertTrue(agent.contains("RunAtLoad"))
        XCTAssertTrue(agent.contains("--uninstall"))
        XCTAssertTrue(agent.contains("Library/LaunchAgents"))

        XCTAssertTrue(makefile.contains("install-resign-agent:"))
        XCTAssertTrue(makefile.contains("uninstall-resign-agent:"))
        XCTAssertTrue(readme.contains("make install-resign-agent"))
        XCTAssertTrue(readme.contains("make uninstall-resign-agent"))
        XCTAssertTrue(readme.contains("within 3 days"))
        XCTAssertTrue(readme.contains("within 48 hours"))
        XCTAssertTrue(readme.contains("~/Library/Logs/GrokWidget/resign.log"))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent("scripts/resign.sh").path, "--self-test"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, text)
        XCTAssertTrue(text.contains("self-test ok"), text)
    }
}
