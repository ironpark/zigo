#!/usr/bin/env bash
# Runs the release checklist from CONTRIBUTING.md end to end: format
# check, the full test suite, every example's generated-tree check,
# staticcheck over the example Go modules, then the version bump
# (CHANGELOG section, build.zig.zon, README and getting-started fetch lines),
# the release commit and the tag. Pushing is opt-in.
#
# Usage: scripts/release.sh <version> [--push] [--skip-checks]
#   version        e.g. 0.14.3 (no leading "v"; becomes the tag and the
#                  "## [0.14.3] - <today>" CHANGELOG heading)
#   --push         push the branch and the tag to origin after tagging
#   --skip-checks  skip fmt/test/example/staticcheck (for re-running the
#                  bump after a check that failed for an unrelated reason)
#
# Refuses to run on a dirty working tree, when the tag already exists, or
# when CHANGELOG.md has no "## [Unreleased]" section with content.
set -euo pipefail

usage() {
  echo "usage: scripts/release.sh <version> [--push] [--skip-checks]" >&2
  exit 2
}

version=""
push=0
skip_checks=0
for arg in "$@"; do
  case "$arg" in
    --push) push=1 ;;
    --skip-checks) skip_checks=1 ;;
    -*) usage ;;
    *) [[ -z "$version" ]] && version="$arg" || usage ;;
  esac
done
[[ -n "$version" ]] || usage
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "release.sh: version must be x.y.z without a 'v' prefix: $version" >&2
  exit 2
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

step() { printf '\n==> %s\n' "$*"; }

# --- preconditions -----------------------------------------------------------

if [[ -n "$(git status --porcelain)" ]]; then
  echo "release.sh: working tree is not clean; commit or stash first" >&2
  git status --short >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/$version" >/dev/null; then
  echo "release.sh: tag $version already exists" >&2
  exit 1
fi
if ! grep -q '^## \[Unreleased\]' CHANGELOG.md; then
  echo "release.sh: CHANGELOG.md has no '## [Unreleased]' section to release" >&2
  exit 1
fi
if grep -q "^## \[$version\]" CHANGELOG.md; then
  echo "release.sh: CHANGELOG.md already has a '## [$version]' section" >&2
  exit 1
fi
# The Unreleased section must carry at least one entry.
if ! awk '
  /^## \[Unreleased\]/ { in_section = 1; next }
  in_section && /^## \[/ { exit }
  in_section && /^- / { found = 1; exit }
  END { exit !found }
' CHANGELOG.md; then
  echo "release.sh: the Unreleased section has no entries" >&2
  exit 1
fi
current="$(sed -n 's/^ *\.version = "\([^"]*\)".*/\1/p' build.zig.zon)"
[[ -n "$current" ]] || { echo "release.sh: could not read .version from build.zig.zon" >&2; exit 1; }
if [[ "$current" == "$version" ]]; then
  echo "release.sh: build.zig.zon is already at $version" >&2
  exit 1
fi

# --- checks ------------------------------------------------------------------

if [[ $skip_checks -eq 0 ]]; then
  step "zig fmt --check"
  if ! zig fmt --check build.zig build src tests/*.zig examples/*/build.zig examples/*/src plugins/*/build.zig plugins/*/src; then
    echo "release.sh: files above are not formatted; run 'zig fmt' on them and commit" >&2
    exit 1
  fi

  step "zig build test"
  zig build test --summary all

  step "example generated trees (go-check)"
  for example in examples/*/; do
    # The Rust examples have no `go-check` step; they are checked below.
    if grep -q 'addRustBindings' "$example/build.zig"; then
      continue
    fi
    if grep -q 'name_prefix = "purego"' "$example/build.zig"; then
      (cd "$example" && zig build go-check purego-go-check --summary all)
    else
      (cd "$example" && zig build go-check --summary all)
    fi
  done
  (cd examples/10-tagged-union && zig build go-check -Dpurego --summary all)

  step "example generated trees (rust-check)"
  for example in examples/*/; do
    if grep -q 'addRustBindings' "$example/build.zig"; then
      (cd "$example" && zig build rust-check abi-check --summary all)
    fi
  done
  if [[ -n "$(git status --porcelain examples)" ]]; then
    echo "release.sh: example trees changed during go-check; regenerate and commit them" >&2
    git status --short examples >&2
    exit 1
  fi

  step "staticcheck -checks U1000 over example Go modules"
  if ! command -v staticcheck >/dev/null; then
    echo "release.sh: staticcheck not found on PATH (go install honnef.co/go/tools/cmd/staticcheck@latest)" >&2
    exit 1
  fi
  while IFS= read -r module; do
    (cd "${module%/go.mod}" && staticcheck -checks U1000 ./...)
  done < <(find examples -maxdepth 4 -name go.mod -print | sort)
fi

# --- bump --------------------------------------------------------------------

today="$(date +%Y-%m-%d)"
step "bump $current -> $version ($today)"

# Portable in-place edit: BSD sed on macOS needs an explicit suffix argument.
edit() { sed -i.release-bak "$1" "$2" && rm -f "$2.release-bak"; }

edit "s/^## \[Unreleased\]\$/## [$version] - $today/" CHANGELOG.md
edit "s/^\( *\.version = \)\"$current\"/\1\"$version\"/" build.zig.zon
# Not every one of these files carries a fetch line at any given time, so a
# file without one is skipped; only having none at all is an error.
bumped_fetch=0
for file in README.md docs/getting-started.md; do
  fetch_ref="$current"
  if ! grep -Fq "github.com/ironpark/zigo#$fetch_ref" "$file"; then
    fetch_ref=main
  fi
  if ! grep -Fq "github.com/ironpark/zigo#$fetch_ref" "$file"; then
    continue
  fi
  edit "s#github.com/ironpark/zigo\#$fetch_ref#github.com/ironpark/zigo\#$version#g" "$file"
  bumped_fetch=1
done
if [[ $bumped_fetch -eq 0 ]]; then
  echo "release.sh: no file has a fetch line for $current or main to update" >&2
  git checkout -- CHANGELOG.md build.zig.zon
  exit 1
fi

# The release notes the workflow will publish must be extractable now.
scripts/extract-changelog-section.sh "$version" >/dev/null

git add CHANGELOG.md build.zig.zon README.md docs/getting-started.md
git --no-pager diff --cached --stat
git commit -q -m "release: $version"
git tag "$version"
echo "committed $(git rev-parse --short HEAD) and tagged $version"

# --- push --------------------------------------------------------------------

if [[ $push -eq 1 ]]; then
  step "push"
  branch="$(git rev-parse --abbrev-ref HEAD)"
  git push origin "$branch"
  git push origin "$version"
  echo "pushed $branch and tag $version; the Release workflow publishes the GitHub release"
else
  branch="$(git rev-parse --abbrev-ref HEAD)"
  printf '\nnot pushed. To publish:\n  git push origin %s && git push origin %s\n' "$branch" "$version"
fi
