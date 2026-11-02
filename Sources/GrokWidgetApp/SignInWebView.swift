import SwiftUI
import WebKit
import WidgetKit

/// Persistent store for the in-app grok.com session.
/// This is the app's own WKWebsiteDataStore. Safari and Chrome are never read.
enum GrokWebDataStore {
    static let identifier = UUID(uuidString: "C4FEA11C-6B0D-4E2A-9F17-0A6D8E3B5C91")!

    static func websiteDataStore() -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: identifier)
    }
}

enum PersistentGrokCookies {
    @MainActor
    static func snapshots() async -> [HTTPCookieSnapshot] {
        let store = GrokWebDataStore.websiteDataStore().httpCookieStore
        let cookies = await cookies(from: store)
        return cookies.map(HTTPCookieSnapshot.init)
    }

    @MainActor
    static func cookies(from store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            MainActor.assumeIsolated {
                store.getAllCookies { cookies in
                    continuation.resume(returning: cookies)
                }
            }
        }
    }
}

enum SignInSession {
    @MainActor
    static func reharvest(store: CookieStoring = KeychainCookieStore()) async -> ReharvestOutcome {
        let outcome = await SessionReharvest(
            readCookies: { await PersistentGrokCookies.snapshots() },
            probe: { header in await UsageStatusProbe.succeeds(cookieHeader: header) },
            save: { header in try store.save(header) }
        ).run()
        if outcome == .recovered {
            WidgetCenter.shared.reloadAllTimelines()
            WidgetCenter.shared.reloadTimelines(ofKind: SharedStorage.widgetKind)
        }
        return outcome
    }
}

struct SignInWebView: NSViewRepresentable {
    var onSignedIn: () -> Void
    var onStatus: (String) -> Void

    func makeCoordinator() -> GrokSignInObserver {
        GrokSignInObserver(onSignedIn: onSignedIn, onStatus: onStatus)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = GrokWebDataStore.websiteDataStore()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        // Desktop Safari UA. Google rejects the default WKWebView UA as disallowed_useragent.
        webView.customUserAgent = DashboardEndpoints.userAgent
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.attach(webView)
        webView.load(URLRequest(url: URL(string: DashboardEndpoints.referer)!))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onSignedIn = onSignedIn
        context.coordinator.onStatus = onStatus
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: GrokSignInObserver) {
        coordinator.detach(webView)
    }
}

/// Watches the web view cookie store. Closes only after usage-status returns 200 JSON.
/// Cookie values are never logged.
final class GrokSignInObserver: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    var onSignedIn: () -> Void
    var onStatus: (String) -> Void
    private var generation = 0
    private var didSucceed = false
    private weak var webView: WKWebView?

    init(onSignedIn: @escaping () -> Void, onStatus: @escaping (String) -> Void) {
        self.onSignedIn = onSignedIn
        self.onStatus = onStatus
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
        webView.configuration.websiteDataStore.httpCookieStore.add(self)
    }

    func detach(_ webView: WKWebView) {
        generation += 1
        webView.configuration.websiteDataStore.httpCookieStore.remove(self)
        self.webView = nil
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        scheduleHarvest(from: cookieStore)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        scheduleHarvest(from: webView.configuration.websiteDataStore.httpCookieStore)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    private func scheduleHarvest(from cookieStore: WKHTTPCookieStore) {
        Task { @MainActor [weak self] in
            guard let self, !self.didSucceed else { return }
            self.generation += 1
            let token = self.generation
            let cookies = await PersistentGrokCookies.cookies(from: cookieStore)
            let snapshots = cookies.map(HTTPCookieSnapshot.init)
            try? await Task.sleep(nanoseconds: 600_000_000)
            await self.harvest(snapshots: snapshots, token: token)
        }
    }

    @MainActor
    private func harvest(snapshots: [HTTPCookieSnapshot], token: Int) async {
        guard token == generation, !didSucceed else { return }
        let outcome = await SessionReharvest(
            readCookies: { snapshots },
            probe: { header in await UsageStatusProbe.succeeds(cookieHeader: header) },
            save: { header in try KeychainCookieStore().save(header) }
        ).run()
        guard token == generation, !didSucceed else { return }
        switch outcome {
        case .recovered:
            didSucceed = true
            webView?.configuration.websiteDataStore.httpCookieStore.remove(self)
            WidgetCenter.shared.reloadAllTimelines()
            WidgetCenter.shared.reloadTimelines(ofKind: SharedStorage.widgetKind)
            onSignedIn()
        case .signInAgain:
            break
        case .saveFailed(let message):
            onStatus(message)
        }
    }
}

struct SignInView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @EnvironmentObject private var coordinator: SignInCoordinator
    @State private var status = "Sign in on grok.com. This window closes once usage-status accepts the session."

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(status)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text("Google sometimes blocks embedded windows (“this browser or app may not be secure”). This window sends a desktop Safari user agent, which is the usual workaround and still sometimes fails. X or email sign-in, including a verification code, stays in this window. Safari and Chrome cookie stores are not read. If sign-in is refused, use Advanced in the main window.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SignInWebView(
                onSignedIn: {
                    coordinator.noteInteractiveSignIn()
                    dismissWindow(id: "sign-in")
                },
                onStatus: { status = $0 }
            )
        }
        .padding(16)
        .frame(minWidth: 800, minHeight: 560)
    }
}
