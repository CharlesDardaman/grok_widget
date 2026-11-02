#!/bin/bash
# Build the host app with the team in Config/Local.xcconfig, replace any
# older install, and refresh the widget gallery. Does not print the team ID.
# Quits with pkill and launches with open.
#
# ./scripts/install.sh
#     Replaces the app and widget. Keeps the Keychain session and App Group.
# ./scripts/install.sh --clean
#     Also deletes the Keychain session and App Group data.

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

clean=0
if [[ $# -gt 1 ]]; then
  echo "error: too many arguments." >&2
  exit 1
fi
if [[ $# -eq 1 ]]; then
  if [[ "$1" != "--clean" ]]; then
    echo "error: unknown argument: $1 (expected --clean)." >&2
    exit 1
  fi
  clean=1
fi

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

lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
dest="/Applications/GrokWidget.app"
candidates="$(mktemp)"
trap 'rm -f "$candidates"' EXIT

add_candidate() {
  local path="$1"
  [[ -n "$path" ]] || return 0
  path="${path%/}"
  if [[ "$(basename "$path")" != "GrokWidget.app" ]]; then
    return 0
  fi
  printf '%s\n' "$path" >> "$candidates"
}

echo "Uninstalling the previous Grok Widget."

echo "Quitting GrokWidget."
if pgrep -x GrokWidget >/dev/null 2>&1; then
  pkill -x GrokWidget || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x GrokWidget >/dev/null 2>&1 || break
    sleep 0.2
  done
else
  echo "GrokWidget is not running."
fi

if [[ -d /Applications ]]; then
  add_candidate "$dest"
fi
if [[ -d "$HOME/Library/Developer/Xcode/DerivedData" ]]; then
  while IFS= read -r found; do
    add_candidate "$found"
  done < <(find "$HOME/Library/Developer/Xcode/DerivedData" -name 'GrokWidget.app' -type d -prune 2>/dev/null || true)
fi
if [[ -d "$root/build" ]]; then
  while IFS= read -r found; do
    add_candidate "$found"
  done < <(find "$root/build" -name 'GrokWidget.app' -type d -prune 2>/dev/null || true)
fi
if [[ -x "$lsregister" ]]; then
  while IFS= read -r found; do
    add_candidate "$found"
  done < <("$lsregister" -dump 2>/dev/null | sed -n 's/^path:[[:space:]]*//p' | sed -E 's/ \(0x[0-9a-fA-F]+\)$//' || true)
fi

echo "Unregistering widget extensions."
unregistered_plugin=0
if [[ -s "$candidates" ]]; then
  while IFS= read -r found; do
    appex="$found/Contents/PlugIns/GrokUsageWidget.appex"
    if [[ -d "$appex" ]]; then
      echo "pluginkit -r $appex"
      pluginkit -r "$appex" || true
      unregistered_plugin=1
    fi
  done < <(sort -u "$candidates")
fi
if [[ "$unregistered_plugin" -eq 0 ]]; then
  echo "No Grok Usage widget extension was registered."
fi

echo "Unregistering Launch Services copies."
unregistered_app=0
if [[ -x "$lsregister" && -s "$candidates" ]]; then
  while IFS= read -r found; do
    echo "lsregister -u $found"
    "$lsregister" -u "$found" || true
    unregistered_app=1
  done < <(sort -u "$candidates")
fi
if [[ "$unregistered_app" -eq 0 ]]; then
  echo "No GrokWidget.app Launch Services entries were found."
fi

echo "Removing $dest."
if [[ -d "$dest" ]]; then
  rm -rf "$dest"
  echo "Removed $dest."
else
  echo "$dest is already gone."
fi

echo "Restarting chronod and Notification Center so the old widget leaves the desktop."
killall chronod || true
killall NotificationCenter || true

if [[ "$clean" -eq 1 ]]; then
  echo "Removing the Keychain session and App Group data."
  security delete-generic-password -s "com.charlesdardaman.grok-widget" -a "dashboard-session-cookie" >/dev/null 2>&1 || true
  rm -rf "$HOME/Library/Group Containers/group.com.charlesdardaman.grok-widget"
  rm -rf "$HOME/Library/Containers/com.charlesdardaman.grok-widget"
  rm -rf "$HOME/Library/Containers/com.charlesdardaman.grok-widget.widget"
else
  echo "Keeping the Keychain session and App Group data."
fi

echo "Installing $dest."
ditto "$app" "$dest"
build_number="$(plutil -extract CFBundleVersion raw "$dest/Contents/Info.plist" 2>/dev/null || echo unknown)"
echo "Installed $dest (build $build_number)."

echo "Registering $dest."
if [[ -x "$lsregister" ]]; then
  "$lsregister" -f "$dest" || true
fi
new_appex="$dest/Contents/PlugIns/GrokUsageWidget.appex"
if [[ -d "$new_appex" ]]; then
  echo "pluginkit -a $new_appex"
  pluginkit -a "$new_appex" || true
  echo "pluginkit -e use -i com.charlesdardaman.grok-widget.widget"
  pluginkit -e use -i com.charlesdardaman.grok-widget.widget || true
fi

echo "Launching Grok Widget."
open "$dest"

echo "Reloading widgets."
killall chronod || true
killall NotificationCenter || true

echo "Checking that only $dest stayed registered."
: > "$candidates"
if [[ -x "$lsregister" ]]; then
  while IFS= read -r found; do
    add_candidate "$found"
  done < <("$lsregister" -dump 2>/dev/null | sed -n 's/^path:[[:space:]]*//p' | sed -E 's/ \(0x[0-9a-fA-F]+\)$//' || true)
  if [[ -s "$candidates" ]]; then
    while IFS= read -r found; do
      if [[ "$found" != "$dest" ]]; then
        echo "lsregister -u $found"
        "$lsregister" -u "$found" || true
        stale_appex="$found/Contents/PlugIns/GrokUsageWidget.appex"
        if [[ -d "$stale_appex" ]]; then
          echo "pluginkit -r $stale_appex"
          pluginkit -r "$stale_appex" || true
        fi
      fi
    done < <(sort -u "$candidates")
  fi
fi

cat <<EOF

The previous widget was removed. You may need to add it again: on the desktop, right-click, choose Edit Widgets, and add Grok Usage.
A signed-in widget opens https://grok.com/dashboard/usage in the browser. Sign in needed and Session expired open this app.
EOF
if [[ "$clean" -eq 1 ]]; then
  echo "The Keychain session and App Group data were deleted."
else
  echo "The Keychain session was kept. ./scripts/install.sh --clean also deletes that session and the App Group data."
fi
