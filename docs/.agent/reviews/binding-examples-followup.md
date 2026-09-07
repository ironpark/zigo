# Polished binding examples: follow-up review

Reviewed at 9f43394d. All 13 example binding files were read. This is a review of the resulting authoring experience; executable files and generated output were not changed.

## Overall finding

No new functional regression was found in the inspected examples. The shared selectors in callback/pipeline, local scopes, and the shared owned result in materialized make the examples substantially easier to follow. The next useful changes concern hidden identity and consistent composition, rather than another broad DSL redesign.

## 1. Preserve parameter identity independently of its name

Priority: highest architectural improvement, not a current broken example.

Evidence:
- examples/04-callback/src/bindings.zig:59 retains a name-only ctx annotation beside userdata = 0.
- The same file at :51 and telemetry-hub at :26 retain .named("cancel").
- src/normalize.zig:303 converts the userdata index into a string using paramName; :308 and :316 fix cancellation/userdata names before source enrichment.
- src/reflect/names.zig:600 enriches only fallback names; these normalized explicit names are therefore not renamed from AST.

A focused compile-time probe verified that omitting the explicit names produces a consistent p0 name and p0 link. The link still works, but the source-derived spelling cannot be recovered under the current model. The extra names preserve generated parameter spelling, not callback correctness.

Recommendation: retain a stable parameter index/identity through normalization and name enrichment, resolving any string reference only after final names are assigned. This is an internal pipeline change with source-name, injected-argument and generated-output regressions to verify, not a small helper addition. Once implemented, the exceptions requiring source-equivalent names can disappear.

## 2. Remove redundant method receiver annotations inside members

Priority: small example-only cleanup.

examples/07-event-queue/src/bindings.zig:103 and :107 explicitly repeat Ticker as the method receiver although both functions are inside Ticker.members and their first arguments are *Ticker and *const Ticker (root.zig:558 and :564).

The normalizer already supplies the enclosing receiver for these signatures (src/normalize.zig:191). A compile-time probe confirmed both cases. These declarations can be:

    api.function("tickerAdvance", .{}).named("advance"),
    api.function("tickerElapsed", .{}).named("elapsed"),

Keep explicit constructor/destructor roles for newTicker/freeTicker: those establish lifecycle pairing. Explicit-method syntax can remain demonstrated by the root-level cursorStyleBlinks example in type-relations.

## 3. Put each handle's lifecycle in one visible group

Priority: small example-only cleanup.

examples/07-event-queue/src/bindings.zig registers Stream.members with capacity, but leaves freeStream in the root declaration list. Ticker already places its root-defined destructor inside its own members.

Recommendation: move the freeStream declaration into Stream.members while retaining its explicit destructor role. Keep newStream under EventQueue because EventQueue is its receiver. Grouping concerns receiver ownership, not the source namespace or returned type; this distinction should be visible in an explanatory comment.

The existing explicit receiver matches Stream, so this uses the current schema. Any later implementation should check generated ordering and ABI.

## 4. Make interface declarations visually consistent

Priority: local readability cleanup.

examples/11-io-streams/src/bindings.zig:17 chains representation, the satisfies plugin, and a member list in one expression. Lines :20-30 repeatedly spell zigo.features.implements and vary the formatting of equally simple params lists.

Recommendation: extract a named Document binding, as event-queue already does; give the built-in feature a local name such as io_adapter; consistently inline one short contract and expand multi-contract options. Keep satisfies and implements distinct: satisfies checks an interface, while implements emits the adapter methods.

No new feature-specific fluent API is necessary to make this example readable.

## 5. Consider named helper options only if extending their contracts

Priority: lower, API design suggestion.

The difference between cancel(3, null) and stream(1, 4096) requires knowing the second positional argument. The current API is small enough to learn, but adding further optional arguments would make it harder.

If these helpers grow, prefer named options such as cancel(3, .{}) and stream(1, .{ .buffer = 4096 }) over additional positional arguments. These spellings are proposals and are not currently implemented. Keep index first and preserve complete-contract replacement semantics.

## Validation and limits

- Fresh zig build go-check abi-check passed for 04-callback, 07-event-queue, 11-io-streams and 12-materialized.
- A temporary compile-time probe confirmed contextual Ticker receiver inference and p0 fallback linkage for unnamed userdata/cancellation parameters.
- All 13 binding files were read; source signatures and the relevant normalization/name-enrichment code were inspected.
- The full runtime suite was not rerun for this review. The preceding implementation's 765-test result is historical evidence, not a new test run here.
- Only the review and plan artifacts were changed.
