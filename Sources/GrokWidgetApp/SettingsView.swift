import SwiftUI
import WidgetKit

struct SettingsView: View {
    @State private var cookieDraft = ""
    @State private var cookieSaved = false
    @State private var statusMessage = "Paste the Cookie header from the usage-status request."
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
                cookieSection
                fetchSection
                previewSection
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(minWidth: 520, minHeight: 640)
        .onAppear(perform: refreshSavedFlag)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Grok Usage")
                .font(.title2.weight(.semibold))
            Text("Desktop widget for grok.com/dashboard/usage. This window only stores the session cookie and can save the raw responses for inspection.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cookieSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session cookie")
                .font(.headline)
            Text(cookieSaved ? "A session cookie is saved in the Keychain." : "No cookie saved yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
            SecureField("Cookie header", text: $cookieDraft)
                .textFieldStyle(.roundedBorder)
            Text("In Safari or Chrome, open the dashboard, select the usage-status request, and copy its Cookie header. It is stored in the Keychain shared with the widget and is not written to disk or the repo.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Save") { saveCookie() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(cookieDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Clear") { clearCookie() }
                    .disabled(!cookieSaved && cookieDraft.isEmpty)
            }
            if !keychainSharingAvailable {
                Text("Keychain sharing with the widget needs a Development Team. Unsigned builds keep the cookie in this app’s keychain only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
            Text("Add it from the desktop: right-click, Edit Widgets, then Grok Usage. macOS refreshes the timeline about every 15 minutes, and saving a cookie reloads it.")
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
            WidgetCenter.shared.reloadTimelines(ofKind: SharedStorage.widgetKind)
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
            WidgetCenter.shared.reloadTimelines(ofKind: SharedStorage.widgetKind)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func fetch() async {
        let cookie: String
        do {
            guard let stored = try store.load(), !CookieHeader.normalize(stored).isEmpty else {
                statusMessage = "Save a cookie first."
                cookieSaved = false
                return
            }
            cookie = stored
        } catch {
            statusMessage = error.localizedDescription
            return
        }

        isWorking = true
        defer { isWorking = false }
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
            WidgetCenter.shared.reloadTimelines(ofKind: SharedStorage.widgetKind)
        } catch {
            try? dump.writeFailure(capture: capture, error: error, cookie: cookie)
            statusMessage = "\(UsageFetchError.redact(error.localizedDescription, cookie: cookie))\nSaved what came back in \(dump.directory.path)."
            if error as? UsageFetchError == .sessionExpired {
                previewPresentation = .sessionExpired
            }
        }
    }
}
