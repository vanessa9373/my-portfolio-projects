#!/usr/bin/env bash
#
# version-bump.sh — Bumps the semver version in package.json
#
# Usage:
#   ./version-bump.sh <major|minor|patch> [path/to/package.json]
#
# If no package.json path is given, defaults to ./package.json in the
# current working directory.

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $(basename "$0") <major|minor|patch> [package.json path]

Arguments:
  major   Bump the major version (e.g. 1.2.3 -> 2.0.0)
  minor   Bump the minor version (e.g. 1.2.3 -> 1.3.0)
  patch   Bump the patch version (e.g. 1.2.3 -> 1.2.4)

Options:
  -h, --help  Show this help message
EOF
  exit 1
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
fi

BUMP_TYPE="${1:-}"
PACKAGE_JSON="${2:-./package.json}"

if [[ -z "$BUMP_TYPE" ]]; then
  die "Version bump type is required. Use: major, minor, or patch."
fi

if [[ "$BUMP_TYPE" != "major" && "$BUMP_TYPE" != "minor" && "$BUMP_TYPE" != "patch" ]]; then
  die "Invalid bump type '$BUMP_TYPE'. Must be one of: major, minor, patch."
fi

if [[ ! -f "$PACKAGE_JSON" ]]; then
  die "File not found: $PACKAGE_JSON"
fi

# ---------------------------------------------------------------------------
# Read current version
# ---------------------------------------------------------------------------
# Extract version without requiring jq (falls back to grep/sed if needed).
if command -v jq &>/dev/null; then
  CURRENT_VERSION=$(jq -r '.version' "$PACKAGE_JSON")
else
  # Portable fallback — works with standard grep + sed
  CURRENT_VERSION=$(grep -m1 '"version"' "$PACKAGE_JSON" | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi

if [[ -z "$CURRENT_VERSION" || "$CURRENT_VERSION" == "null" ]]; then
  die "Could not read version from $PACKAGE_JSON"
fi

# Validate semver format (MAJOR.MINOR.PATCH, optional pre-release ignored)
if ! echo "$CURRENT_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+'; then
  die "Current version '$CURRENT_VERSION' is not valid semver (expected MAJOR.MINOR.PATCH)."
fi

# ---------------------------------------------------------------------------
# Compute new version
# ---------------------------------------------------------------------------
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

case "$BUMP_TYPE" in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"

# ---------------------------------------------------------------------------
# Update package.json
# ---------------------------------------------------------------------------
# Use a temp file for atomic write to avoid corruption on failure.
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

if command -v jq &>/dev/null; then
  jq --arg v "$NEW_VERSION" '.version = $v' "$PACKAGE_JSON" > "$TMPFILE"
else
  # Portable sed replacement — only replaces the first "version" occurrence.
  sed "s/\"version\"[[:space:]]*:[[:space:]]*\"${CURRENT_VERSION}\"/\"version\": \"${NEW_VERSION}\"/" "$PACKAGE_JSON" > "$TMPFILE"
fi

mv "$TMPFILE" "$PACKAGE_JSON"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
echo "$NEW_VERSION"
