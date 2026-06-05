#!/usr/bin/env bash
#
# release.sh — Automated release pipeline
#
# Bumps the version, creates a git tag, generates a changelog from
# conventional commits since the previous tag, and outputs a summary.
#
# Usage:
#   ./release.sh <major|minor|patch> [package.json path]
#
# Prerequisites:
#   - Must be run inside a git repository
#   - Working tree should be clean (no uncommitted changes)
#   - Conventional commit messages (feat:, fix:, chore:, etc.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $(basename "$0") <major|minor|patch> [package.json path]

Creates a new release by:
  1. Bumping the version in package.json
  2. Committing the version change
  3. Creating an annotated git tag
  4. Generating a changelog from conventional commits
  5. Printing a release summary

Options:
  -h, --help   Show this help message
  --dry-run    Show what would happen without making changes
EOF
  exit 1
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

info() {
  echo "==> $*"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
DRY_RUN=false

POSITIONAL_ARGS=()
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage ;;
    --dry-run)  DRY_RUN=true ;;
    *)          POSITIONAL_ARGS+=("$arg") ;;
  esac
done

BUMP_TYPE="${POSITIONAL_ARGS[0]:-}"
PACKAGE_JSON="${POSITIONAL_ARGS[1]:-./package.json}"

if [[ -z "$BUMP_TYPE" ]]; then
  die "Version bump type is required. Use: major, minor, or patch."
fi

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  die "Not inside a git repository."
fi

# Warn if working tree is dirty (but don't block — CI may have staged changes)
if [[ -n "$(git status --porcelain)" ]]; then
  echo "WARNING: Working tree has uncommitted changes." >&2
fi

if [[ ! -f "$PACKAGE_JSON" ]]; then
  die "File not found: $PACKAGE_JSON"
fi

# ---------------------------------------------------------------------------
# Read old version & determine last tag
# ---------------------------------------------------------------------------
if command -v jq &>/dev/null; then
  OLD_VERSION=$(jq -r '.version' "$PACKAGE_JSON")
else
  OLD_VERSION=$(grep -m1 '"version"' "$PACKAGE_JSON" | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi

# Find the most recent version tag (vX.Y.Z format)
LAST_TAG=$(git tag --list 'v[0-9]*' --sort=-version:refname | head -n1 || true)
if [[ -z "$LAST_TAG" ]]; then
  # No prior tags — use the initial commit as the baseline
  LAST_TAG=$(git rev-list --max-parents=0 HEAD 2>/dev/null | head -n1 || true)
  LAST_TAG_DISPLAY="(initial commit)"
else
  LAST_TAG_DISPLAY="$LAST_TAG"
fi

info "Current version : $OLD_VERSION"
info "Last tag        : $LAST_TAG_DISPLAY"
info "Bump type       : $BUMP_TYPE"

# ---------------------------------------------------------------------------
# Bump version
# ---------------------------------------------------------------------------
NEW_VERSION=$("${SCRIPT_DIR}/version-bump.sh" "$BUMP_TYPE" "$PACKAGE_JSON")
NEW_TAG="v${NEW_VERSION}"

info "New version     : $NEW_VERSION"
info "New tag         : $NEW_TAG"

# ---------------------------------------------------------------------------
# Generate changelog from conventional commits
# ---------------------------------------------------------------------------
generate_changelog() {
  local range
  if git tag --list 'v[0-9]*' --sort=-version:refname | head -n1 | grep -q .; then
    range="${LAST_TAG}..HEAD"
  else
    range="HEAD"
  fi

  local features="" fixes="" breaking="" other=""

  while IFS= read -r line; do
    # Skip empty lines
    [[ -z "$line" ]] && continue

    # Extract the commit subject (strip hash prefix if present)
    local subject
    subject=$(echo "$line" | sed 's/^[a-f0-9]* //')

    case "$subject" in
      feat\!:*|feat\(*\)\!:*)
        breaking+="- ${subject}"$'\n'
        ;;
      feat:*|feat\(*\):*)
        features+="- ${subject}"$'\n'
        ;;
      fix:*|fix\(*\):*)
        fixes+="- ${subject}"$'\n'
        ;;
      BREAKING[[:space:]]CHANGE:*|BREAKING-CHANGE:*)
        breaking+="- ${subject}"$'\n'
        ;;
      docs:*|chore:*|ci:*|style:*|refactor:*|perf:*|test:*|build:*)
        other+="- ${subject}"$'\n'
        ;;
      *)
        other+="- ${subject}"$'\n'
        ;;
    esac
  done < <(git log --oneline "$range" 2>/dev/null || true)

  echo "# Release ${NEW_TAG}"
  echo ""
  echo "**Released:** $(date -u +"%Y-%m-%d")"
  echo "**Previous:** ${LAST_TAG_DISPLAY}"
  echo ""

  if [[ -n "$breaking" ]]; then
    echo "## BREAKING CHANGES"
    echo "$breaking"
  fi

  if [[ -n "$features" ]]; then
    echo "## Features"
    echo "$features"
  fi

  if [[ -n "$fixes" ]]; then
    echo "## Bug Fixes"
    echo "$fixes"
  fi

  if [[ -n "$other" ]]; then
    echo "## Other Changes"
    echo "$other"
  fi
}

