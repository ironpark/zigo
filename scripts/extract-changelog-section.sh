#!/usr/bin/env bash
# Extracts one version's section from CHANGELOG.md, for use as a GitHub
# release body. `release.yml` runs this against the tag it just built.
#
# Usage: extract-changelog-section.sh <version> [changelog-file]
#   version         e.g. 0.2.0 (no leading "v", matches "## [0.2.0]" in the file)
#   changelog-file  defaults to CHANGELOG.md in the repository root
#
# Prints the body between the "## [<version>] - ..." heading (exclusive) and
# the next "## [" heading (exclusive) to stdout. Exits non-zero if the
# heading is not found.
set -euo pipefail

version="${1:?usage: extract-changelog-section.sh <version> [changelog-file]}"
file="${2:-$(dirname "$0")/../CHANGELOG.md}"

if [[ ! -f "$file" ]]; then
  echo "extract-changelog-section.sh: no such file: $file" >&2
  exit 1
fi

set +e
section=$(awk -v ver="$version" '
  BEGIN { found = 0; printing = 0 }
  # Match "## [0.2.0]" exactly, not "## [0.20.0]" or "## [Unreleased]".
  $0 ~ "^## \\[" ver "\\]" {
    found = 1
    printing = 1
    next
  }
  printing && /^## \[/ { printing = 0 }
  printing { print }
  END { if (!found) exit 1 }
' "$file")
status=$?
set -e

if [[ $status -ne 0 ]]; then
  echo "extract-changelog-section.sh: no '## [$version]' section in $file" >&2
  exit 1
fi

# Trim leading/trailing blank lines so the release body does not start or
# end with empty space. `sed` handles this in one pass without relying on
# `tac`, which is not available on macOS/BSD.
printf '%s\n' "$section" | sed -e '/./,$!d' -e ':a' -e '/^\n*$/{$d;N;ba' -e '}'
