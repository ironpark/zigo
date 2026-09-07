# Example adoption audit

Reviewed at 68107d98. All 13 bindings and relevant example READMEs were inspected.
This review distinguishes useful adoption gaps from optional APIs that do not need to appear everywhere.

## 1. Context adoption is incomplete

Four examples currently use Context, all for handles. Five other examples retain separate source scopes and member-bearing type declarations:

| Example | Remaining separate scopes | Recommendation |
|---|---|---|
| 03-opaque | Context, ContextView | Can migrate; reasonable to retain as the explicit Entry.members teaching baseline |
| 05-pipeline | Pipeline, IntBatch, FloatBatch | High priority: matches the generic-buffer pattern already simplified in 04 |
| 08-telemetry-hub | TelemetryHub | Use Context for the four overrides; preserve public discovery |
| 09-type-relations | Counter, Accumulator, DeccolmMode | Show handle and enum Contexts; keep plain text/unicode namespace scopes |
| 10-tagged-union | Child, Value, Signal, Palette | Show tagged-union Contexts and preserved representation/field options |

Relevant lines:
- 05-pipeline/src/bindings.zig:5, :31, :38.
- 08-telemetry-hub/src/bindings.zig:5 and :11.
- 09-type-relations/src/bindings.zig:28.
- 10-tagged-union/src/bindings.zig:21 and :33.

The materialized Leaf/Probe and value RGB/Point registrations have no members to group. Adding Context solely to register them would not improve the examples.

## 2. The interface example does not yet use context-owned TypeRef

05-pipeline already shares a selector, but still writes the generic aliases separately in scope, registration and interface type references.

With Context:

    const IntBatch = api.handle("IntBatch", .{}).context();
    const FloatBatch = api.handle("FloatBatch", .{}).context();

    // declarations
    IntBatch.select(batch_members),
    FloatBatch.select(batch_members),

    // the Batch interface
    .types = &.{ IntBatch.typeRef(), FloatBatch.typeRef() },

This is a more complete demonstration of the new context than merely changing members to define.

## 3. select() is underused for uniform member lists

11-io-streams/src/bindings.zig:34-43 uses seven option-free function calls for Sink and Source. These can be:

    Sink.select(.{ .names = &.{ "create", "writer", "count", "deinit" } }),
    Source.select(.{ .names = &.{ "create", "reader", "deinit" } }),

10-tagged-union similarly lists ten option-free Value members and eight Signal members. Context.select can preserve the existing explicit order and snapshot/projection settings while reducing repeated calls.

Keep define where a member has a callback, result, role or plugin override. Do not split a heterogeneous list into many artificial selectors just to use the API. One-member declarations do not necessarily benefit.

## 4. Some contextual ownership is still duplicated or split

07-event-queue/src/bindings.zig:106 and :110 repeat explicit Ticker method roles within Ticker.define.
Its two methods already infer the receiver; retaining only the Go name overrides produces exactly the same normalized binding.

Stream is declared at :125, but its explicit freeStream destructor stays at :164. Moving that root-defined function into Stream.define would demonstrate that source location and receiver membership are independent. Keep newStream under EventQueue, whose receiver constructs it.

Do not remove constructor/destructor role contracts that establish lifecycle pairing. Keep the explicit root-method example in 09-type-relations as a teaching example.

The destructor move can reorder functions and would need generated-output/ABI verification if implemented. It was not included in the exact-order equality probes below.

## 5. Example discovery and README explanations lag the API

docs/examples.md indexes runtime features but has no authoring-feature guide. A short mapping would make the completed work discoverable:

| Authoring feature | Example to point to |
|---|---|
| Complete literal schema / basic members | 03-opaque; 11 fillCodepoints for full buffer schema |
| Generic Context, shared selector, TypeRef | 04-callback and migrated 05-pipeline |
| Sparse callback native indices and on_failure | 04-callback |
| Contextual child constructor and packages | 07-event-queue |
| Discovery with sparse overrides | 08-telemetry-hub |
| Enum / tagged-union Context | Migrated 09 / 10 |
| Plugin + Context + per-function feature | 11-io-streams |
| Shared releasedBy result contract | 12-materialized |

11-io-streams/README.md:63 still shows the earlier standalone Entry plugin snippet rather than its actual Context composition. It remains valid, but does not teach the new combination.
12-materialized/README.md:30 describes literal owned lifetime while the actual binding uses the shared owned_tree/releasedBy contract. Explaining that constant and its release reference would better match the file.

## Already sufficiently used or intentionally omitted

- output/stream/callback/cancel/flatten helpers are used where matching contracts exist.
- owned/releasedBy/borrowed result helpers, sparse callback params, on_failure, .member constructors, type refs, plugins and package grouping are already demonstrated.
- The one remaining full buffer contract literal is explicitly labeled as a schema example in 11. Keep it.
- input duplicates the default input contract; adding it everywhere would restore redundant metadata.
- inout requires a real read/write-buffer use case. Do not change an output-only API merely to demonstrate the helper.
- named(null), with and replacePlugin are configuration-composition tools already covered by docs/tests. They need a shared-configuration use case, not artificial example invocations.
- Recursive/public-prefix discovery and package defaults alter export/inference policy. Their absence is not grounds to replace explicit allowlists or change existing API semantics.
- The ctx/cancel names still needed by normalized string links are an implementation constraint, not missed helper adoption.
- Minimal free-function examples 00/01/02/06 do not need type Contexts.

## Verification

A temporary Zig harness compiled seven candidate variants against the current public API, comparing the entire before/after normalized binding with comptime expectEqualDeep:

1. Context migration of 03-opaque.
2. Context migration and context TypeRefs in 05-pipeline.
3. Context migration preserving discovery in 08-telemetry-hub.
4. Handle/enum Context migration in 09-type-relations.
5. Handle/union Context migration and Value/Signal selectors in 10-tagged-union.
6. Sink/Source selectors in 11-io-streams.
7. Removal of redundant Ticker method roles in 07-event-queue.

All seven passed with exact declaration order and metadata equality. Production examples were not modified.
No new full runtime or generated-tree run was performed for this review.

## Recommended next scope

Migrate 05/08/09/10, apply the simple selectors and redundant-role cleanup, group Stream's destructor, and update the authoring-feature guide and affected READMEs. Keep 03 as a documented lower-level baseline and preserve the explicit buffer schema example.
