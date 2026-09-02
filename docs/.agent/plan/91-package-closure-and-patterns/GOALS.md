# GOALS

## Problem and the end result from the user's point of view

Splitting a sub-package today means enumerating every type and function; a missed type stays in the root package. The end result: a `.packages` entry can list `.types` with a trailing `*` prefix pattern (`"Key*"`), and `.closure = true` adds every registered type reachable from the listed functions and types (parameter, return, payload, callback signature, and constructs/destroys targets) that is not explicitly assigned elsewhere. ZIGO032 still guards cycles.

## Measurable goals

- Prefix patterns in `.types` and `.namespaces`; a pattern matching nothing is a diagnostic.
- `.closure = true` transitive inclusion with deterministic precedence: explicit assignment in another package wins; a type reachable from two closure packages is a new diagnostic naming both.
- The generated package listing (`planr`-style report is out of scope) is reflected in semantic.json as today, so `abi-diff` sees moves.
- Tests in `walk.zig`/`validate.zig`, generator case `sub_packages` extension, example 11 or whichever uses `.packages`, docs `bindings.md` "공개 Go 하위 패키지", CHANGELOG.

## Supported scope and non-goals

In scope: package assignment resolution in `walk.zig` (or wherever `.packages` is resolved), validation, docs.
Non-goals: regex patterns; automatic package creation.

## Reference source / commit / license

Current main; plan 83 (go-sub-packages) and ZIGO031/032.

## Completion criteria for the whole plan

Phase done; verification loop green; docs and CHANGELOG updated; tree clean.
