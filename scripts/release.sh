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
    echo "  whatsnew          Create/edit curated App Store release notes"
    echo "  changelog        Generate release notes from git log since last tag"
    echo "  tag <version>   Create a git tag and GitHub Release"
    echo "  release         Full pipeline: check → bump → commit → archive → upload → changelog → tag"
    echo ""
    echo "Options:"
    echo "  --version X.Y.Z Set the marketing version (for bump and release)"
    echo "  --dry-run       Show what would happen without making changes"
    echo ""
    echo "Examples:"
    echo "  scripts/release.sh bump                    # build 5 → 6"
    echo "  scripts/release.sh bump --version 1.0.1    # build 5 → 6, version → 1.0.1"
    echo "  scripts/release.sh release --version 1.0.1 # full release pipeline"
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
    local current_version
    current_version=$(current_marketing_version)
    local new_build="${1:-$((current + 1))}"

    step "Bumping build number: $current → $new_build"

    if [ "${DRY_RUN:-}" = "1" ]; then
        warn "Dry run — no changes made"
        return
    fi

    sed -i '' "s/CURRENT_PROJECT_VERSION = $current;/CURRENT_PROJECT_VERSION = $new_build;/g" "$PBXPROJ"
    pass "Build number updated to $new_build"

    if [ -n "$NEW_VERSION" ]; then
        step "Setting marketing version: $current_version → $NEW_VERSION"
        sed -i '' "s/MARKETING_VERSION = $current_version;/MARKETING_VERSION = $NEW_VERSION;/g" "$PBXPROJ"
        pass "Marketing version updated to $NEW_VERSION"
    fi
}

cmd_archive() {
    local version
    version=$(current_marketing_version)
    local build
    build=$(current_build_number)

    step "Archiving Pilgrim $version ($build)"

    rm -rf "$ARCHIVE_PATH"

    local auth_flags=""
    if [ -n "${APP_STORE_API_KEY:-}" ] && [ -n "${APP_STORE_API_ISSUER:-}" ]; then
        local key_path="$HOME/.private_keys/AuthKey_${APP_STORE_API_KEY}.p8"
        if [ -f "$key_path" ]; then
            auth_flags="-allowProvisioningUpdates -authenticationKeyPath $key_path -authenticationKeyID $APP_STORE_API_KEY -authenticationKeyIssuerID $APP_STORE_API_ISSUER"
        fi
    fi

    xcodebuild archive \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -sdk iphoneos \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        CODE_SIGN_STYLE=Manual \
        -quiet \
        $auth_flags || fail "Archive failed"

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

    local auth_flags=""
    if [ -n "${APP_STORE_API_KEY:-}" ] && [ -n "${APP_STORE_API_ISSUER:-}" ]; then
        local key_path="$HOME/.private_keys/AuthKey_${APP_STORE_API_KEY}.p8"
        if [ -f "$key_path" ]; then
            auth_flags="-allowProvisioningUpdates -authenticationKeyPath $key_path -authenticationKeyID $APP_STORE_API_KEY -authenticationKeyIssuerID $APP_STORE_API_ISSUER"
        fi
    fi

    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportOptionsPlist "$EXPORT_OPTIONS" \
        -exportPath "$EXPORT_PATH" \
        -quiet \
        $auth_flags || fail "Export failed"

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
    git push origin "$tag"
    pass "Tag $tag created and pushed"

    if command -v gh &>/dev/null; then
        step "Creating GitHub Release"
        gh release create "$tag" \
            --title "Pilgrim $tag" \
            --generate-notes || warn "GitHub Release creation failed (non-fatal)"
        pass "GitHub Release created"
    else
        warn "gh CLI not installed — create GitHub Release manually"
    fi
}

