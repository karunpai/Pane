#!/bin/zsh
# Pulls the latest source and reinstalls Pane. (The repo is private, so the app can't check
# for updates itself; this is the update path.)
set -euo pipefail

ROOT="${0:A:h:h}"
git -C "$ROOT" pull --ff-only
"$ROOT/scripts/install.sh"
