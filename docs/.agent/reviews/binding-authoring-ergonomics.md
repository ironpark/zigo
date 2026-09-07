# Binding authoring ergonomics review

Reviewed at `c485f8ac`. This is an assessment, not an implementation proposal approved for execution.
The typed declaration tree is useful, but the migrated examples retain much of the old metadata and flat organization.

## 1. Remove redundant metadata before expanding the API

Across the 13 example binding files, 126 parameter literals contain only `index` and `go_name`.
This is a count of name-only annotations, not proof that all 126 can be removed: deliberate public-name overrides or stable API spelling must remain.

Verified examples: `banner(w, width)` and `tee(r, w)` in `examples/11-io-streams/src/root.zig:148` and `:156`
repeat those exact names in `src/bindings.zig:36` and `:37`. Both declarations can be expressed using the current
`api.function(name, .{})` API when the configured source-name scan is present.

Remove only annotations equal to the source-derived name, keeping semantic, lifetime and naming overrides.
Use named local scopes and actual type members in large examples. `07-event-queue` still repeats
`api.in("EventQueue")` throughout a flat list. `04-callback` separately repeats the same four exports for
FloatBuffer and IntBuffer; the existing explicit `.functions(.{ .names = ... })` selector can share that allowlist.

Verification for a future cleanup: compare generated public signatures, C symbols, runtime behavior and ABI.
The semantic `name_source` field will intentionally change from sidecar to source; do not demand byte identity there.

## 2. Add typed constructors for parameter and result contracts

`11-io-streams:21` expresses an output slice through params → contract → buffer → output → written.
`12-materialized:17` and `:18` repeat returns → lifetime → owned → release with the same release function.

Illustrative proposed syntax, not currently supported:

```zig
.params = &.{zigo.param.output(1, .result)},
.returns = zigo.result.releasedBy(api.ref("release")),
```

These helpers should return the existing Param and Returns structures. They must not create a second
normalization path or restore incremental lifetime shortcuts that retain stale release metadata.
A result helper constructs a complete result contract; passing it to `.with(.{ .returns = ... })`
keeps today's whole-contract replacement semantics.

A shared typed `const owned_result: zigo.Returns = ...` already removes duplication without any new API.
Favor a few frequent contract constructors over a general-purpose builder language.

## 3. Make type composition direct and consistently demonstrated

`11-io-streams:14` chains representation registration, a plugin and `.with(.{ .members = ... })`,
then repeats the source type name inside every function. Local `const document = api.in("Document")`
works today. A small proposed `.members(entries)` helper would remove the common with/members wrapper.

A larger alternative is a type-bound scope that can both register its representation and select members,
but this needs a deliberate distinction between source container and Go receiver. Root-level functions
attached as members must remain expressible. Avoid introducing this abstraction merely to save `.in()`.

Existing simple member sets should use the already implemented explicit name selector, not public discovery:
new Zig exports must not silently widen the binding API.

## 4. Make contextual roles explicit about their source

`07-event-queue:25` repeats Stream, EventQueue and `.parent = .receiver` for newStream.
The normalizer currently consults the member parent for `.role = .auto`, but explicit `.constructor`
uses only its own receiver field and requires it when `.parent = .receiver`.

In a future API, a child constructor could explicitly choose the enclosing member owner as its receiver,
while keeping the child's constructed type separate. Explicit overrides should be checked against member
ownership, and a child constructor with no available receiver must still fail.

Prefer a visible contextual selector/helper over silently changing the meaning of null receiver: a static
constructor nested under a type is a legitimate case and must remain distinguishable.

## 5. Unify callback annotation conventions

`04-callback:24` uses callback type params `&.{ .{}, .{ .semantic = .utf8_string } }`, while function
params in the same file use sparse original Zig indices. Callback type positions currently refer to the
logical signature after userdata removal and pointer/length grouping. This is a substantial learning cost.

A future callback Param should also select an original native argument index. For a pointer/length pair,
annotate the pointer position; reject independent annotation of the hidden length/token positions and
normalize the pair once. Keep type-level defaults and per-call overrides distinct.

Also align `CallbackOptions.on_callback_failure` and `CallbackContract.on_failure`.
Name-based function selectors would require a larger source-AST/normalization pipeline change; comptime
reflection cannot simply supply parameter names. Do not present that as a small helper addition.

## 6. Fix the examples' layout independently of API design

The longest lines in `07-event-queue` and `08-telemetry-hub` are 319 and 351 characters respectively.
The package literal at `07-event-queue:102` and grouped parameter lists are especially difficult to scan.
`zig fmt` succeeding does not establish readable grouping: trailing commas and source layout determine
whether nested collections stay on one line.

Use one declaration or contract item per line for nontrivial lists, extract package/type groups into
named constants, and choose each example's presentation around the feature it demonstrates.
Keep at least one explicit full-schema example for reference; make normal examples idiomatic.

## Recommended order

1. Clean existing examples with source-derived names, local scopes, shared constants and explicit selectors.
2. Add small Param/Returns constructors and a members convenience method, preserving one typed schema.
3. Unify callback argument addressing and define contextual receiver semantics.
4. Consider a type-bound scope only if the resulting examples still demonstrate substantial repetition.

No executable changes were made. Evidence was checked against the binding files, source signatures,
`src/author.zig` and `src/normalize.zig`; runtime tests were not required for this assessment.
