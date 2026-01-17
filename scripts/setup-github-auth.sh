#!/bin/bash
# Setup GitHub authentication for this repo (multi-account safe).
#
# Key idea: avoid `gh auth switch` (global) and instead export `GH_TOKEN`
# for the desired account for this shell session.
set -euo pipefail

fail() {
  echo "Error: $*" >&2
  if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    return 1
  fi
  exit 1
}

if [ -f .env.local ]; then
  # shellcheck disable=SC1091
  source .env.local
fi

: "${GITHUB_HOST:=github.com}"
: "${GITHUB_USER:=dels78}"

command -v gh >/dev/null 2>&1 || fail "GitHub CLI (gh) is not installed. Run: gh auth login -h ${GITHUB_HOST}"

if ! gh auth status -h "${GITHUB_HOST}" >/dev/null 2>&1; then
  fail "gh is not authenticated for ${GITHUB_HOST}. Run: gh auth login -h ${GITHUB_HOST}"
fi

# Avoid accidental overrides from other environments (e.g. Haus).
unset GITHUB_TOKEN || true

export GH_TOKEN
GH_TOKEN="$(gh auth token --hostname "${GITHUB_HOST}" --user "${GITHUB_USER}")" || true
if [ -z "${GH_TOKEN}" ]; then
  fail "No oauth token found for ${GITHUB_HOST} account ${GITHUB_USER}. Log in: gh auth login -h ${GITHUB_HOST}"
fi

# Backwards-compat: some scripts/tools still look for GITHUB_TOKEN.
export GITHUB_TOKEN="${GH_TOKEN}"

echo "✓ GH_TOKEN exported for ${GITHUB_USER} (${GITHUB_HOST})"
echo "To use in your current shell, run:"
echo "  source scripts/setup-github-auth.sh"

