# Plugin API feedback review

Reviewed against zigo 0.19.3 and the adjacent gostty working tree (zig/build.zig.zon pins zigo 0.19.2). Review only; no generator or consumer implementation changed.

## 6. Public result helpers: confirmed, with a broader contract needed

src/plugin.zig:160-229 exposes type spelling and a full signature, but no separate parameter/result writer or result metadata. gostty/zig/plugins/must/src/plugin.zig:46-175 renders the signature, splits balanced parentheses, and strips a trailing error using top-level comma splitting. The report is accurate for this external MUSTOPT plugin. zigo's built-in MUST plugin does import emit internals directly (src/gen/plugins/must.zig:10-14); the import restriction does not describe the built-in plugin.

A result writer alone does not remove the parameter-list parser or the need to count results. Prefer a structured public-signature view, or writers for parameters/results with an explicit omit-error policy plus result count. Reuse existing lowering/public spelling so constructors, optional bool results, borrowed references, strings, codepoints, adapters, and package qualification match exactly. Exposing call-argument writing would also avoid consumer duplication for injected parameters, callback userdata, cancellation and flattened parameters.

## 7. Public file paths: confirmed; collision detection is separately necessary

src/gen/emit/emit.zig:269 has a private publicFilePathAlloc helper; common.zig:24 implements the path fallback. gostty's helperPath at zig/plugins/must/src/plugin.zig:197 duplicates it. Emitter.pathAlloc receives allocator, Program and Options, not Context, so merely adding a Context method does not solve the callback ergonomics. Expose a helper callable directly from pathAlloc, or provide a public-file emitter factory accepting a basename.

The generator prepares files without duplicate-path detection (src/gen/generator.zig:175-191), then writes them in sequence (line 171). Thus the reported overwrite is consistent with current implementation; the historical debug session itself was not replayed. Add normalized output-path collision checks before any output mutation, identifying the conflicting plugin/package. Include root '.', subpackages, duplicate plugin files, and built-in/plugin collisions in tests. Path API and duplicate-output rejection should be implemented together.

## 8. Multiple diagnostics: confirmed; callback change alone is insufficient

Plugin.validate returns at most one diagnostic (src/plugin.zig:280). Both findIssueWithPlugins and pluginIssue return at the first issue (src/gen/validate/validate.zig:162-181); CLI paths likewise consume one issue. gostty's STRINGER validator checks omitted names (003) before unsupported flag types (004), confirming why the second issue is masked.

Introduce a collector or a new validateAll callback with a compatibility bridge for validate. Aggregate and render at the driver/CLI layer too. Keep structural core validation ahead of plugin validation; skip a plugin's semantic validator when its options cannot be parsed. A slice-only signature replacement breaks existing plugin source and does not itself make unsafe downstream checks independent. Define ordering and ownership of diagnostic data.

## 9. Field hooks: handle accessors already supported

HandleField.extend captures FunctionOptions; reflection copies ext onto both synthesized getter/setter functions (src/reflect/walk.zig:278-310). The ordinary method_hook runs after those methods (src/gen/emit/public.zig:765). docs/bindings-handles.md:266 documents this and walk.zig:5035 tests it. This shipped in 0.19.0 and is already in gostty's pinned dependency.

For getter/setter wrappers, no field_hook is needed: use HandleField.extend and context.functionOptions; function.origin.field_access identifies path and setter. This does not imply a hook exists next to each Go value-struct field, or for independently customizing getter and setter attachment options. The user's referenced item 1 was not supplied, so any additional field-declaration requirement remains outside this review.

## C. Existing features and gostty adoption

The gostty build has no abi_base and commits zig/zigo/semantic.json, matching the relative git-show baseline path in zigo/build.zig:640. Adding abi_base is directly applicable. The standard step is `zig build abi-check`, not `go-abi-check` (build.zig:222); go-verify depends on it when configured. HEAD compares generated output to the current commit: once a breaking semantic change is committed, HEAD moves with it. Use a release tag or PR base SHA for persistent compatibility checks. This compares semantic/lowered ABI contracts, not arbitrary plugin-generated Go behavior or native binary exports.

searchAll has no cancellation flag and loops until completion (gostty/zig/src/search.zig:110); cancellation requires adding a native atomic flag parameter and polling it, not only a binding option. It changes the signature and needs ABI review.

TaggedUnion is already used for Attribute and ScrollViewport (gostty/zig/src/bindings.zig:776,786). StreamEvent is still an enum with separate payload accessors, so the specific Stream/OSC redesign is a potential adoption area, not evidence of global non-use. Payload ownership, event lifetime and accessor compatibility must be designed before replacing those interfaces.

## D. satisfies value/pointer form: confirmed

plugins/satisfies/src/plugin.zig:20 offers only interfaces; line 43 emits (*T)(nil) unconditionally. gostty's stringer explicitly asserts the value form at zig/plugins/stringer/src/plugin.zig:76. Go distinguishes T's method set from *T's, and fmt uses the dynamic argument's supported formatting interfaces. A pointer assertion does not prove that passing a value uses String(). Sources: https://go.dev/ref/spec#Method_sets and https://pkg.go.dev/fmt.

Add form = .pointer | .value, retaining .pointer as default. Value assertions must work for enums as well as structs; T{} is not universal, whereas a typed zero expression such as *new(T) works across these supported kinds. Interface conformance does not verify the exact text or guarantee Stringer precedence over fmt.Formatter; retain formatting tests.

## Suggested order

1. Public file-path API plus duplicate output rejection: prevent silent file replacement.
2. Result/signature and forwarding helpers: remove consumer parsing and spelling duplication.
3. satisfies form: small additive option with focused Go compile tests.
4. Multi-diagnostic driver/API: useful, but requires coordinated compatibility and validation changes.

Enable gostty ABI checks independently. Treat Cancel and Stream/OSC union adoption as consumer API changes. No new accessor field_hook is justified by the supplied getter/setter use case.

## Implementation follow-up

Plan 173 implements the path helper with pre-write normalized collision diagnostics (ZIGO059), Context parameter/result/argument writers, additive validateAll aggregation and satisfies.form. Legacy validate and default pointer assertions remain supported. External-module fixtures cover split packages, constructor/optional results, callbacks, flattening and cancellation; Go compilation verifies value assertions and rejects pointer-only implementations. See docs/plugins.md for the current API. gostty and its ABI baseline were not modified.
