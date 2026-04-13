#!/bin/bash
#
# Pulls the canonical whisper manifest and all referenced audio files from R2
# and writes them into Pilgrim/Support Files/ as flat file resources.
#
# Idempotent. Run whenever the R2 manifest changes and you want the next
# release to bundle a fresh snapshot.
#
# Usage: scripts/regen-whisper-bootstrap.sh

set -euo pipefail

MANIFEST_URL="https://cdn.pilgrimapp.org/audio/whisper/manifest.json"
CDN_BASE="https://cdn.pilgrimapp.org/audio/whisper"
SUPPORT_DIR="Pilgrim/Support Files"
BOOTSTRAP_JSON="$SUPPORT_DIR/whispers-bootstrap.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

step() { echo -e "\n→ $1"; }
pass() { echo -e "  ${GREEN}✓ $1${NC}"; }
fail() { echo -e "  ${RED}✗ $1${NC}"; exit 1; }

command -v curl >/dev/null || fail "curl not on PATH"
command -v jq >/dev/null || fail "jq not on PATH (brew install jq)"

step "Downloading manifest from R2"
mkdir -p "$SUPPORT_DIR"
curl -fsSL "$MANIFEST_URL" -o "$BOOTSTRAP_JSON" || fail "Failed to fetch manifest"
pass "Wrote $BOOTSTRAP_JSON"

MANIFEST_VERSION=$(jq -r .version "$BOOTSTRAP_JSON")
WHISPER_COUNT=$(jq -r '.whispers | length' "$BOOTSTRAP_JSON")
pass "Manifest version=$MANIFEST_VERSION, whispers=$WHISPER_COUNT"

step "Downloading audio files"
jq -r '.whispers[] | .audioFileName' "$BOOTSTRAP_JSON" | while read -r name; do
    dest="$SUPPORT_DIR/$name.aac"
    if [ -f "$dest" ]; then
        echo "  · $name.aac (already present, skipping)"
        continue
    fi
    echo "  · $name.aac"
    curl -fsSL "$CDN_BASE/$name.aac" -o "$dest" || fail "Failed to fetch $name.aac"
done
pass "All audio files present in $SUPPORT_DIR"

step "Summary"
BUNDLED_COUNT=$(jq -r '.whispers[] | .audioFileName' "$BOOTSTRAP_JSON" | while read -r name; do
    [ -f "$SUPPORT_DIR/$name.aac" ] && echo "$name"
done | wc -l | tr -d ' ')
echo "  Bundled audio files: $BUNDLED_COUNT"
echo "  Manifest version:    $MANIFEST_VERSION"

if [ "$BUNDLED_COUNT" -ne "$WHISPER_COUNT" ]; then
    fail "File count ($BUNDLED_COUNT) does not match manifest count ($WHISPER_COUNT)"
fi

pass "Bootstrap ready. If new .aac files were added, remember to register them in the Xcode project via scripts/release.sh bootstrap-whispers (Task 11) or manually with the xcodeproj gem."
