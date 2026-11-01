# Grok Usage widget

A macOS desktop widget for [grok.com/dashboard/usage](https://grok.com/dashboard/usage). The host app is a small window used to paste a session cookie and to save raw API responses. It is not a menu-bar app. The widget itself is a WidgetKit extension.

Small shows the weekly included percent, the progress bar, and the reset date. Medium and large add total tokens, included tokens, credit usage, and a tokens-per-day chart grouped by product.

## Requirements

- macOS 14 or later
- Xcode 15 or later (this repo was built with Xcode 27)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you change `project.yml` (`brew install xcodegen`)

If `xcodebuild` says the active developer directory is Command Line Tools, point it at Xcode for the shell you are using:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

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

4. Open `GrokWidget.xcodeproj`, select the GrokWidget scheme, and run it.

The app and the widget extension share:

- App Group `group.com.charlesdardaman.grok-widget` (cached `UsageSnapshot`)
- Keychain access group `$(AppIdentifierPrefix)com.charlesdardaman.grok-widget.shared` (the session cookie)

Both identifiers are in the entitlements files. Xcode’s automatic signing registers them for your team the first time you build a signed app. The widget can read the cookie only when both targets are signed with that team. An unsigned build still compiles; the cookie stays in the app keychain and the extension will not see it.

### Unsigned build

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project GrokWidget.xcodeproj -scheme GrokWidget -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=- build
xcodebuild -project GrokWidget.xcodeproj -scheme GrokWidget -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=- test
```

## Run and add the widget

1. Run the **GrokWidget** scheme. A normal Dock app opens. There is no menu-bar item.
2. In Safari or Chrome, open `https://grok.com/dashboard/usage`, find the `usage-status` request, and copy its `Cookie` header.
3. Paste that value into the app and click **Save**. It is stored in the Keychain. It is not written to the repo, logged, or put on the command line.
4. Optionally click **Fetch and save raw JSON**. Responses land in `~/Library/Application Support/grok_widget/` as `last_usage_status.json`, `last_daily_usage.json`, and `last_daily_usage_request.json`. If a body contains the cookie, that file is not written.
5. On the desktop, right-click, choose **Edit Widgets**, and add **Grok Usage**. macOS 14+ can place widgets on the desktop (System Settings → Desktop & Dock → Widgets, if the desktop gallery is hidden).

The timeline refreshes about every 15 minutes. Saving or clearing the cookie reloads it immediately. The widget shows the time it last fetched, a stale or error banner when a refresh fails, “Session expired. Re-paste the cookie” on HTTP 401/403 or a redirect to login, and an unavailable state when `availability` is not `available`.

`grok-usage-dump` is a small command-line tool built with the same scheme. It reads the cookie from the Keychain (never from an argument) and writes the same JSON files. `--out` changes the directory. It only works once the tool is signed with the same team as the app.

## Data

`GrokWebUsageProvider` calls the two captured endpoints:

- `GET https://grok.com/dashboard/api/dashboard/v2/usage-status?scope=user`
- `POST https://grok.com/dashboard/api/dashboard/v2/query-daily-usage`

Headers match the dashboard: `Accept: application/json`, the session `Cookie`, `Referer: https://grok.com/dashboard/usage`, `x-cursor-dashboard-surface: v2`, and a Safari user agent. The POST also sends `Content-Type: application/json` and `Origin: https://grok.com`.

Weekly percent is `weeklyIncludedUsage.usedCents / budgetCents` (1160/16159 is 7.2%, shown as 7%, the same rounding as the dashboard). The reset date is `weeklyIncludedUsage.resetsAt`. `weeklyIncludedStatus.status` (for example `metered`) is shown as a small caption. Credit usage is `monthlyUsage.creditsUsedCents` in dollars. `monthlyUsage.usedCents` is shown beside it when the two differ. `limitCents` may be null.

The daily query covers the current weekly period and at least 14 days, grouped by `product`, with `topN` 5. Headline totals are the sum of daily points inside the weekly period, labeled **This week**, so they are not the dashboard’s arbitrary chart range. The request omits `filters` so `totalTokens` can differ from `totalIncludedTokens`. If the server rejects that with HTTP 400 or 422, the provider retries `usageTypes: ["included", "on-demand"]` and then `["included"]`. The widget footnotes the filter it actually used. Product slugs map to Cursor, Grok Bot, Grok Tasks, Grok Chat, and Grok App Builder; anything else is title-cased, and the `other` bucket is included.

Codable models match the captured samples in `Tests/GrokUsageKitTests/Fixtures/`. Costs are decimal strings. Token counts are `Int64`.

`FixtureUsageProvider` returns the October dashboard screenshot (967.2M total, 874.7M included, $0.50 credit, 7% weekly, resets Nov 4) for previews and the widget gallery. The daily bars are a visual trace of that chart, not a captured payload.

## Layout

- `project.yml` — XcodeGen project
- `Sources/GrokUsageKit` — models, formatting, providers, Keychain, cache
- `Sources/GrokUsageUI` — SwiftUI widget views
- `Sources/GrokWidgetApp` — settings window
- `Sources/GrokUsageWidget` — WidgetKit extension
- `Sources/grok-usage-dump` — raw-JSON command
- `Tests/GrokUsageKitTests` — formatting, decode, mapping, provider, and snapshot render tests
