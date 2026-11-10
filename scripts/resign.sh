#!/bin/bash
# Rebuild /Applications/GrokWidget.app when its free-team profile is expired,
# inside 3 days of expiry, or the signature no longer verifies. A successful
# run replaces the app only after codesign and both embedded profiles check
# out, then launches it and re-registers the widget extension.
#
#   ./scripts/resign.sh                 # daily check (what the LaunchAgent runs)
#   ./scripts/resign.sh --force         # rebuild even if the profile is still fresh
#   ./scripts/resign.sh --check         # print the decision; do not build or notify
#   ./scripts/resign.sh --simulate-failure
#   ./scripts/resign.sh --simulate-expiring
#   GROK_RESIGN_SIMULATE=failure|expiring ./scripts/resign.sh
#
# Simulations post the real notification text and do not modify the app.
# Each failure type is posted at most once per local day.
# Log: ~/Library/Logs/GrokWidget/resign.log

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="${HOME}/Library/Logs/GrokWidget/resign.log"
DEST="/Applications/GrokWidget.app"
RENEW_WITHIN_SECONDS=$((3 * 24 * 60 * 60))
WARN_WITHIN_SECONDS=$((48 * 60 * 60))
BUILD_TIMEOUT_SECONDS=1500
APP_GROUP="group.com.charlesdardaman.grok-widget"
KEYCHAIN_SUFFIX="com.charlesdardaman.grok-widget.shared"
WIDGET_ID="com.charlesdardaman.grok-widget.widget"

stage_dir=""
lock_dir=""
build_log=""
FORCE=0
CHECK=0
SIMULATE=""
TEAM=""
APP_EXPIRY=""
APPEX_EXPIRY=""
INSTALLED_APP_EXPIRY=""
INSTALLED_APPEX_EXPIRY=""
INSTALLED=0
VERIFY_OK=0
on_exit_reason=""
failure_notified=0
RENEWED=0

usage() {
  cat <<EOF
Usage: ./scripts/resign.sh [--check | --force | --simulate-failure | --simulate-expiring]

Rebuilds the Release app when /Applications/GrokWidget.app fails
codesign --verify --deep --strict, or its embedded profile expires within
3 days. --force always rebuilds. --check only reports the decision.
EOF
}

log() {
  mkdir -p "$(dirname "$LOG_FILE")"
  # Console copy goes to stderr so command substitutions only capture real output.
  printf '%s %s\n' "$(date "+%Y-%m-%dT%H:%M:%S%z")" "$*" | tee -a "$LOG_FILE" >&2
}

