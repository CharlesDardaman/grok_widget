import AppKit
import CoreServices
import SwiftUI
import WidgetKit

enum WidgetReload {
    static func all() {
        WidgetCenter.shared.reloadAllTimelines()
        WidgetCenter.shared.reloadTimelines(ofKind: SharedStorage.widgetKind)
    }
}

enum AppForeground {
    /// Brings this app forward with AppKit.
    static func activate() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        for window in app.windows where window.styleMask.contains(.titled) && !window.isSheet {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    /// The sign-in sheet is 800pt wide. The settings window starts narrower, so grow it
    /// before presenting or SwiftUI drops the sheet.
    static func fitSignInSheet() {
        activate()
        applySignInFrame()
        DispatchQueue.main.async { applySignInFrame() }
    }

    private static func applySignInFrame() {
        let target = NSSize(width: 960, height: 820)
        for window in NSApplication.shared.windows {
            guard window.styleMask.contains(.titled), !window.isSheet else { continue }
            var frame = window.frame
            guard frame.size != target else {
                window.makeKeyAndOrderFront(nil)
                continue
            }
            frame.origin.y -= target.height - frame.size.height
            frame.size = target
            window.setFrame(frame, display: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@MainActor
final class SignInCoordinator: ObservableObject {
    @Published var banner: String?
    @Published var presentSignIn = false
    @Published var sessionRevision = 0
    private var handlingLink = false
    private var lastLinkAt: [String: Date] = [:]

    func handle(_ url: URL) async {
        guard AppLink.isAppLink(url) else { return }
        let key = url.absoluteString.lowercased()
        if let last = lastLinkAt[key], Date().timeIntervalSince(last) < 1 {
            return
        }
        lastLinkAt[key] = Date()
        AppForeground.activate()
        guard AppLink.isSignIn(url) else { return }

        // A sheet that is already true on first layout does not present.
        if presentSignIn {
            presentSignIn = false
            await Task.yield()
        }
        AppForeground.fitSignInSheet()
        presentSignIn = true

        guard !handlingLink else { return }
        handlingLink = true
        defer { handlingLink = false }
        let outcome = await SignInSession.reharvest()
        switch outcome {
        case .recovered:
            sessionRevision += 1
            banner = "Session refreshed."
            presentSignIn = false
            WidgetReload.all()
        case .signInAgain:
            banner = "Sign in again."
            presentSignIn = true
            AppForeground.fitSignInSheet()
        case .saveFailed(let message):
            banner = message
            presentSignIn = true
            AppForeground.fitSignInSheet()
        }
    }

    func noteInteractiveSignIn() {
        sessionRevision += 1
        banner = "Signed in. Widget timelines were reloaded."
        presentSignIn = false
        WidgetReload.all()
    }
}

/// Receives `grokwidget://` opens. This is the app's own URL event, not a script
/// that controls another process.
final class GrokGetURLHandler: NSObject {
    static let shared = GrokGetURLHandler()
    var receiver: ((URL) -> Void)?

    func install() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handle(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc func handle(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: raw),
              let receiver else { return }
        if Thread.isMainThread {
            receiver(url)
        } else {
            DispatchQueue.main.async { receiver(url) }
        }
    }

    static func url(from event: NSAppleEventDescriptor?) -> URL? {
        guard let event,
              event.eventClass == AEEventClass(kInternetEventClass),
              event.eventID == AEEventID(kAEGetURL),
              let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else {
            return nil
        }
        return URL(string: raw)
    }
}

@MainActor
final class GrokWidgetAppDelegate: NSObject, NSApplicationDelegate {
    var coordinator: SignInCoordinator?
    private var pendingURLs: [URL] = []
    private var isReady = false

    override init() {
        super.init()
        let handler = GrokGetURLHandler.shared
        handler.receiver = { [weak self] url in
            Task { @MainActor in
                self?.accept([url])
            }
        }
        handler.install()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        GrokGetURLHandler.shared.install()
        captureLaunchURL()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI installs its own handler during launch. Put ours back so a
        // later `open grokwidget://sign-in` still reaches the sign-in sheet.
        GrokGetURLHandler.shared.install()
        captureLaunchURL()
        AppForeground.activate()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        accept(urls)
    }

    func accept(_ urls: [URL]) {
        for url in urls where AppLink.isAppLink(url) && !pendingURLs.contains(url) {
            pendingURLs.append(url)
        }
        drainIfReady()
    }

    func markReady() {
        isReady = true
        drainIfReady()
    }

    private func captureLaunchURL() {
        guard let url = GrokGetURLHandler.url(from: NSAppleEventManager.shared().currentAppleEvent) else { return }
        accept([url])
    }

    private func drainIfReady() {
        guard isReady, let coordinator else { return }
        let batch = pendingURLs
        pendingURLs = []
        guard !batch.isEmpty else { return }
        Task { @MainActor in
            AppForeground.activate()
            for url in batch {
                await coordinator.handle(url)
            }
        }
    }
}

@main
struct GrokWidgetApp: App {
    @NSApplicationDelegateAdaptor(GrokWidgetAppDelegate.self) private var appDelegate
    @StateObject private var coordinator = SignInCoordinator()

    init() {
        GrokGetURLHandler.shared.install()
    }

    var body: some Scene {
        Window("Grok Usage", id: "main") {
            MainWindow(appDelegate: appDelegate)
                .environmentObject(coordinator)
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        // Match every external-event identifier. Matching only "grokwidget"
        // drops the open event, so onOpenURL never runs and the click does nothing.
        .handlesExternalEvents(matching: ["*"])
        .defaultSize(width: 560, height: 780)
        .windowResizability(.contentMinSize)
    }
}

struct MainWindow: View {
    @EnvironmentObject private var coordinator: SignInCoordinator
    var appDelegate: GrokWidgetAppDelegate

    var body: some View {
        SettingsView()
            .onOpenURL { url in
                appDelegate.accept([url])
            }
            .onAppear {
                appDelegate.coordinator = coordinator
                Task { @MainActor in
                    // Let the window exist before a sheet is requested.
                    await Task.yield()
                    AppForeground.activate()
                    appDelegate.markReady()
                }
            }
            .onChange(of: coordinator.presentSignIn) { _, isPresented in
                if isPresented {
                    AppForeground.fitSignInSheet()
                }
            }
            .sheet(isPresented: Binding(
                get: { coordinator.presentSignIn },
                set: { coordinator.presentSignIn = $0 }
            )) {
                SignInView()
                    .environmentObject(coordinator)
            }
    }
}
