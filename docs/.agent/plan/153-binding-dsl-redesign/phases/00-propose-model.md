---
completed_at: "2026-09-07T12:14:02Z"
perf_phase: false
status: done
---
> DONE-WHEN: Prioritized redesign recommendations are ready to present with clear separation from existing APIs.
> NEXT: none

# Propose the redesigned model

## Planned Work

- Evaluate declaration ownership, references, contracts, composition and plugin targets.
- Record a coherent recommendation with illustrative API sketches and implementation constraints.

## Done When

- Prioritized redesign recommendations are ready to present with clear separation from existing APIs.

## Recommended redesign

Preserve a typed canonical schema and make the DSL its authoring facade. Without compatibility constraints, redesign both around declaration ownership, stable references and explicit contract variants rather than adding more shortcuts to the current flat records.

1. A declaration tree: package declarations contain actual exported declarations, and handle declarations contain lifecycle/method declarations. A function source can still be a free function while its Go owner is a handle; these are separate concepts. Eliminate package membership lists and redundant methods/function lists from the authoring surface. Normalize deterministically to the existing generator model; do not couple symbol identity to Go package nesting or traversal order.
2. Comptime reference descriptors: scope(library).function(name) resolves the Zig declaration and records root/owner/path; type registrations provide references with registration identity. Source identity and Go naming are separate. Reuse function/type references for release, constructors, interfaces and exclusions. A bare function value cannot uniquely recover its declaration path or alias identity, so retain explicit source descriptors. Do not serialize pointers or comptime-only type values as identities.
3. Contracts as tagged unions: represent free/method/constructor/destructor as exclusive function roles, and owned/borrowed result lifetimes with their corresponding release or parent source. Split buffer, callback and ordinary argument contracts while keeping independent dimensions composable. This structurally eliminates many invalid field combinations; signature- and cross-declaration validation is still needed. Generalizing borrowed ownership beyond the current receiver model requires lifetime/emitter changes, not just new syntax.
4. One predictable composition policy: set/with replaces an explicitly supplied field or complete contract; null clears nullable values. If partial editing is needed, use an explicit patch record with keep/set/clear operations. Avoid implicit recursive merge and special append behavior for ext/covers. use(plugin, options) adds a unique plugin key and rejects duplicates; replacement is explicit. Keep terminal declarations immutable and normalize/validate them in define.
5. Sparse parameter contracts with stable targeting: support explicit Zig parameter indices and source-name descriptors separate from Go rename. Resolve receiver/injected/userdata positions using the same normalizer, so exposed argument order is derived once. Source-name targeting must use source/AST information or an explicit source map; Zig function-type reflection alone does not provide names. Missing, ambiguous or unavailable source names should fail with a clear diagnostic and index alternative.
6. Target-aware extensions: plugins declare supported declaration kinds and per-target option types; attaching JSON to an unsupported function or type is rejected early. Present Go-only built-in conveniences through the same use mechanism as external plugins, while ownership/ABI contracts stay core. Do not imply plugin build modules can be discovered from binding declarations without changing the build architecture.
7. Scope defaults and selectors: permit inheritable non-semantic authoring defaults with explicit local overrides, but do not silently infer ownership or callback retention. Make exact-name vs public/prefix discovery a tagged selector rather than three interacting fields. Require explicit opt-in to selections that grow with upstream public API.
8. define as normalization/validation boundary: resolve references, expand selectors/defaults, detect duplicates and contradictions, produce deterministic typed declarations with provenance for diagnostics. Keep signature/ABI validation in the appropriate later stages. Prove an authoring-only migration by semantic/generated golden equivalence on representative examples. New lifetime semantics need separate behavior tests.

Suggested implementation order: contract variants and composition semantics; validated references and normalization; declaration tree and typed authoring facade; target-aware plugins, sparse parameter helpers and real example conversions. API snippets in the response are illustrative proposals, not implemented APIs.

## Evidence and limits

Grounded in declare.zig (Function/Returns/Param/Type/Package/Binding), dsl.zig (selectors and typed helpers), root.zig (define currently preserves data), plugin.zig (one Options type for every attachment), and reflect/names.zig (source-name enrichment). Reuses the preceding review's verified composition and duplicate-extension observations. No implementation changed and no new runtime behavior was tested for this conceptual proposal.