display_path() {
  local path="$1"
  case "$path" in
    "$HOME"/*) printf '~/%s' "${path#"$HOME"/}" ;;
    *) printf '%s' "$path" ;;
  esac
}

display_cmd() {
  printf '%s --force' "$(display_path "$root/scripts/resign.sh")"
}

notify_state_file() {
  if [[ -n "${GROK_RESIGN_STATE_FILE:-}" ]]; then
    printf '%s' "$GROK_RESIGN_STATE_FILE"
  else
    printf '%s' "${HOME}/Library/Logs/GrokWidget/notify-state"
  fi
}

iso_to_epoch() {
  date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" "+%s"
}

epoch_to_iso() {
  date -u -r "$1" "+%Y-%m-%dT%H:%M:%SZ"
}

format_expiry() {
  date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" "+%Y-%m-%d %H:%M UTC"
}

normalize_expiry() {
  local raw="$1"
  raw="${raw//$'\r'/}"
  raw="${raw//$'\n'/}"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  if [[ "$raw" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    printf '%s' "$raw"
    return 0
  fi
  if [[ "$raw" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]([0-9]{2}:[0-9]{2}:[0-9]{2})[[:space:]]\+0000$ ]]; then
    printf '%sT%sZ' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

# verify_ok (0/1), now epoch, expiry epoch -> "rebuild|skip" + " warn| ok"
plan_for() {
  local verify_ok="$1"
  local now="$2"
  local expiry="$3"
  local left=$((expiry - now))
  local rebuild=0
  local warn=0
  if [[ "$verify_ok" -eq 0 || "$left" -le "$RENEW_WITHIN_SECONDS" ]]; then
    rebuild=1
  fi
  if [[ "$left" -le "$WARN_WITHIN_SECONDS" ]]; then
    warn=1
  fi
  if [[ "$rebuild" -eq 1 ]]; then
    printf 'rebuild'
  else
    printf 'skip'
  fi
  if [[ "$warn" -eq 1 ]]; then
    printf ' warn\n'
  else
    printf ' ok\n'
  fi
}

failure_message() {
  local reason="${1:-account}"
  local cmd logp
  cmd="$(display_cmd)"
  logp='~/Library/Logs/GrokWidget/resign.log'
  case "$reason" in
    network)
      printf 'GrokWidget re-sign failed: no network while updating the provisioning profile. Reconnect, then run %s. Log: %s' "$cmd" "$logp"
      ;;
    build)
      printf 'GrokWidget re-sign failed: the Release build failed. See %s, then run %s.' "$logp" "$cmd"
      ;;
    timeout)
      printf 'GrokWidget re-sign failed: xcodebuild did not finish. Open Xcode > Settings > Accounts and sign back in, then run %s. Log: %s' "$cmd" "$logp"
      ;;
    launch)
      printf 'GrokWidget re-sign failed: a new profile was installed but the app did not open. See %s, then run %s.' "$logp" "$cmd"
      ;;
    *)
      printf 'GrokWidget re-sign failed: open Xcode > Settings > Accounts and sign back in, then run %s. Log: %s' "$cmd" "$logp"
      ;;
  esac
}

expiring_message() {
  local expiry_iso="$1"
  local now_epoch="$2"
  local exp_epoch pretty cmd logp
  exp_epoch="$(iso_to_epoch "$expiry_iso")"
  pretty="$(format_expiry "$expiry_iso")"
  cmd="$(display_cmd)"
  logp='~/Library/Logs/GrokWidget/resign.log'
  if [[ "$exp_epoch" -le "$now_epoch" ]]; then
    printf 'GrokWidget signing expired %s and was not renewed: open Xcode > Settings > Accounts and sign back in, then run %s. Log: %s' "$pretty" "$cmd" "$logp"
  else
    printf 'GrokWidget signing expires %s (within 48 hours) and was not renewed: open Xcode > Settings > Accounts and sign back in, then run %s. Log: %s' "$pretty" "$cmd" "$logp"
  fi
}

already_notified() {
  local kind="$1"
  local today state
  today="$(date "+%Y-%m-%d")"
  state="$(notify_state_file)"
  if [[ -f "$state" ]] && grep -qx -- "$kind $today" "$state"; then
    return 0
  fi
  return 1
}

record_notified() {
  local kind="$1"
  local today state dir tmp
  today="$(date "+%Y-%m-%d")"
  state="$(notify_state_file)"
  dir="$(dirname "$state")"
  mkdir -p "$dir"
  tmp="$(mktemp "$dir/notify-state.XXXXXX")"
  if [[ -f "$state" ]]; then
    grep -v "^${kind} " "$state" > "$tmp" || true
  fi
  printf '%s %s\n' "$kind" "$today" >> "$tmp"
  mv "$tmp" "$state"
}

post_notification() {
  local message="$1"
  if command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier -title "GrokWidget" -message "$message" -sound default
    return $?
  fi
  osascript - "$message" <<'APPLESCRIPT'
on run argv
  display notification (item 1 of argv) with title "GrokWidget" sound name "default"
end run
APPLESCRIPT
}

notify_kind() {
  local kind="$1"
  local message="$2"
  if already_notified "$kind"; then
    log "notification suppressed ($kind already sent today): $message"
    return 0
  fi
  if post_notification "$message"; then
    record_notified "$kind"
    log "notification posted ($kind): $message"
  else
    log "notification could not be posted ($kind): $message"
  fi
}

notify_failure() {
  notify_kind "resign-failed" "$(failure_message "${1:-account}")"
}

soonest_expiry_iso() {
  local app_iso="${INSTALLED_APP_EXPIRY:-}"
  local appex_iso="${INSTALLED_APPEX_EXPIRY:-}"
  if [[ -z "$app_iso" && -z "$appex_iso" ]]; then
    return 0
  fi
  if [[ -z "$app_iso" ]]; then
    printf '%s' "$appex_iso"
    return 0
  fi
  if [[ -z "$appex_iso" ]]; then
    printf '%s' "$app_iso"
    return 0
  fi
  local app_epoch appex_epoch
  app_epoch="$(iso_to_epoch "$app_iso")"
  appex_epoch="$(iso_to_epoch "$appex_iso")"
  if [[ "$app_epoch" -le "$appex_epoch" ]]; then
    printf '%s' "$app_iso"
  else
    printf '%s' "$appex_iso"
  fi
}

expires_soon() {
  local iso now exp left
  if [[ "$RENEWED" -eq 1 ]]; then
    return 1
  fi
  if [[ "$INSTALLED" -eq 0 || -z "$INSTALLED_APP_EXPIRY" || -z "$INSTALLED_APPEX_EXPIRY" ]]; then
    return 0
  fi
  iso="$(soonest_expiry_iso)"
  now="$(date -u "+%s")"
  exp="$(iso_to_epoch "$iso")"
  left=$((exp - now))
  [[ "$left" -le "$WARN_WITHIN_SECONDS" ]]
}

notify_expiring() {
  local iso message now
  iso="$(soonest_expiry_iso || true)"
  now="$(date -u "+%s")"
  if [[ -z "$iso" ]]; then
    message="GrokWidget signing is missing and was not renewed: open Xcode > Settings > Accounts and sign back in, then run $(display_cmd). Log: ~/Library/Logs/GrokWidget/resign.log"
  else
    message="$(expiring_message "$iso" "$now")"
  fi
  notify_kind "expiring-soon" "$message"
}

finish_failure() {
  local reason="$1"
  failure_notified=1
  notify_failure "$reason"
  if expires_soon; then
    notify_expiring
  fi
  exit 1
}

cleanup() {
  local status=$?
  if [[ -n "$build_log" && -f "$build_log" ]]; then
    rm -f "$build_log"
  fi
  if [[ -n "$stage_dir" && -d "$stage_dir" ]]; then
    rm -rf "$stage_dir"
  fi
  if [[ "$status" -ne 0 && "$failure_notified" -eq 0 && -n "$on_exit_reason" ]]; then
    failure_notified=1
    notify_failure "$on_exit_reason" || true
    if expires_soon; then
      notify_expiring || true
    fi
  fi
  if [[ -n "$lock_dir" && -d "$lock_dir" ]]; then
    rm -rf "$lock_dir"
  fi
  exit "$status"
}

kill_tree() {
  local pid="$1"
  local child
  local children=""
  children="$(pgrep -P "$pid" || true)"
  for child in $children; do
    kill_tree "$child"
  done
  kill "$pid" 2>/dev/null || true
}

acquire_lock() {
  local old=""
  lock_dir="${HOME}/Library/Logs/GrokWidget/resign.lock"
  mkdir -p "$(dirname "$lock_dir")"
  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$$" > "$lock_dir/pid"
    return 0
  fi
  if [[ -f "$lock_dir/pid" ]]; then
    old="$(cat "$lock_dir/pid" 2>/dev/null || true)"
  fi
  if [[ -n "$old" ]] && ! kill -0 "$old" 2>/dev/null; then
    rm -rf "$lock_dir"
    mkdir "$lock_dir"
    printf '%s\n' "$$" > "$lock_dir/pid"
    log "removed a stale resign lock from pid $old"
    return 0
  fi
  log "another resign is already running${old:+ (pid $old)}; leaving the app unchanged"
  lock_dir=""
  exit 0
}

ensure_xcode() {
  if [[ -x "${DEVELOPER_DIR:-}/usr/bin/xcodebuild" && "${DEVELOPER_DIR:-}" == *"/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR
    return 0
  fi
  local selected=""
  selected="$(xcode-select -p 2>/dev/null || true)"
  if [[ -x "$selected/usr/bin/xcodebuild" && "$selected" == *"/Xcode.app/Contents/Developer" ]]; then
    DEVELOPER_DIR="$selected"
    export DEVELOPER_DIR
    return 0
  fi
  if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    export DEVELOPER_DIR
    log "Using $DEVELOPER_DIR (xcode-select is not pointing at full Xcode)."
    return 0
  fi
  log "Full Xcode is required. Install Xcode, or set DEVELOPER_DIR to /Applications/Xcode.app/Contents/Developer."
  return 1
}

read_team() {
  local local_config="$root/Config/Local.xcconfig"
  local team=""
  if [[ -f "$local_config" ]]; then
    local line stripped
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
  fi
  if [[ -z "$team" || "$team" == "ABCDE12345" ]]; then
    if [[ -d "$DEST" ]]; then
      local signed=""
      signed="$(codesign -dv "$DEST" 2>&1 || true)"
      team="$(printf '%s\n' "$signed" | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
      log "DEVELOPMENT_TEAM is not set in Config/Local.xcconfig; using the team already signing $DEST."
    fi
  fi
  if [[ ! "$team" =~ ^[A-Za-z0-9]{10}$ || "$team" == "ABCDE12345" ]]; then
    log "Set DEVELOPMENT_TEAM in Config/Local.xcconfig to your 10-character Team ID (Xcode > Settings > Accounts). Copy Config/Local.xcconfig.example if the file is missing."
    return 1
  fi
  TEAM="$team"
}

signature_ok() {
  codesign --verify --deep --strict "$1" >/dev/null 2>&1
}

entitlements_ok() {
  local bundle="$1"
  local ents=""
  ents="$(codesign -d --entitlements :- "$bundle" 2>/dev/null || true)"
  [[ "$ents" == *"$APP_GROUP"* && "$ents" == *"keychain-access-groups"* && "$ents" == *"$KEYCHAIN_SUFFIX"* ]]
}

team_of() {
  local out=""
  out="$(codesign -dv "$1" 2>&1 || true)"
  printf '%s\n' "$out" | awk -F= '/^TeamIdentifier=/{print $2; exit}'
}

profile_expiration() {
  local profile="$1"
  local raw="" normalized=""
  if [[ ! -f "$profile" ]]; then
    return 1
  fi
  raw="$(security cms -D -i "$profile" 2>/dev/null | plutil -extract ExpirationDate raw - -o - 2>/dev/null || true)"
  if ! normalized="$(normalize_expiry "$raw")"; then
    log "could not read ExpirationDate from $profile"
    return 1
  fi
  printf '%s' "$normalized"
}

recover_partial_swap() {
  local previous="/Applications/GrokWidget.app.previous"
  if [[ ! -d "$DEST" && -d "$previous" ]]; then
    log "restoring $previous because $DEST is missing"
    mv "$previous" "$DEST"
  fi
}

read_installed() {
  INSTALLED=0
  VERIFY_OK=0
  INSTALLED_APP_EXPIRY=""
  INSTALLED_APPEX_EXPIRY=""
  APP_EXPIRY=""
  APPEX_EXPIRY=""
  if [[ ! -d "$DEST" ]]; then
    return 0
  fi
  INSTALLED=1
  if signature_ok "$DEST"; then
    VERIFY_OK=1
  fi
  INSTALLED_APP_EXPIRY="$(profile_expiration "$DEST/Contents/embedded.provisionprofile" || true)"
  INSTALLED_APPEX_EXPIRY="$(profile_expiration "$DEST/Contents/PlugIns/GrokUsageWidget.appex/Contents/embedded.provisionprofile" || true)"
  APP_EXPIRY="$INSTALLED_APP_EXPIRY"
  APPEX_EXPIRY="$INSTALLED_APPEX_EXPIRY"
}

needs_rebuild() {
  local now app_epoch appex_epoch earliest left
  if [[ "$FORCE" -eq 1 || "$INSTALLED" -eq 0 || "$VERIFY_OK" -eq 0 ]]; then
    return 0
  fi
  if [[ -z "$INSTALLED_APP_EXPIRY" || -z "$INSTALLED_APPEX_EXPIRY" ]]; then
    return 0
  fi
  now="$(date -u "+%s")"
  app_epoch="$(iso_to_epoch "$INSTALLED_APP_EXPIRY")"
  appex_epoch="$(iso_to_epoch "$INSTALLED_APPEX_EXPIRY")"
  if [[ "$app_epoch" -le "$appex_epoch" ]]; then
    earliest="$app_epoch"
  else
    earliest="$appex_epoch"
  fi
  left=$((earliest - now))
  [[ "$left" -le "$RENEW_WITHIN_SECONDS" ]]
}

profiles_in_future() {
  local app="$1"
  local now app_iso appex_iso app_epoch appex_epoch
  app_iso="$(profile_expiration "$app/Contents/embedded.provisionprofile")" || return 1
  appex_iso="$(profile_expiration "$app/Contents/PlugIns/GrokUsageWidget.appex/Contents/embedded.provisionprofile")" || return 1
  APP_EXPIRY="$app_iso"
  APPEX_EXPIRY="$appex_iso"
  now="$(date -u "+%s")"
  app_epoch="$(iso_to_epoch "$app_iso")"
  appex_epoch="$(iso_to_epoch "$appex_iso")"
  [[ "$app_epoch" -gt "$now" && "$appex_epoch" -gt "$now" ]]
}

classify_failure() {
  local file="$1"
  if [[ ! -s "$file" ]]; then
    printf 'account'
    return 0
  fi
  if grep -Eiq 'xcodebuild timed out|xcodebuild did not finish' "$file"; then
    printf 'timeout'
    return 0
  fi
  if grep -Eiq 'network connection was lost|The Internet connection appears to be offline|Could not resolve|NSURLErrorDomain|not connected to the internet|A server with the specified hostname could not be found' "$file"; then
    printf 'network'
    return 0
  fi
  if grep -Eiq 'No Accounts|not signed in|requires a provisioning profile|Provisioning profile|No profiles for|session has expired|Authentication failed|DVTDeveloperAccount|No signing certificate' "$file"; then
    printf 'account'
    return 0
  fi
  if grep -Eiq 'error: ' "$file"; then
    printf 'build'
    return 0
  fi
  printf 'account'
}

append_build_log() {
  if [[ ! -f "$build_log" ]]; then
    return 0
  fi
  if [[ -n "$TEAM" ]]; then
    sed "s/${TEAM}/[team]/g" "$build_log" >> "$LOG_FILE"
  else
    cat "$build_log" >> "$LOG_FILE"
  fi
}

run_with_timeout() {
  local limit="$1"
  shift
  build_log="$(mktemp "${TMPDIR:-/tmp}/grok-resign-build.XXXXXX")"
  log "xcodebuild output is collected in $build_log and copied into the resign log."
  "$@" >"$build_log" 2>&1 &
  local xpid=$!
  local elapsed=0
  while kill -0 "$xpid" 2>/dev/null; do
    if [[ "$elapsed" -ge "$limit" ]]; then
      log "xcodebuild still running after ${limit}s; stopping it"
      kill_tree "$xpid"
      set +e
      wait "$xpid"
      set -e
      printf '\nxcodebuild timed out after %ss\n' "$limit" >> "$build_log"
      append_build_log
      set +e
      return 124
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  local status=0
  set +e
  wait "$xpid"
  status=$?
  append_build_log
  return "$status"
}

quit_host() {
  local _i
  if pgrep -x GrokWidget >/dev/null 2>&1; then
    log "quitting GrokWidget"
    pkill -x GrokWidget || true
    for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
      pgrep -x GrokWidget >/dev/null 2>&1 || return 0
      sleep 0.2
    done
    log "GrokWidget did not quit; sending SIGKILL"
    pkill -9 -x GrokWidget || true
    sleep 0.3
  else
    log "GrokWidget is not running"
  fi
}

register_widget() {
  local appex="$DEST/Contents/PlugIns/GrokUsageWidget.appex"
  local listing=""
  listing="$(pluginkit -m -v -i "$WIDGET_ID" 2>/dev/null || true)"
  if printf '%s\n' "$listing" | grep -F -q "$appex" && printf '%s\n' "$listing" | grep -q '^+'; then
    log "widget extension is already enabled at $appex; re-registering so the new signature is picked up"
  else
    log "widget extension is not enabled at $appex; registering with pluginkit"
  fi
  pluginkit -a "$appex" || log "pluginkit -a failed for $appex"
  pluginkit -e use -i "$WIDGET_ID" || log "pluginkit -e use failed for $WIDGET_ID"
  listing="$(pluginkit -m -v -i "$WIDGET_ID" 2>/dev/null || true)"
  log "pluginkit: ${listing:-no match}"
}

reload_widget() {
  local _i
  if pgrep -x GrokUsageWidget >/dev/null 2>&1; then
    pkill -x GrokUsageWidget || true
    for _i in 1 2 3 4 5 6 7 8 9 10; do
      pgrep -x GrokUsageWidget >/dev/null 2>&1 || break
      sleep 0.2
    done
  fi
  killall chronod >/dev/null 2>&1 || true
  log "reloaded chronod so the widget extension is the newly signed copy"
}

remove_previous() {
  local previous="/Applications/GrokWidget.app.previous"
  local _i
  for _i in 1 2 3 4 5; do
    if [[ ! -e "$previous" ]]; then
      return 0
    fi
    if rm -rf "$previous"; then
      return 0
    fi
    sleep 0.4
  done
  if [[ -e "$previous" ]]; then
    log "could not delete $previous yet; the next run will remove it"
  fi
}

launch_host() {
  local err=""
  local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  local _i
  if [[ -x "$lsregister" ]]; then
    "$lsregister" -f "$DEST" || true
  fi
  err="$(open -a GrokWidget 2>&1)" || true
  if [[ -n "$err" ]]; then
    log "open -a GrokWidget: $err"
  else
    log "open -a GrokWidget"
  fi
  for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if pgrep -x GrokWidget >/dev/null 2>&1; then
      log "GrokWidget is running (pid $(pgrep -x GrokWidget | head -n 1))"
      return 0
    fi
    sleep 0.25
  done
  log "GrokWidget did not stay running after open -a"
  return 1
}

install_built_app() {
  local built="$1"
  local previous="/Applications/GrokWidget.app.previous"
  local appex=""
  local built_team=""
  appex="$built/Contents/PlugIns/GrokUsageWidget.appex"
  if [[ ! -d "$built" || ! -d "$appex" ]]; then
    log "build finished without $built"
    return 1
  fi
  if ! signature_ok "$built"; then
    log "built app failed codesign --verify --deep --strict; leaving $DEST unchanged"
    return 1
  fi
  if ! profiles_in_future "$built"; then
    log "built profiles are missing or not in the future (app ${APP_EXPIRY:-missing}, appex ${APPEX_EXPIRY:-missing}); leaving $DEST unchanged"
    return 1
  fi
  if ! entitlements_ok "$built" || ! entitlements_ok "$appex"; then
    log "built app or widget is missing the app group or keychain access group; leaving $DEST unchanged"
    return 1
  fi
  built_team="$(team_of "$built")"
  if [[ -z "$built_team" || "$built_team" != "$TEAM" ]]; then
    log "built app is not signed for the selected development team; leaving $DEST unchanged"
    return 1
  fi
  log "built app verified; app profile expiry $APP_EXPIRY; appex profile expiry $APPEX_EXPIRY"

  stage_dir="$(mktemp -d /Applications/.GrokWidget.resign.XXXXXX)"
  ditto "$built" "$stage_dir/GrokWidget.app"
  if ! signature_ok "$stage_dir/GrokWidget.app" || ! profiles_in_future "$stage_dir/GrokWidget.app"; then
    log "staged copy failed verification; leaving $DEST unchanged"
    return 1
  fi

  quit_host
  remove_previous
  if [[ -d "$DEST" ]]; then
    if ! mv "$DEST" "$previous"; then
      log "could not move $DEST aside"
      return 1
    fi
  fi
  if ! mv "$stage_dir/GrokWidget.app" "$DEST"; then
    log "could not move the new app into place; restoring the previous copy"
    if [[ -d "$previous" && ! -d "$DEST" ]]; then
      mv "$previous" "$DEST" || log "restore of the previous app failed"
    fi
    return 1
  fi
  rmdir "$stage_dir" 2>/dev/null || true
  stage_dir=""

  if xattr -l "$DEST" 2>/dev/null | grep -q 'com.apple.quarantine'; then
    xattr -dr com.apple.quarantine "$DEST" || true
    log "cleared quarantine on $DEST"
  fi
  if ! signature_ok "$DEST" || ! profiles_in_future "$DEST"; then
    log "installed app failed verification; restoring the previous copy"
    rm -rf "$DEST"
    if [[ -d "$previous" ]]; then
      mv "$previous" "$DEST" || log "restore of the previous app failed"
    fi
    return 1
  fi
  log "installed $DEST; new app profile expiry $APP_EXPIRY; new appex profile expiry $APPEX_EXPIRY"
  return 0
}

rebuild() {
  local built="$root/build/DerivedData/Build/Products/Release/GrokWidget.app"
  local build_status=0
  local reason=""
  on_exit_reason="build"
  if ! ensure_xcode; then
    finish_failure account
  fi
  if ! read_team; then
    finish_failure account
  fi
  if ! security find-identity -p codesigning -v 2>/dev/null | grep -q "Apple Development"; then
    log "No Apple Development identity is in the login keychain. Open Xcode > Settings > Accounts and sign back in."
    finish_failure account
  fi
  log "Building GrokWidgetApp (Release) with automatic signing."
  set +e
  run_with_timeout "$BUILD_TIMEOUT_SECONDS" \
    "$DEVELOPER_DIR/usr/bin/xcodebuild" \
    -project "$root/GrokWidget.xcodeproj" \
    -scheme GrokWidgetApp \
    -destination 'platform=macOS' \
    -configuration Release \
    -derivedDataPath "$root/build/DerivedData" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" \
    build
  build_status=$?
  set -e
  if [[ "$build_status" -ne 0 ]]; then
    reason="$(classify_failure "$build_log")"
    if [[ "$build_status" -eq 124 ]]; then
      reason="timeout"
    fi
    log "xcodebuild exited $build_status ($reason); leaving $DEST unchanged"
    finish_failure "$reason"
  fi
  on_exit_reason="account"
  if ! install_built_app "$built"; then
    finish_failure account
  fi
  RENEWED=1
  on_exit_reason="launch"
  register_widget
  if ! launch_host; then
    finish_failure launch
  fi
  reload_widget
  remove_previous
  on_exit_reason=""
  log "re-sign complete; new expiry app $APP_EXPIRY; appex $APPEX_EXPIRY"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) FORCE=1 ;;
      --check) CHECK=1 ;;
      --simulate-failure) SIMULATE="failure" ;;
      --simulate-expiring) SIMULATE="expiring" ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "error: unknown argument: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
    shift
  done
  if [[ -n "$SIMULATE" && ( "$FORCE" -eq 1 || "$CHECK" -eq 1 ) ]]; then
    echo "error: simulation flags cannot be combined with --force or --check." >&2
    exit 1
  fi
  if [[ -z "$SIMULATE" && -n "${GROK_RESIGN_SIMULATE:-}" ]]; then
    case "$GROK_RESIGN_SIMULATE" in
      failure|fail) SIMULATE="failure" ;;
      expiring|expiring-soon) SIMULATE="expiring" ;;
      *)
        echo "error: GROK_RESIGN_SIMULATE must be failure or expiring." >&2
        exit 1
        ;;
    esac
  fi
}

self_test() {
  local iso="2026-11-09T15:59:23Z"
  local state got msg
  expect() {
    local got_value="$1"
    local want="$2"
    local label="$3"
    if [[ "$got_value" != "$want" ]]; then
      printf 'self-test failed: %s: got [%s] want [%s]\n' "$label" "$got_value" "$want" >&2
      exit 1
    fi
  }
  contains() {
    local hay="$1"
    local needle="$2"
    local label="$3"
    if [[ "$hay" != *"$needle"* ]]; then
      printf 'self-test failed: %s: [%s] does not contain [%s]\n' "$label" "$hay" "$needle" >&2
      exit 1
    fi
  }
  expect "$(epoch_to_iso "$(iso_to_epoch "$iso")")" "$iso" "roundtrip"
  expect "$(normalize_expiry "2026-11-09 15:59:23 +0000")" "$iso" "normalize"
  expect "$(plan_for 1 0 $((6 * 24 * 60 * 60)))" "skip ok" "6 days"
  expect "$(plan_for 1 0 "$RENEW_WITHIN_SECONDS")" "rebuild ok" "exactly 3 days"
  expect "$(plan_for 1 0 $((RENEW_WITHIN_SECONDS + 1)))" "skip ok" "just over 3 days"
  expect "$(plan_for 1 0 "$WARN_WITHIN_SECONDS")" "rebuild warn" "exactly 48 hours"
  expect "$(plan_for 1 0 $((WARN_WITHIN_SECONDS + 1)))" "rebuild ok" "just over 48 hours"
  expect "$(plan_for 1 1000 1000)" "rebuild warn" "expires this second"
  expect "$(plan_for 1 1000 999)" "rebuild warn" "already expired"
  expect "$(plan_for 0 0 $((6 * 24 * 60 * 60)))" "rebuild ok" "verify failed"

  msg="$(failure_message account)"
  contains "$msg" "GrokWidget re-sign failed: open Xcode > Settings > Accounts and sign back in, then run " "failure copy"
  contains "$msg" "--force" "failure command"
  contains "$msg" "Log: ~/Library/Logs/GrokWidget/resign.log" "failure log"
  msg="$(expiring_message "2026-11-12T15:00:00Z" "$(iso_to_epoch "2026-11-11T03:00:00Z")")"
  contains "$msg" "GrokWidget signing expires 2026-11-12 15:00 UTC (within 48 hours) and was not renewed:" "soon copy"
  contains "$msg" "open Xcode > Settings > Accounts and sign back in, then run " "soon action"
  contains "$msg" "Log: ~/Library/Logs/GrokWidget/resign.log" "soon log"
  msg="$(expiring_message "2026-11-09T15:59:23Z" "$(iso_to_epoch "2026-11-10T15:59:23Z")")"
  contains "$msg" "GrokWidget signing expired 2026-11-09 15:59 UTC and was not renewed:" "expired copy"

  state="$(mktemp "${TMPDIR:-/tmp}/grok-resign-state.XXXXXX")"
  GROK_RESIGN_STATE_FILE="$state"
  if already_notified "resign-failed"; then
    printf 'self-test failed: empty state should not count as notified\n' >&2
    exit 1
  fi
  record_notified "resign-failed"
  if ! already_notified "resign-failed"; then
    printf 'self-test failed: resign-failed should be recorded for today\n' >&2
    exit 1
  fi
  if already_notified "expiring-soon"; then
    printf 'self-test failed: expiring-soon should be independent\n' >&2
    exit 1
  fi
  printf 'resign-failed 2000-01-01\n' > "$state"
  if already_notified "resign-failed"; then
    printf 'self-test failed: a previous day should not suppress today\n' >&2
    exit 1
  fi
  rm -f "$state"
  unset GROK_RESIGN_STATE_FILE
  printf 'self-test ok\n'
}

main() {
  cd "$root"
  if [[ "${1:-}" == "--self-test" ]]; then
    if [[ $# -ne 1 ]]; then
      echo "error: --self-test takes no other arguments." >&2
      exit 1
    fi
    self_test
    exit 0
  fi
  parse_args "$@"
  mkdir -p "$(dirname "$LOG_FILE")"
  trap cleanup EXIT

  if [[ -n "$SIMULATE" ]]; then
    acquire_lock
    if [[ "$SIMULATE" == "failure" ]]; then
      log "simulated re-sign failure; installed app was not modified"
      failure_notified=1
      notify_failure account
      exit 1
    fi
    local now soon iso
    now="$(date -u "+%s")"
    soon=$((now + 36 * 60 * 60))
    iso="$(epoch_to_iso "$soon")"
    log "simulated expiring-soon notification for $iso; installed app was not modified"
    failure_notified=1
    notify_kind "expiring-soon" "$(expiring_message "$iso" "$now")"
    exit 0
  fi

  if [[ "$CHECK" -eq 0 ]]; then
    acquire_lock
  fi
  recover_partial_swap
  read_installed
  log "installed=$INSTALLED verify_ok=$VERIFY_OK app_expiry=${INSTALLED_APP_EXPIRY:-missing} appex_expiry=${INSTALLED_APPEX_EXPIRY:-missing} force=$FORCE"
  if [[ "$CHECK" -eq 1 ]]; then
    if needs_rebuild; then
      log "check: rebuild needed"
      exit 2
    fi
    log "check: rebuild not needed; app expiry ${INSTALLED_APP_EXPIRY:-missing}; appex expiry ${INSTALLED_APPEX_EXPIRY:-missing}"
    exit 0
  fi
  if needs_rebuild; then
    if [[ "$FORCE" -eq 1 ]]; then
      log "rebuilding because --force was set"
    elif [[ "$INSTALLED" -eq 0 ]]; then
      log "rebuilding because $DEST is not installed"
    elif [[ "$VERIFY_OK" -eq 0 ]]; then
      log "rebuilding because codesign --verify --deep --strict failed"
    else
      log "rebuilding because a profile is expired or inside 3 days (app ${INSTALLED_APP_EXPIRY:-missing}, appex ${INSTALLED_APPEX_EXPIRY:-missing})"
    fi
    rebuild
    exit 0
  fi
  log "profile still valid; app expiry $INSTALLED_APP_EXPIRY; appex expiry $INSTALLED_APPEX_EXPIRY; skipping build"
  exit 0
}

main "$@"
