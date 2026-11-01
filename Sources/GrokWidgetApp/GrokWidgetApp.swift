import SwiftUI

@main
struct GrokWidgetApp: App {
    var body: some Scene {
        Window("Grok Usage", id: "main") {
            SettingsView()
        }
        .defaultSize(width: 560, height: 760)
        .windowResizability(.contentMinSize)
    }
}
