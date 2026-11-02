import SwiftUI
import WidgetKit

struct SettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var coordinator: SignInCoordinator

    @State private var cookieDraft = ""
    @State private var cookieSaved = false
    @State private var statusMessage = "Sign in to grok.com. The session is saved in the Keychain."
    @State private var isWorking = false
    @State private var previewSnapshot: UsageSnapshot? = .screenshotFixture
    @State private var previewPresentation: UsagePresentation = .fresh
    @State private var previewIsSample = true
    @State private var previewSize: UsageWidgetSize = .medium

    private let store = KeychainCookieStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                signInSection
                fetchSection
                previewSection
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(minWidth: 520, minHeight: 640)
        .onAppear(perform: refreshSavedFlag)
        .onChange(of: coordinator.sessionRevision) { _, _ in
            refreshSavedFlag()
        }
        .onChange(of: coordinator.banner) { _, banner in
            if let banner {
                statusMessage = banner
            }
        }
        .onChange(of: coordinator.openSignIn) { _, open in
            guard open else { return }
            openWindow(id: "sign-in")
            coordinator.openSignIn = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Grok Usage")
                .font(.title2.weight(.semibold))
            Text("Desktop widget for grok.com/dashboard/usage. Sign in inside this app. The widget reads the session from the shared Keychain.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var signInSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session")
                .font(.headline)
            Text(cookieSaved ? "A session cookie is saved in the Keychain." : "No cookie saved yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Sign in to grok.com") {
                openWindow(id: "sign-in")
            }
            .keyboardShortcut(.defaultAction)
            Text("Opens grok.com in this app. Log in there, including SSO or a verification code. When usage-status accepts the session, the cookie is saved and the window closes. If the widget says the session expired, this app tries that saved sign-in again before asking you to sign in.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Advanced") {
                advancedCookieFields
            }
            if !keychainSharingAvailable {
                Text("Keychain sharing with the widget needs a Development Team. Unsigned builds keep the cookie in this app’s keychain only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var advancedCookieFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste a Cookie header if the sign-in window cannot complete login. It is stored in the Keychain shared with the widget and is not written to disk or the repo.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("Cookie header", text: $cookieDraft)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Save") { saveCookie() }
                    .disabled(cookieDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Clear") { clearCookie() }
                    .disabled(!cookieSaved && cookieDraft.isEmpty)
            }
            Text("Clear removes the Keychain copy only. The sign-in window keeps its own session until you log out there.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private var fetchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raw responses")
                .font(.headline)
            Text(RawResponseDump.defaultDirectory.path)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Text("Writes last_usage_status.json, last_daily_usage.json, and last_daily_usage_request.json. The request file is the JSON body, not the cookie.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(isWorking ? "Fetching…" : "Fetch and save raw JSON") {
                Task { await fetch() }
            }
            .disabled(isWorking || !cookieSaved)
            Text(statusMessage)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Widget preview")
                    .font(.headline)
                Spacer()
                Picker("Size", selection: $previewSize) {
                    ForEach(UsageWidgetSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            Text(previewIsSample ? "Showing the October screenshot sample until a fetch succeeds." : "Showing the last fetch.")
                .font(.caption)
                .foregroundStyle(.secondary)
            UsageWidgetRoot(
                family: previewSize,
                snapshot: previewSnapshot,
                presentation: previewPresentation,
                now: previewSnapshot?.fetchedAt ?? Date()
            )
            .padding(12)
            .frame(width: previewSize.previewSize.width, height: previewSize.previewSize.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.08))
            )
            Text("Add it from the desktop: right-click, Edit Widgets, then Grok Usage. macOS refreshes the timeline about every 15 minutes. Signing in reloads it. A session-expired widget opens this app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var keychainSharingAvailable: Bool {
        SharedStorage.resolvedKeychainAccessGroup() != nil
    }

    private func refreshSavedFlag() {
        do {
            cookieSaved = try store.hasCookie()
            if let cached = UsageCache().load() {
                previewSnapshot = cached
                previewPresentation = cached.isAvailable ? .fresh : .unavailable
                previewIsSample = false
            }
        } catch {
            cookieSaved = false
            statusMessage = error.localizedDescription
        }
    }

    private func saveCookie() {
        let normalized = CookieHeader.normalize(cookieDraft)
        guard !normalized.isEmpty else {
            statusMessage = "Paste a Cookie header first."
            return
        }
        do {
            try store.save(normalized)
            cookieDraft = ""
            cookieSaved = true
            statusMessage = "Saved to the Keychain."
            reloadTimelines()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func clearCookie() {
        do {
            try store.clear()
            cookieDraft = ""
            cookieSaved = false
            statusMessage = "Removed the cookie from the Keychain."
            reloadTimelines()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func fetch() async {
        isWorking = true
        defer { isWorking = false }
        await performFetch(allowReharvest: true)
    }

    private func performFetch(allowReharvest: Bool) async {
        let cookie: String
        do {
            guard let stored = try store.load(), !CookieHeader.normalize(stored).isEmpty else {
                statusMessage = "Sign in to grok.com first."
                cookieSaved = false
                return
            }
            cookie = stored
        } catch {
            statusMessage = error.localizedDescription
            return
        }

        let capture = ResponseCapture()
        let dump = RawResponseDump(directory: RawResponseDump.defaultDirectory)
        do {
            let result = try await GrokWebUsageProvider(cookieHeader: cookie).fetchRaw(capture: capture)
            _ = try dump.write(result: result, cookie: cookie)
            try? UsageCache().save(result.snapshot)
            previewSnapshot = result.snapshot
            previewPresentation = result.snapshot.isAvailable ? .fresh : .unavailable
            previewIsSample = false
            statusMessage = "\(UsageSummary.line(for: result.snapshot))\n\(dump.directory.path)"
            reloadTimelines()
        } catch {
            try? dump.writeFailure(capture: capture, error: error, cookie: cookie)
            if allowReharvest, error as? UsageFetchError == .sessionExpired {
                statusMessage = "Session expired. Checking the saved sign-in…"
                switch await SignInSession.reharvest() {
                case .recovered:
                    cookieSaved = true
                    statusMessage = "Session refreshed. Fetching again…"
                    await performFetch(allowReharvest: false)
                case .signInAgain:
                    previewPresentation = .sessionExpired
                    statusMessage = "Sign in again."
                    coordinator.openSignIn = true
                case .saveFailed(let message):
                    previewPresentation = .sessionExpired
                    statusMessage = message
                }
                return
            }
            statusMessage = "\(UsageFetchError.redact(error.localizedDescription, cookie: cookie))\nSaved what came back in \(dump.directory.path)."
            if error as? UsageFetchError == .sessionExpired {
                previewPresentation = .sessionExpired
            }
        }
    }

    private func reloadTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
        WidgetCenter.shared.reloadTimelines(ofKind: SharedStorage.widgetKind)
    }
}
