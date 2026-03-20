#!/bin/bash
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

WORKSPACE="Pilgrim.xcworkspace"
SCHEME="Pilgrim"
ARCHIVE_PATH="build/Pilgrim.xcarchive"
EXPORT_PATH="build/Export"
EXPORT_OPTIONS="scripts/ExportOptions.plist"
PBXPROJ="Pilgrim.xcodeproj/project.pbxproj"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

step() { echo -e "\n${BOLD}→ $1${NC}"; }
pass() { echo -e "  ${GREEN}✓ $1${NC}"; }
fail() { echo -e "  ${RED}✗ $1${NC}"; exit 1; }
warn() { echo -e "  ${YELLOW}! $1${NC}"; }

usage() {
    echo "Usage: scripts/release.sh <command> [options]"
    echo ""
    echo "Commands:"
    echo "  check           Validate the project is ready for release"
    echo "  bump [build]    Bump the build number (auto-increments by default)"
    echo "  archive         Build the release archive"
    echo "  export          Export the archive for App Store upload"
    echo "  upload          Upload to App Store Connect"
    echo "  tag <version>   Create a git tag (e.g., tag v1.0.0)"
    echo "  release         Run full pipeline: check → bump → archive → export → upload → tag"
    echo ""
    echo "Options:"
    echo "  --dry-run       Show what would happen without making changes"
    exit 1
}

current_marketing_version() {
    grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed 's/.*= *\(.*\);/\1/' | tr -d '[:space:]'
}

current_build_number() {
    grep -m1 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | sed 's/.*= *\(.*\);/\1/' | tr -d '[:space:]'
}

cmd_check() {
    step "Checking release readiness"
    local errors=0

    if [ ! -d "$WORKSPACE" ]; then
        fail "Workspace not found: $WORKSPACE"
    fi

    local version
    version=$(current_marketing_version)
    local build
    build=$(current_build_number)
    pass "Version: $version ($build)"

    if [ ! -f "Pilgrim/PrivacyInfo.xcprivacy" ]; then
        fail "PrivacyInfo.xcprivacy not found"
    fi
    pass "Privacy manifest present"

    if grep -q "armv7" "Pilgrim/Support Files/Info.plist" 2>/dev/null; then
        fail "Info.plist still references armv7"
    fi
    pass "Device capabilities OK (arm64)"

    step "Running SwiftLint"
    if command -v swiftlint &>/dev/null; then
        local lint_errors
        lint_errors=$(swiftlint lint --quiet 2>/dev/null | grep "error:" | wc -l | tr -d '[:space:]' || true)
        if [ "$lint_errors" -gt 0 ]; then
            fail "SwiftLint found $lint_errors error(s)"
        fi
        pass "No lint errors"
    else
        warn "SwiftLint not installed, skipping"
    fi

    step "Building (release)"
    xcodebuild build \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -sdk iphoneos \
        -configuration Release \
        -quiet \
        CODE_SIGNING_ALLOWED=NO \
        ONLY_ACTIVE_ARCH=NO || fail "Build failed"
    pass "Release build succeeded"

    step "Running tests"
    xcodebuild test \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -sdk iphonesimulator \
        -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
        -skip-testing:ScreenshotTests \
        -quiet \
        CODE_SIGNING_ALLOWED=NO \
        ONLY_ACTIVE_ARCH=YES || fail "Tests failed"
    pass "All tests passed"

    echo -e "\n${GREEN}${BOLD}Ready for release: $version ($build)${NC}"
}

cmd_bump() {
    local current
    current=$(current_build_number)
    local new_build="${1:-$((current + 1))}"

    step "Bumping build number: $current → $new_build"

    if [ "${DRY_RUN:-}" = "1" ]; then
        warn "Dry run — no changes made"
        return
    fi

    sed -i '' "s/CURRENT_PROJECT_VERSION = $current;/CURRENT_PROJECT_VERSION = $new_build;/g" "$PBXPROJ"
    pass "Build number updated to $new_build"
}

cmd_archive() {
    local version
    version=$(current_marketing_version)
    local build
    build=$(current_build_number)

    step "Archiving Pilgrim $version ($build)"

    rm -rf "$ARCHIVE_PATH"

    xcodebuild archive \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -sdk iphoneos \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        -quiet || fail "Archive failed"

    pass "Archive created at $ARCHIVE_PATH"
}

cmd_export() {
    step "Exporting for App Store"

    if [ ! -d "$ARCHIVE_PATH" ]; then
        fail "No archive found at $ARCHIVE_PATH — run 'archive' first"
    fi

    if [ ! -f "$EXPORT_OPTIONS" ]; then
        fail "ExportOptions.plist not found at $EXPORT_OPTIONS"
    fi

    rm -rf "$EXPORT_PATH"

    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportOptionsPlist "$EXPORT_OPTIONS" \
        -exportPath "$EXPORT_PATH" \
        -quiet || fail "Export failed"

    pass "IPA exported to $EXPORT_PATH"
}

cmd_upload() {
    step "Uploading to App Store Connect"

    local ipa
    ipa=$(find "$EXPORT_PATH" -name "*.ipa" -maxdepth 1 2>/dev/null | head -1)

    if [ -z "$ipa" ]; then
        fail "No IPA found in $EXPORT_PATH — run 'export' first"
    fi

    if [ "${DRY_RUN:-}" = "1" ]; then
        warn "Dry run — would upload $ipa"
        return
    fi

    xcrun altool --upload-app \
        --type ios \
        --file "$ipa" \
        --apiKey "${APP_STORE_API_KEY:-}" \
        --apiIssuer "${APP_STORE_API_ISSUER:-}" || fail "Upload failed"

    pass "Uploaded to App Store Connect"
}

cmd_tag() {
    local tag="$1"

    step "Tagging release: $tag"

    if git rev-parse "$tag" &>/dev/null; then
        fail "Tag $tag already exists"
    fi

    if [ "${DRY_RUN:-}" = "1" ]; then
        warn "Dry run — would create tag $tag"
        return
    fi

    git tag -a "$tag" -m "Release $tag"
    pass "Tag $tag created (push with: git push origin $tag)"
}

cmd_release() {
    local version
    version=$(current_marketing_version)

    echo -e "${BOLD}Pilgrim Release Pipeline — v$version${NC}"

    cmd_check
    cmd_bump
    cmd_archive
    cmd_export
    cmd_upload
    cmd_tag "v$version"

    local build
    build=$(current_build_number)
    echo -e "\n${GREEN}${BOLD}Release v$version ($build) complete!${NC}"
    echo "Don't forget to:"
    echo "  1. git add -A && git commit -m 'release: v$version'"
    echo "  2. git push origin main --tags"
    echo "  3. Fill in App Store Connect metadata"
}

DRY_RUN=0
ARGS=()
for arg in "$@"; do
    if [ "$arg" = "--dry-run" ]; then
        DRY_RUN=1
    else
        ARGS+=("$arg")
    fi
done

COMMAND="${ARGS[0]:-}"
ARG1="${ARGS[1]:-}"

case "$COMMAND" in
    check)   cmd_check ;;
    bump)    cmd_bump "$ARG1" ;;
    archive) cmd_archive ;;
    export)  cmd_export ;;
    upload)  cmd_upload ;;
    tag)     [ -z "$ARG1" ] && fail "Usage: release.sh tag <version>" ; cmd_tag "$ARG1" ;;
    release) cmd_release ;;
    *)       usage ;;
esac
