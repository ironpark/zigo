# GOALS

## Problem and the end result from the user's point of view

ABI checking is currently exposed by every binding graph but misses changes to exported C symbols, document identity, and constructor metadata. Make the check an explicit compatibility-policy opt-in and make enabled checks trustworthy.

## Measurable goals

- Changing a function's exported symbol, package, prefix, IR version, or constructor mapping produces a breaking report.
- A consumer that omits ABI configuration gets no Git baseline command and no ABI check handle.
- Consumers that opt in retain a build step that fails on breaking changes.

## Supported scope and non-goals

Scope covers semantic contract comparison, `addGoBindings` ABI configuration, examples, tests, and user/design documentation. It does not promise compatibility across separate prebuilt dynamic-library distributions or add release version negotiation.

## Reference source / commit / license

Implementation follows this repository's existing Zig 0.16 build graph and semantic IR; no external source is copied.

## Completion criteria for the whole plan

Both phases are done, opt-in and default build graphs compile, focused ABI tests pass, all Zig and Go/example checks pass, and documentation consistently describes the feature as optional contract checking.
