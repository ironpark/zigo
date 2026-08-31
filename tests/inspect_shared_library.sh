#!/usr/bin/env bash
# Inspects an installed zigo shared library.
#
#   tests/inspect_shared_library.sh <library> [symbol...]
#
# Asserts the platform filename, that no build-cache path is baked into the
# runtime dependencies, that every requested symbol is exported, and that no
# generated `zg_` symbol is left undefined (a cgo trampoline dependency would
# make the library unusable from a CGO_ENABLED=0 process).
set -euo pipefail

library=${1:?usage: inspect_shared_library.sh <library> [symbol...]}
shift || true

if [[ ! -f "$library" ]]; then
  echo "FAIL artifact: $library does not exist"
  exit 1
fi

case "$(uname -s)" in
  Darwin) expected_suffix=.dylib ;;
  Linux) expected_suffix=.so ;;
  *)
    echo "FAIL platform: $(uname -s) is not a supported zigo shared-library platform"
    exit 1
    ;;
esac

if [[ "$library" != *"$expected_suffix" ]]; then
  echo "FAIL artifact: $library does not use the platform suffix $expected_suffix"
  exit 1
fi
echo "PASS artifact: $library"

if [[ "$(uname -s)" == Darwin ]]; then
  # The first otool line echoes the inspected path, which is itself inside zig-out.
  dependencies=$(otool -L "$library" | tail -n +2)
  # Mach-O symbol names carry a leading underscore that ELF names do not.
  defined=$(nm -gU "$library" | awk '{print $NF}' | sed 's/^_//')
  undefined=$(nm -u "$library" | awk '{print $NF}' | sed 's/^_//')
else
  dependencies=$(objdump -p "$library" | grep -E 'NEEDED|RUNPATH|RPATH' || true)
  defined=$(nm -D --defined-only "$library" | awk '{print $NF}')
  undefined=$(nm -D --undefined-only "$library" | awk '{print $NF}')
fi

if grep -qE '\.zig-cache|zig-out' <<<"$dependencies"; then
  echo "FAIL dependencies: a build-cache path is baked into the artifact"
  echo "$dependencies"
  exit 1
fi
echo "PASS dependencies: no build-cache path is baked into the artifact"

if grep -qE '^zg_' <<<"$undefined"; then
  echo "FAIL symbols: generated zg_ symbols are undefined in the artifact"
  grep -E '^zg_' <<<"$undefined"
  exit 1
fi
echo "PASS symbols: no generated zg_ symbol is left undefined"

for symbol in "$@"; do
  if ! grep -qx "$symbol" <<<"$defined"; then
    echo "FAIL symbols: $symbol is not exported"
    exit 1
  fi
  echo "PASS symbols: $symbol is exported"
done
