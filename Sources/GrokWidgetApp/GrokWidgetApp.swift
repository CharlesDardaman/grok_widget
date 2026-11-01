import SwiftUI

@MainActor
final class SignInCoordinator: ObservableObject {
    @Published var banner: String?
    @Published var openSignIn = false
    @Published var sessionRevision = 0
    private var handlingLink = false

    func handle(_ url: URL) async {
        guard AppLink.isSignIn(url) else { return }
        guard !handlingLink else { return }
        handlingLink = true
        defer { handlingLink = false }
        let outcome = await SignInSession.reharvest()
        apply(outcome)
    }

    func noteInteractiveSignIn() {
        sessionRevision += 1
        banner = "Signed in. Widget timelines were reloaded."
        openSignIn = false
    }

    private func apply(_ outcome: ReharvestOutcome) {
        switch outcome {
        case .recovered:
            sessionRevision += 1
            banner = "Session refreshed."
            openSignIn = false
        case .signInAgain:
            banner = "Sign in again."
            openSignIn = true
        case .saveFailed(let message):
            banner = message
            openSignIn = false
        }
    }
}

@main
struct GrokWidgetApp: App {
    @StateObject private var coordinator = SignInCoordinator()

    var body: some Scene {
        Window("Grok Usage", id: "main") {
            SettingsView()
                .environmentObject(coordinator)
                .onOpenURL { url in
                    Task { await coordinator.handle(url) }
                }
        }
        .defaultSize(width: 560, height: 780)
        .windowResizability(.contentMinSize)

        Window("Sign in to grok.com", id: "sign-in") {
            SignInView()
                .environmentObject(coordinator)
                .onOpenURL { url in
                    Task { await coordinator.handle(url) }
                }
        }
        .defaultSize(width: 960, height: 760)
        .windowResizability(.contentMinSize)
    }
}
