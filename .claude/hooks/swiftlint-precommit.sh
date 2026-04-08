#!/usr/bin/env bash
# Pre-commit SwiftLint gate.
#
# Claude Code PreToolUse hook that runs SwiftLint on staged Swift files
# before a `git commit` call is executed. Blocks the commit (exit 2) if
# serious lint errors would fail CI.
#
# Rationale: On 2026-04-08, the pilgrim-ios feat/collapsible-stats-panel
# PR was admin-merged to main with a clean local Xcode build, but the
# GHA lint job failed immediately because MeditationView had grown 10
# lines over SwiftLint's type_body_length: error: 750 threshold. Local
# swiftlint reported different numbers than CI. This hook catches that
# same class of error before commit, so main stays green.
#
# Gracefully skips (exit 0, no block) when any of the following is true:
#   - the bash command is not a `git commit`
#   - the command passes `--no-verify` (respect the user's bypass)
#   - swiftlint is not installed on the machine
#   - no `.swiftlint.yml` in the git repo's root (no config → no opinion)
#   - no staged `.swift` files (nothing to lint)
#
# This hook is USER-scoped (defined in ~/.claude/settings.json) so it
# applies across every Swift project. Projects without SwiftLint configured
# pass through transparently.

set -euo pipefail

# Read the tool-use payload from stdin.
payload=$(cat)

# Extract the bash command. Use python3 (guaranteed on macOS) for safe
# JSON parsing. If the structure differs from what we expect, fall back
# to allowing the action — never block on hook-internal errors.
command=$(python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get("tool_input", {}).get("command", ""))
except Exception:
    print("")
' <<< "$payload" 2>/dev/null || echo "")

# Only intercept git commit commands.
if [[ ! "$command" =~ git[[:space:]]+commit ]]; then
    exit 0
fi

# Respect --no-verify as a deliberate user bypass.
if [[ "$command" =~ --no-verify ]]; then
    exit 0
fi

# Require SwiftLint; otherwise no-op.
if ! command -v swiftlint &> /dev/null; then
    exit 0
fi

# Find the git repo root from the current working directory.
project_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [[ -z "$project_root" ]]; then
    exit 0
fi

# No config → no lint. Project opts in by having a .swiftlint.yml.
config_path="$project_root/.swiftlint.yml"
if [[ ! -f "$config_path" ]]; then
    exit 0
fi

# Collect staged Swift files (added/copied/modified/renamed).
# Paths are relative to project_root.
staged_files=$(git -C "$project_root" diff --cached --name-only --diff-filter=ACMR | grep -E '\.swift$' || true)
if [[ -z "$staged_files" ]]; then
    exit 0
fi

# Build absolute paths and verify each file still exists in the working
# tree. Skip any that were staged-then-deleted.
files_to_lint=()
while IFS= read -r rel_path; do
    abs_path="$project_root/$rel_path"
    if [[ -f "$abs_path" ]]; then
        files_to_lint+=("$abs_path")
    fi
done <<< "$staged_files"

if [[ ${#files_to_lint[@]} -eq 0 ]]; then
    exit 0
fi

# SwiftLint needs SourceKit from Xcode's toolchain. Without DEVELOPER_DIR
# pointing at Xcode, SwiftLint crashes with a sourcekitdInProc load error.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# Run SwiftLint. Capture both stdout and stderr; SwiftLint prints
# violations to stdout and its own status to stderr.
lint_output=$(swiftlint lint --config "$config_path" --quiet "${files_to_lint[@]}" 2>&1 || true)

# Serious errors in SwiftLint's output are lines containing ": error:".
# Warnings (": warning:") pass through without blocking.
serious_errors=$(echo "$lint_output" | grep -E ': error: ' || true)

if [[ -n "$serious_errors" ]]; then
    {
        echo "SwiftLint: serious errors in staged Swift files — commit blocked."
        echo ""
        echo "$serious_errors"
        echo ""
        echo "Fix the errors above and re-stage, or bypass this gate with:"
        echo "  git commit --no-verify"
    } >&2
    exit 2
fi

exit 0
