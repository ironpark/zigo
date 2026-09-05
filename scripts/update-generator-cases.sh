#!/usr/bin/env bash
# Regenerates the expected tree of every generator case (or the ones named as
# arguments) from the current generator. Review the resulting diff before
# committing: a golden change is a generated-code change.
#
# Usage: scripts/update-generator-cases.sh [case-name...]
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
zig build test -Dtest-filter=__none__ >/dev/null 2>&1 || true
# Several runner builds can sit in the cache; the newest one is the one the
# test step just produced.
# `head` closing the pipe early would trip pipefail, so the status is masked.
runner="$(ls -t $(find .zig-cache/o -maxdepth 2 -name zigo-generator-case -type f) 2>/dev/null | head -1 || true)"
[[ -n "$runner" ]] || { echo "generator case runner not built; run zig build test once" >&2; exit 1; }
cases=("$@")
if [[ ${#cases[@]} -eq 0 ]]; then
  cases=($(ls tests/generator_cases))
fi
for name in "${cases[@]}"; do
  dir="tests/generator_cases/$name"
  [[ -f "$dir/semantic.json" ]] || continue
  actual="$(mktemp -d)"
  mkdir -p "$dir/expected"
  "$runner" "$dir" "$actual" >/dev/null 2>&1 || true
  if [[ -z "$(ls -A "$actual")" ]]; then
    echo "$name: generation produced nothing" >&2
    rm -rf "$actual"
    exit 1
  fi
  rm -rf "$dir/expected"
  cp -R "$actual" "$dir/expected"
  rm -rf "$actual"
done
git status --short tests/generator_cases | awk '{print $2}' | cut -d/ -f3 | sort -u | sed 's/^/updated: /'
