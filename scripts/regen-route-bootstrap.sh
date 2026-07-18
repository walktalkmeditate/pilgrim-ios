#!/bin/bash
#
# Pulls the canonical collective-route artifact from the CDN and writes it into
# Pilgrim/Support Files/ so a fresh install with no network still rotates a
# route on day one.
#
# Idempotent. Run whenever the artifact is re-baked and published in
# pilgrim-landing and you want the next release to bundle a fresh snapshot.
#
# Usage: scripts/regen-route-bootstrap.sh

set -euo pipefail

CATALOG_URL="https://cdn.pilgrimapp.org/collective/routes.json"
SUPPORT_DIR="Pilgrim/Support Files"
BOOTSTRAP_NAME="collective-routes-bootstrap.json"
BOOTSTRAP_JSON="$SUPPORT_DIR/$BOOTSTRAP_NAME"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

step() { echo -e "\n→ $1"; }
pass() { echo -e "  ${GREEN}✓ $1${NC}"; }
fail() { echo -e "  ${RED}✗ $1${NC}"; exit 1; }

command -v curl >/dev/null || fail "curl not on PATH"
command -v jq >/dev/null || fail "jq not on PATH (brew install jq)"

# Download to a scratch file and only move it into place once it validates. The
# committed bootstrap is what every CI-built binary ships, so a truncated or
# error-page response must never be allowed to overwrite a good one.
TMP_JSON=$(mktemp -t collective-routes)
trap 'rm -f "$TMP_JSON"' EXIT

step "Downloading catalog from the CDN"
curl -fsSL "$CATALOG_URL" -o "$TMP_JSON" || fail "Failed to fetch $CATALOG_URL"
jq -e . "$TMP_JSON" >/dev/null 2>&1 || fail "Response is not valid JSON"
pass "Fetched $CATALOG_URL"

step "Verifying the artifact"
VERSION=$(jq -r '.version // ""' "$TMP_JSON")
[ -n "$VERSION" ] || fail "Artifact has no version — the app compares versions to decide when to refresh"

TOTAL=$(jq '((.pilgrimages // []) + (.horizons // [])) | length' "$TMP_JSON")
[ "$TOTAL" -gt 0 ] || fail "Artifact contains no entries"

# Mirrors CollectiveRoute's decode contract exactly. Entries the app cannot
# parse are dropped by the catalog's lossy array decode, which is deliberate —
# it keeps a schema change from bricking clients in the wild, but it also means
# a bad bake would bundle a half-empty catalog with no runtime signal at all.
# Catching it here is the only place it makes a noise.
#
# Each array is checked against its own kind rather than the two merged, because
# a cosmic entry filed under .pilgrimages decodes cleanly on both platforms and
# still splits them: pilgrim-landing's orderedEntries lays the day out by source
# array while the Swift catalog lays it out by decoded kind, so the entry lands
# at a different index on each and the two offer different routes for the same
# date. Both sides stay silent about it — this is the only guard upstream.
REJECTED=$(jq -r '
    def decodes($kind):
        (.id | type == "string")
        and (.companyLine | type == "string")
        and (.km | type) == "number" and .km > 0
        and .kind == $kind
        and (
            ($kind == "route" and (.nameEn | type == "string"))
            or ($kind == "cosmic" and (.preposition | type == "string") and (.body | type == "string"))
        );
    def reject($array; $kind):
        ((.[$array] // [])[] | select(decodes($kind) | not) | "\($array): \(.id // "(no id)") — "
            + (if .kind != $kind
               then "kind is \(.kind // "(none)"), expected \($kind) (mis-filed array)"
               else "fails the \($kind) decode contract" end));
    reject("pilgrimages"; "route"), reject("horizons"; "cosmic")
' "$TMP_JSON")

if [ -n "$REJECTED" ]; then
    echo "$REJECTED" | while IFS= read -r entry; do echo "  · $entry"; done
    REJECTED_COUNT=$(echo "$REJECTED" | wc -l | tr -d '[:space:]')
    fail "$REJECTED_COUNT of $TOTAL entries would be dropped or mis-filed by the app — re-bake in pilgrim-landing before publishing"
fi
pass "version=$VERSION, entries=$TOTAL (all decodable, each in its own array)"

step "Writing $BOOTSTRAP_JSON"
mkdir -p "$SUPPORT_DIR"
if [ -f "$BOOTSTRAP_JSON" ] && cmp -s "$TMP_JSON" "$BOOTSTRAP_JSON"; then
    pass "Already up to date (unchanged)"
else
    cp "$TMP_JSON" "$BOOTSTRAP_JSON"
    # mktemp creates 0600 and cp carries that onto a new destination, which
    # would leave the bundled artifact readable only by whoever ran the script.
    chmod 644 "$BOOTSTRAP_JSON"
    pass "Wrote $BOOTSTRAP_JSON"
fi

step "Registering the bootstrap in the Xcode project"
PROJECT="Pilgrim.xcodeproj"
[ -d "$PROJECT" ] || fail "$PROJECT not found"
command -v ruby >/dev/null || fail "ruby not on PATH"
ruby -e "require 'xcodeproj'" 2>/dev/null || fail "xcodeproj gem not installed (gem install xcodeproj)"

# The sibling whisper script registers only the audio files it enumerates, never
# the manifest itself — that entry was hand-added once and nothing would notice
# if it were ever lost. This registers the JSON it just downloaded, and checks
# the Copy Bundle Resources membership separately from the group membership:
# a file reference can sit in the group while missing from the build phase, and
# that combination ships a binary with no bootstrap in it.
ACTIONS=$(ruby -e '
require "xcodeproj"
filename = ARGV[0]
project = Xcodeproj::Project.open("Pilgrim.xcodeproj")
target = project.targets.find { |t| t.name == "Pilgrim" } or abort "Pilgrim target not found"
group = project.main_group["Pilgrim"]["Support Files"] or abort "Support Files group not found"

actions = []
file_ref = group.files.find { |f| f.path == filename }
if file_ref.nil?
    file_ref = group.new_file(filename)
    actions << "added file reference to Support Files"
end

phase = target.resources_build_phase
unless phase.files_references.include?(file_ref)
    phase.add_file_reference(file_ref)
    actions << "added to Copy Bundle Resources"
end

project.save unless actions.empty?
actions.each { |a| puts a }
' "$BOOTSTRAP_NAME")

if [ -n "$ACTIONS" ]; then
    echo "$ACTIONS" | while IFS= read -r a; do echo "  · $a"; done
    pass "Xcode project updated"
else
    pass "Already registered in the Pilgrim target"
fi

pass "Bootstrap ready."
