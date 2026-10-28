#!/bin/zsh
# Builds Pane, quits the running copy, installs to /Applications/Pane.app and launches it.
set -euo pipefail

ROOT="${0:A:h:h}"
BUNDLE_ID="com.karunpai.Pane"
DEST="/Applications/Pane.app"

"$ROOT/scripts/build-app.sh"

if pgrep -x Pane >/dev/null; then
  echo "==> Quitting running Pane"
  osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || true
  for i in {1..50}; do
    pgrep -x Pane >/dev/null || break
    sleep 0.1
  done
  if pgrep -x Pane >/dev/null; then
    pkill -x Pane || true
    sleep 0.5
  fi
fi

echo "==> Installing to $DEST"
rm -rf "$DEST"
ditto "$ROOT/build/Pane.app" "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true

echo "==> Launching Pane"
open "$DEST"
