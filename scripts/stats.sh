#!/usr/bin/env bash
#
# How many times each published build has been downloaded.
#
# GitHub counts this on its own, for every asset of every release, from the
# moment the release exists. Nothing had to be enabled and nothing in the app
# reports anything: this is the whole of the project's usage measurement, and
# it is deliberate.
#
# Read it with:
#
#   ./scripts/stats.sh
#
# Three things it is not:
#
# - it counts DOWNLOADS, not installs. Bots, mirrors and interrupted retries
#   are in there, so it runs high;
# - a counter RESETS if an asset is deleted and re-uploaded, so never edit a
#   published release in place;
# - the auto-generated source tarballs are not counted at all.
#
# Homebrew installs do appear, since `brew` fetches the release asset like
# anyone else. Once the app is public, this is the number to watch.
#
set -euo pipefail

REPO="${1:-eliorpom-cmd/to-be-downloaded}"

if ! command -v gh >/dev/null 2>&1; then
  echo "The GitHub CLI is needed: brew install gh" >&2
  exit 1
fi

printf '%s\n\n' "Downloads — $REPO"

# The single quotes are the point: what follows is a jq program, and $tag is
# jq's variable, not the shell's.
# shellcheck disable=SC2016
gh api "repos/$REPO/releases" --paginate --jq '
  .[] | .tag_name as $tag
  | .assets[]
  | select(.name | endswith(".sig") | not)
  | "\(.download_count)\t\($tag)\t\(.name)"
' | sort -rn | awk -F'\t' '{ printf "%8s  %-10s %s\n", $1, $2, $3 }'

printf '\n%s\n' "Signatures are left out: one is fetched per update check, not per human."
