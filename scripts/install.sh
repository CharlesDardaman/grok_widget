#!/bin/bash
# Build the host app with the team in Config/Local.xcconfig, install it to
# /Applications, and refresh the widget gallery. Does not print the team ID.

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

is_full_xcode() {
  local path="${1:-}"
  [[ -n "$path" && -x "$path/usr/bin/xcodebuild" && "$path" == *"/Xcode.app/Contents/Developer" ]]
}

if ! is_full_xcode "${DEVELOPER_DIR:-}"; then
  selected="$(xcode-select -p 2>/dev/null || true)"
  if is_full_xcode "$selected"; then
    export DEVELOPER_DIR="$selected"
  elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    echo "Using $DEVELOPER_DIR (xcode-select is not pointing at full Xcode)."
  else
    echo "error: Full Xcode is required. Install Xcode, or set DEVELOPER_DIR to /Applications/Xcode.app/Contents/Developer." >&2
    exit 1
  fi
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is not installed. Install it with: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate

local_config="Config/Local.xcconfig"
if [[ ! -f "$local_config" ]]; then
  echo "error: $local_config is missing. Copy Config/Local.xcconfig.example to Config/Local.xcconfig and set DEVELOPMENT_TEAM to your 10-character Team ID." >&2
  exit 1
fi

team=""
while IFS= read -r line || [[ -n "$line" ]]; do
  stripped="${line%%//*}"
  stripped="${stripped#"${stripped%%[![:space:]]*}"}"
  if [[ "$stripped" =~ ^DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*(.*)$ ]]; then
    team="${BASH_REMATCH[1]}"
    team="${team%"${team##*[![:space:]]}"}"
    team="${team%\"}"
    team="${team#\"}"
  fi
done < "$local_config"

if [[ -z "$team" || "$team" == "ABCDE12345" ]]; then
  echo "error: Set DEVELOPMENT_TEAM in $local_config to your 10-character Team ID (Xcode → Settings → Accounts). The example value does not sign the app." >&2
  exit 1
fi

if [[ ! "$team" =~ ^[A-Za-z0-9]{10}$ ]]; then
  echo "error: DEVELOPMENT_TEAM in $local_config must be a 10-character Team ID." >&2
  exit 1
fi

configuration="${CONFIGURATION:-Release}"
derived="$root/build/DerivedData"
echo "Building GrokWidgetApp ($configuration) for macOS."

xcodebuild \
  -project GrokWidget.xcodeproj \
  -scheme GrokWidgetApp \
  -destination 'platform=macOS' \
  -configuration "$configuration" \
  -derivedDataPath "$derived" \
  -allowProvisioningUpdates \
  build

app="$derived/Build/Products/$configuration/GrokWidget.app"
if [[ ! -d "$app" ]]; then
  echo "error: Build finished but $app was not produced." >&2
  exit 1
fi

if pgrep -x GrokWidget >/dev/null 2>&1; then
  killall GrokWidget || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x GrokWidget >/dev/null 2>&1 || break
    sleep 0.2
  done
fi

dest="/Applications/GrokWidget.app"
rm -rf "$dest"
ditto "$app" "$dest"
echo "Installed $dest"
open "$dest"

# Notification Center caches the widget gallery. Restarting it picks up the new extension.
killall NotificationCenter || true

cat <<'EOF'

Next:
1. In the Grok Widget window, click Sign in to grok.com.
2. On the desktop, right-click, choose Edit Widgets, and add Grok Usage.
EOF
