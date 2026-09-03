# GOALS

## Problem and the end result from the user's point of view

`pub fn viewportIsBottom(self: Screen) bool` is rejected ("no C representation" / ZIGO003) because the receiver is the struct by value, although `Screen` is a registered opaque handle and the shim already holds `*Screen`. Downstream projects write one-line wrappers for every such function. End result: when a parameter (receiver or otherwise) is a registered opaque type by value, the C signature takes the handle pointer and the shim passes `self.*` / `arg.*`; Go sees an ordinary method or `*T` parameter. Const-ness follows: the pointer is `*const T`.

## Measurable goals

- Receiver by value becomes a Go method with the same lifecycle guard as pointer receivers; non-receiver by-value opaque parameters take `*T` in Go and are dereferenced in the shim; the copy semantics are documented (mutations inside the callee do not reach the handle).
- A by-value opaque return stays rejected with the existing boxing rule (`init` boxing is the constructor path); a diagnostic hint points at `.constructs`/boxing.
- Reflection unit tests, a generator case, example (03 opaque) Go tests on both backends, docs `bindings.md` "Opaque handle" note, CHANGELOG `### Added`.

## Supported scope and non-goals

In scope: `walk.zig` receiver detection (`receiverNameAt` requires a single pointer today) and parameter typing, `validate.zig`, `emit.zig` shim argument writing, docs.
Non-goals: by-value opaque returns, tagged unions by value (own rules), value copies of large structs by hidden pointer in Go (Go always holds the handle).

## Reference source / commit / license

Current main; plan 74 receiver rules; `walk.zig` `receiverNameAt`.

## Completion criteria for the whole plan

Phase done; verification loop green; tree clean.