cmd_changelog() {
    local last_tag
    last_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

    local range
    if [ -n "$last_tag" ]; then
        range="$last_tag..HEAD"
        step "Changelog since $last_tag"
    else
        range="HEAD"
        step "Changelog (all commits — no previous tag found)"
    fi

    local feats="" fixes="" styles=""

    while IFS= read -r line; do
        local msg="${line#* }"
        local clean
        case "$msg" in
            feat:*|feat\(*)
                clean=$(echo "$msg" | sed 's/^feat([^)]*): *//;s/^feat: *//')
                feats="$feats- $clean
" ;;
            fix:*|fix\(*)
                clean=$(echo "$msg" | sed 's/^fix([^)]*): *//;s/^fix: *//')
                fixes="$fixes- $clean
" ;;
            style:*|style\(*)
                clean=$(echo "$msg" | sed 's/^style([^)]*): *//;s/^style: *//')
                styles="$styles- $clean
" ;;
        esac
    done < <(git log "$range" --oneline --no-merges 2>/dev/null)

    mkdir -p build

    # Developer changelog (GitHub Release)
    {
        echo "# Pilgrim $(current_marketing_version)"
        echo ""
        if [ -n "$feats" ]; then
            echo "## What's New"
            echo "$feats"
        fi
        if [ -n "$fixes" ]; then
            echo "## Bug Fixes"
            echo "$fixes"
        fi
        if [ -n "$styles" ]; then
            echo "## Visual Polish"
            echo "$styles"
        fi
    } > build/changelog.md

    # App Store release notes (user-friendly)
    # For v1.0.0: use the curated first-release template
    # For patches: auto-generate from feat/fix commits
    local version
    version=$(current_marketing_version)

    if [ -f "build/whatsnew.txt" ]; then
        cp build/whatsnew.txt build/releasenotes.txt
    else
        {
            if [ -n "$feats" ]; then echo "$feats"; fi
            if [ -n "$fixes" ]; then echo "$fixes"; fi
        } | sed 's/^ *- */• /' | \
            sed 's/@[A-Za-z]*//g' | \
            sed 's/[A-Z][a-zA-Z]*View//g; s/[A-Z][a-zA-Z]*Card//g; s/[A-Z][a-zA-Z]*Manager//g' | \
            sed 's/[A-Z][a-zA-Z]*Player//g' | \
            sed 's/  */ /g; s/ ,/,/g; s/ \././g' | \
            sed '/^[•] *$/d; /^$/d' | \
            head -8 > build/releasenotes.txt
    fi

    pass "Developer changelog: build/changelog.md"
    pass "App Store notes:     build/releasenotes.txt"

    echo ""
    echo -e "${BOLD}--- GitHub Release ---${NC}"
    cat build/changelog.md
    echo ""
    echo -e "${BOLD}--- App Store Release Notes ---${NC}"
    cat build/releasenotes.txt
}

cmd_whatsnew() {
    local version
    version=$(current_marketing_version)

    mkdir -p build

    if [ ! -f "build/whatsnew.txt" ]; then
        cat > build/whatsnew.txt << 'TEMPLATE'
Your first walk starts with a question.

• Walk, talk, meditate — three modes of attention, one path
• Voice recordings transcribed on-device by WhisperKit
• Seven voice guides with meditation prompts and ambient soundscapes
• Goshuin seals — digital pilgrimage stamps unique to each walk
• Walk with the collective — see how far pilgrims have walked together
• Celestial awareness — moon phases, zodiac, planetary hours
• View your entire journey at view.pilgrimapp.org
• Privacy-first — no accounts, no analytics, no cloud
TEMPLATE
        pass "Created build/whatsnew.txt — edit it, then run 'changelog'"
    fi

    echo -e "${BOLD}--- What's New (v$version) ---${NC}"
    cat build/whatsnew.txt
    echo ""
    echo "Edit build/whatsnew.txt to customize. The changelog command will use it."
}

cmd_release() {
    local version
    version="${NEW_VERSION:-$(current_marketing_version)}"

    echo -e "${BOLD}Pilgrim Release Pipeline — v$version${NC}"
    echo ""
    echo "This will: check → bump → commit → archive → export → upload → tag → GitHub Release"
    echo ""
    read -p "Continue? (y/N) " confirm
    [ "$confirm" = "y" ] || [ "$confirm" = "Y" ] || exit 0

    cmd_check
    cmd_bump

    step "Committing version bump"
    local build
    build=$(current_build_number)
    git add "$PBXPROJ"
    git commit -m "release: v$version (build $build)"
    git push origin main
    pass "Committed and pushed"

    cmd_archive
    cmd_export
    cmd_upload
    cmd_changelog
    cmd_tag "v$version"

    echo -e "\n${GREEN}${BOLD}Release v$version ($build) complete!${NC}"
    echo ""
    echo "App Store release notes are in build/releasenotes.txt — paste into App Store Connect."
}

DRY_RUN=0
NEW_VERSION=""
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --version) NEW_VERSION="$2"; shift ;;
        *) ARGS+=("$1") ;;
    esac
    shift
done

COMMAND="${ARGS[0]:-}"
ARG1="${ARGS[1]:-}"

case "$COMMAND" in
    check)   cmd_check ;;
    bump)    cmd_bump "$ARG1" ;;
    archive) cmd_archive ;;
    export)  cmd_export ;;
    upload)  cmd_upload ;;
    changelog) cmd_changelog ;;
    whatsnew) cmd_whatsnew ;;
    tag)     [ -z "$ARG1" ] && fail "Usage: release.sh tag <version>" ; cmd_tag "$ARG1" ;;
    release) cmd_release ;;
    *)       usage ;;
esac
