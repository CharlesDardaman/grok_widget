# Grok Usage widget

A macOS desktop widget for [grok.com/dashboard/usage](https://grok.com/dashboard/usage). The host app is a small window used to sign in to grok.com and to save raw API responses. It is not a menu-bar app. The widget itself is a WidgetKit extension.

Small shows the weekly included percent, the progress bar, and the reset date. Medium and large add total tokens, included tokens, tokens today, and a tokens-per-day chart grouped by product.

## Requirements

- macOS 14 or later
- Xcode 15 or later (this repo was built with Xcode 27)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you change `project.yml` (`brew install xcodegen`)

If `xcodebuild` says the active developer directory is Command Line Tools, point it at Xcode for the shell you are using:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

## Install

This is the recommended path. It builds the host app, removes the previous copy, installs the new one to `/Applications`, and restarts the widget process.

```bash
./scripts/install.sh
```

The script needs full Xcode and `Config/Local.xcconfig` with your real `DEVELOPMENT_TEAM`. It stops with a clear error if that file or the team is missing, and it does not print the team ID. A free Apple Development profile expires after 7 days; `make install-resign-agent` renews the installed app before that. See [Renew the free-team signature](#renew-the-free-team-signature). Before it copies the new app it quits Grok Widget with `pkill -x`, unregisters the old widget extension, unregisters every `GrokWidget.app` Launch Services entry it finds under `/Applications`, Xcode DerivedData, and this repo's `build` directory, deletes `/Applications/GrokWidget.app`, and restarts `chronod` and Notification Center so the old desktop widget disappears. It then registers only the `/Applications` copy, launches it once, and reloads widgets. The Keychain session is kept. `./scripts/install.sh --clean` also deletes that session and the App Group data.

When it finishes, add the widget again: on the desktop, right-click, choose **Edit Widgets**, and add **Grok Usage**. `open grokwidget://sign-in` opens the sign-in sheet.

In Xcode, run the **GrokWidgetApp** scheme. **GrokWidgetExtension** only opens the WidgetKit preview. It is not the sign-in app.

## Signing

Automatic signing is on (`CODE_SIGN_STYLE = Automatic`). The team ID is not committed.

1. Copy the example config:

   ```bash
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```

2. Set `DEVELOPMENT_TEAM` to your 10-character Team ID (Xcode → Settings → Accounts → your team). A personal team is enough.

3. Regenerate the project if you edit `project.yml`:

   ```bash
   xcodegen generate
   ```

4. Open `GrokWidget.xcodeproj` and run the **GrokWidgetApp** scheme. Do not run **GrokWidgetExtension** if you want the sign-in window. `./scripts/install.sh` does this build for you and copies the app to `/Applications`.

The app and the widget extension share:

- App Group `group.com.charlesdardaman.grok-widget` (cached `UsageSnapshot`)
- Keychain access group `$(AppIdentifierPrefix)com.charlesdardaman.grok-widget.shared` (the session cookie)

Both identifiers are in the entitlements files. Xcode’s automatic signing registers them for your team the first time you build a signed app. The widget can read the cookie only when both targets are signed with that team. An unsigned build still compiles; the cookie stays in the app keychain and the extension will not see it.

### Unsigned build

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project GrokWidget.xcodeproj -scheme GrokWidgetApp -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=- build
xcodebuild -project GrokWidget.xcodeproj -scheme GrokWidgetApp -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=- test
```

## Renew the free-team signature

A free Apple Development profile lasts 7 days. The app and the widget need one because they use the app group and the keychain access group. `scripts/resign.sh` keeps `/Applications/GrokWidget.app` signed with that team. It does not drop those entitlements.

On a normal run the script does not build. It rebuilds the **GrokWidgetApp** Release scheme with `xcodebuild -allowProvisioningUpdates` only when one of these is true:

- `codesign --verify --deep --strict` fails for `/Applications/GrokWidget.app`
- the embedded profile on the app or on `GrokUsageWidget.appex` is missing, already expired, or expires within 3 days

Automatic signing uses the team in `Config/Local.xcconfig`. Xcode has to already be signed in to the Apple ID (Xcode > Settings > Accounts). The script cannot complete a sign-in prompt. After a build it checks the signature, checks that both embedded profiles expire in the future, and checks that the app group and keychain access group are still present. It quits Grok Widget, swaps the new bundle into `/Applications/GrokWidget.app`, launches it, and re-registers the widget with `pluginkit` so WidgetKit uses the new signature.

Each run appends to `~/Library/Logs/GrokWidget/resign.log`, including the new expiry date when it installs a profile.

A user LaunchAgent runs that check every day at 9:15 local time and again at login. `StartCalendarInterval` also runs the missed check after the Mac wakes from sleep. The agent stores this checkout's path, so run the install again if you move the repo:

```bash
make install-resign-agent
```

Remove it with:

```bash
make uninstall-resign-agent
```

That deletes `~/Library/LaunchAgents/com.charlesdardaman.grok-widget.resign.plist` and unloads the agent. The app and the log stay where they are.

If a re-sign fails, or the installed profile expires within 48 hours and that run did not install a new one, the script posts a macOS notification. Each of those two situations is sent at most once per day. The banner tells you to open Xcode > Settings > Accounts and sign back in, then run `scripts/resign.sh --force`, and it includes `~/Library/Logs/GrokWidget/resign.log`. `terminal-notifier` is used when it is installed; otherwise the script uses `osascript`.

```bash
./scripts/resign.sh --force                 # rebuild now
./scripts/resign.sh --check                 # report only; does not modify the app
./scripts/resign.sh --simulate-failure      # post the failure notification, do not build
./scripts/resign.sh --simulate-expiring     # post the 48-hour notification, do not build
```

`GROK_RESIGN_SIMULATE=failure` and `GROK_RESIGN_SIMULATE=expiring` do the same thing as the simulate flags.

## Run and add the widget

1. Run `./scripts/install.sh`, or run the **GrokWidgetApp** scheme in Xcode. A normal Dock app opens. There is no menu-bar item. **GrokWidgetExtension** is only the widget preview.
2. Click **Sign in to grok.com**. A window opens `https://grok.com/dashboard/usage` in a `WKWebView` with its own persistent data store. Log in there, including SSO or a verification code.
3. The app watches that web view’s cookie store. It does not read Safari or Chrome. When grok.com cookies are present and `usage-status` returns HTTP 200 JSON, it builds a `Cookie` header from the grok.com cookies only, saves it in the Keychain, closes the window, and reloads widget timelines. Cookie values are never logged.
4. Optionally click **Fetch and save raw JSON**. Responses land in `~/Library/Application Support/grok_widget/` as `last_usage_status.json`, `last_daily_usage.json`, and `last_daily_usage_request.json`. If a body contains the cookie, that file is not written.
5. On the desktop, right-click, choose **Edit Widgets**, and add **Grok Usage**. macOS 14+ can place widgets on the desktop (System Settings → Desktop & Dock → Widgets, if the desktop gallery is hidden).

**Advanced** still has a cookie field. Use it when the sign-in window cannot finish login. Paste the `Cookie` header from the dashboard’s `usage-status` request and click **Save**.

Google’s sign-in page sometimes refuses an embedded web view with “This browser or app may not be secure” (`disallowed_useragent`). The web view sets a desktop Safari user agent, because that check is mostly the user-agent string and the default WKWebView agent is rejected. That workaround often succeeds on macOS, including a verification code that stays on the page, but Google does not support embedded web views and can still refuse. X or email inside the same window is the other path. This was not confirmed against a live Google account here.

**Sign in needed** and **Session expired** use `grokwidget://sign-in`, which brings the window forward and opens the sign-in sheet. Every other state, including a stale reading and every widget size, sets the widget link to `https://grok.com/dashboard/usage`. macOS opens that in the default browser and does not launch this app. A custom-scheme link only launches the app, which is why a signed-in click used to show the Grok Usage window. The app first re-reads cookies from the persistent web view store and probes `usage-status` when the sign-in link is opened. If that succeeds, the Keychain is updated and the widget reloads. If it fails, the sheet stays open. A successful sign-in also reloads widget timelines immediately.

If a signed-in desktop click still opens the Grok Usage window, the desktop is showing a widget cached from an older copy. Run `./scripts/install.sh` again, then add **Grok Usage** from **Edit Widgets**. Several registered copies of the app, or a timeline saved before the link changed, cause that click to launch the app with no URL.

The timeline refreshes about every 15 minutes. Signing in, saving, or clearing the cookie reloads it immediately. The widget shows the time it last fetched, a stale or error banner when a refresh fails, and an unavailable state when `availability` is not `available`.

`grok-usage-dump` is a small command-line tool built with the same scheme. It reads the cookie from the Keychain (never from an argument) and writes the same JSON files. `--out` changes the directory. It only works once the tool is signed with the same team as the app.

## Data

`GrokWebUsageProvider` calls the two captured endpoints:

- `GET https://grok.com/dashboard/api/dashboard/v2/usage-status?scope=user`
- `POST https://grok.com/dashboard/api/dashboard/v2/query-daily-usage`

Headers match the dashboard: `Accept: application/json`, the session `Cookie`, `Referer: https://grok.com/dashboard/usage`, `x-cursor-dashboard-surface: v2`, and a Safari user agent. The POST also sends `Content-Type: application/json` and `Origin: https://grok.com`.

Weekly percent is `weeklyIncludedUsage.usedCents / budgetCents` (1160/16159 is 7.2%, shown as 7%, the same rounding as the dashboard). The reset date is `weeklyIncludedUsage.resetsAt`. `weeklyIncludedStatus.status` (for example `metered`) is shown as a small caption. **Tokens today** is the last UTC day of the daily series, the same total as the chart’s last bar, formatted like the other token totals. A day with no points is `0`. Credit fields stay on the model and in the summary line; the widget does not show them.

The daily query covers the current weekly period and at least 14 days, grouped by `product`, with `topN` 5. Headline totals are the sum of daily points inside the weekly period, labeled **This week**, so they are not the dashboard’s arbitrary chart range. The request omits `filters` so `totalTokens` can differ from `totalIncludedTokens`. If the server rejects that with HTTP 400 or 422, the provider retries `usageTypes: ["included", "on-demand"]` and then `["included"]`. The widget footnotes the filter it actually used. Product slugs map to Cursor, Grok Bot, Grok Tasks, Grok Chat, and Grok App Builder; anything else is title-cased, and the `other` bucket is included.

Codable models match the captured samples in `Tests/GrokUsageKitTests/Fixtures/`. Costs are decimal strings. Token counts are `Int64`.

`FixtureUsageProvider` returns the October dashboard screenshot (967.2M total, 874.7M included, $0.50 credit, 7% weekly, resets Nov 4) for previews and the widget gallery. The daily bars are a visual trace of that chart, not a captured payload.

## Layout

- `project.yml` — XcodeGen project. Shared schemes are **GrokWidgetApp** (runs the host app) and **GrokWidgetExtension** (WidgetKit preview)
- `scripts/install.sh` — signed build, install to `/Applications`, open the app
- `scripts/resign.sh` — refresh the free-team signature when it is near expiry
- `scripts/install-resign-agent.sh` — install or remove the daily LaunchAgent
- `Makefile` — `install-resign-agent` and `uninstall-resign-agent`
- `Sources/GrokUsageKit` — models, formatting, providers, Keychain, cache
- `Sources/GrokUsageUI` — SwiftUI widget views
- `Sources/GrokWidgetApp` — settings window and in-app sign-in
- `Sources/GrokUsageWidget` — WidgetKit extension
- `Sources/grok-usage-dump` — raw-JSON command
- `Tests/GrokUsageKitTests` — formatting, decode, mapping, provider, and snapshot render tests