CHANGELOG=$(generate_changelog)

# ---------------------------------------------------------------------------
# Commit, tag, and write changelog (unless --dry-run)
# ---------------------------------------------------------------------------
if [[ "$DRY_RUN" == true ]]; then
  info "[DRY RUN] Would commit version bump, create tag $NEW_TAG"
  echo ""
  echo "$CHANGELOG"
  exit 0
fi

# Stage the updated package.json
git add "$PACKAGE_JSON"

# Commit the version bump
git commit -m "chore(release): bump version to ${NEW_VERSION}

Automated release: ${OLD_VERSION} -> ${NEW_VERSION}" --allow-empty

# Create annotated tag
git tag -a "$NEW_TAG" -m "Release ${NEW_VERSION}

${CHANGELOG}"

# Write changelog to CHANGELOG.md (append at top if it exists)
CHANGELOG_FILE="$(dirname "$PACKAGE_JSON")/CHANGELOG.md"
if [[ -f "$CHANGELOG_FILE" ]]; then
  EXISTING=$(cat "$CHANGELOG_FILE")
  {
    echo "$CHANGELOG"
    echo ""
    echo "---"
    echo ""
    echo "$EXISTING"
  } > "$CHANGELOG_FILE"
else
  echo "$CHANGELOG" > "$CHANGELOG_FILE"
fi

git add "$CHANGELOG_FILE"
git commit -m "docs(release): update changelog for ${NEW_VERSION}" --allow-empty

# Move the tag to include the changelog commit
git tag -f -a "$NEW_TAG" -m "Release ${NEW_VERSION}

${CHANGELOG}"

# ---------------------------------------------------------------------------
# Release summary
# ---------------------------------------------------------------------------
COMMIT_COUNT=$(git log --oneline "${LAST_TAG}..HEAD" 2>/dev/null | wc -l | tr -d ' ')

cat <<EOF

============================================================
  RELEASE SUMMARY
============================================================
  Version   : ${OLD_VERSION} -> ${NEW_VERSION}
  Tag       : ${NEW_TAG}
  Commits   : ${COMMIT_COUNT} since ${LAST_TAG_DISPLAY}
  Date      : $(date -u +"%Y-%m-%dT%H:%M:%SZ")
============================================================

Next steps:
  1. Push the tag        : git push origin ${NEW_TAG}
  2. Push the branch     : git push origin $(git branch --show-current)
  3. Create GitHub release: gh release create ${NEW_TAG} --generate-notes

${CHANGELOG}
EOF
