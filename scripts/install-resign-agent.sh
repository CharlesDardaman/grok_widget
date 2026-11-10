#!/bin/bash
# Install or remove the user LaunchAgent that runs scripts/resign.sh.
#
#   ./scripts/install-resign-agent.sh
#   ./scripts/install-resign-agent.sh --uninstall
#
# The agent runs at 09:15 local time, at login, and after wake when 09:15
# was missed while the Mac was asleep. It stores this checkout's path.
# Run it again if the repo moves.

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
label="com.charlesdardaman.grok-widget.resign"
plist="${HOME}/Library/LaunchAgents/${label}.plist"
uid="$(id -u)"
domain="gui/${uid}"
script="${root}/scripts/resign.sh"
log_dir="${HOME}/Library/Logs/GrokWidget"

uninstall=0
if [[ $# -gt 1 ]]; then
  echo "error: too many arguments." >&2
  exit 1
fi
if [[ $# -eq 1 ]]; then
  if [[ "$1" != "--uninstall" ]]; then
    echo "error: unknown argument: $1 (expected --uninstall)." >&2
    exit 1
  fi
  uninstall=1
fi

bootout_agent() {
  launchctl bootout "${domain}/${label}" >/dev/null 2>&1 || true
  if [[ -f "$plist" ]]; then
    launchctl bootout "$domain" "$plist" >/dev/null 2>&1 || true
  fi
}

if [[ "$uninstall" -eq 1 ]]; then
  bootout_agent
  rm -f "$plist"
  echo "Removed the ${label} LaunchAgent if it was installed."
  echo "/Applications/GrokWidget.app and ${log_dir} were left in place."
  exit 0
fi

if [[ ! -f "$script" ]]; then
  echo "error: $script is missing." >&2
  exit 1
fi

case "${root}${script}${log_dir}" in
  *'&'*|*'<'*|*'>'*)
    echo "error: the checkout path cannot be stored in the LaunchAgent plist." >&2
    exit 1
    ;;
esac

mkdir -p "${HOME}/Library/LaunchAgents" "$log_dir"
bootout_agent

cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${label}</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>${script}</string>
	</array>
	<key>WorkingDirectory</key>
	<string>${root}</string>
	<key>RunAtLoad</key>
	<true/>
	<key>StartCalendarInterval</key>
	<dict>
		<key>Hour</key>
		<integer>9</integer>
		<key>Minute</key>
		<integer>15</integer>
	</dict>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>StandardOutPath</key>
	<string>${log_dir}/resign.launchd.out.log</string>
	<key>StandardErrorPath</key>
	<string>${log_dir}/resign.launchd.err.log</string>
	<key>EnvironmentVariables</key>
	<dict>
		<key>PATH</key>
		<string>/usr/bin:/bin:/usr/sbin:/sbin</string>
	</dict>
</dict>
</plist>
EOF

plutil -lint "$plist" >/dev/null
chmod 644 "$plist"
launchctl enable "${domain}/${label}"
launchctl bootstrap "$domain" "$plist"

echo "Installed ${plist}"
echo "Runs ${script} at 09:15 local time, at login, and after wake if 09:15 was missed."
echo "Log: ${log_dir}/resign.log"
