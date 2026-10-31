#!/bin/zsh
# Tags the current commit as v<VERSION>, builds, and publishes a GitHub release with the DMG and zip.
# Bump VERSION and commit before running.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree has uncommitted changes; commit or stash them first" >&2
  exit 1
fi

VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"
ZIP="build/Pane-$VERSION-arm64.zip"
DMG="build/Pane-$VERSION.dmg"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "error: tag $TAG already exists; bump VERSION first" >&2
  exit 1
fi

"$ROOT/scripts/build-app.sh"

git tag -a "$TAG" -m "Pane $VERSION"
git push origin "$TAG"
# Release notes come from this version's section of CHANGELOG.md when there is one.
NOTES="$(awk -v v="## $VERSION" '$0==v{f=1;next} /^## /{f=0} f' CHANGELOG.md 2>/dev/null || true)"
if [[ -n "${NOTES//[[:space:]]/}" ]]; then
  gh release create "$TAG" "$DMG" "$ZIP" --title "Pane $VERSION" --notes "$NOTES"
else
  gh release create "$TAG" "$DMG" "$ZIP" --title "Pane $VERSION" --generate-notes
fi
echo "==> Released Pane $VERSION"
