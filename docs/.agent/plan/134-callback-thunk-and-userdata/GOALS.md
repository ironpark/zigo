# GOALS

## Problem and the end result from the user's point of view

A Zig callback that takes or returns `bool` fails to compile: the shim declares the Go trampoline with the wire type `u8` and hands its address to a target expecting `bool`. The userdata convention (last `usize` in the callback, the `usize` right after the callback in the function) is undocumented and unenforced; a misplaced userdata either dies with a siteless `error.CallbackRequiresUserdata` or dispatches on the wrong argument at runtime. After this plan, `bool` callbacks work on both backends, the userdata position can be declared per callback type and per function parameter, violations are `ZIGO` diagnostics with a site, and the docs state the contract.

## Measurable goals

- `callback_bool` generator cases (cgo, purego) generate and the shim compiles.
- A callback with userdata first, declared via `.userdata = .first`, generates a thunk and dispatches to the right Go value.
- Missing or mistyped userdata is a validate diagnostic with a function site, no emit-time error.

## Supported scope and non-goals

In scope: bool params/results in callbacks, `userdata_index` in the semantic IR, `.userdata` on callback type entries, `param_meta.<cb>.userdata` naming the function-side token, thunk reordering, diagnostics, docs. Non-goals: `?*anyopaque` userdata, a marker type, changes to the Go dispatcher convention.

## Reference source / commit / license

Own code; base commit 5bc968ca.

## Completion criteria for the whole plan

`zig build test` passes, generator snapshot cases are updated, docs describe the contract.
