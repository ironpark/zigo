# GOALS

## Problem and the end result from the user's point of view

Large Zig APIs currently repeat every exported function in `zigo.define`. Add an opt-in automatic discovery mode so users declare the module and ABI-relevant types once, while retaining explicit control over exclusions and semantic overrides.

## Measurable goals

- Discover supported public root functions and public methods on registered types using Zig compiler reflection.
- Reduce the telemetry-hub binding declaration from 51 explicit function entries to discovery plus exceptional metadata.
- Enrich discovered declarations with owner-qualified AST parameter names and documentation.
- Preserve the existing `.functions` declaration form without behavior changes.

## Supported scope and non-goals

Support opt-in discovery for public, non-generic functions on a module namespace and registered concrete types. Keep opaque/value representation, generic specializations, UTF-8 semantics, ownership, callback retention, renames, and exclusions explicit. Do not use AST as a type checker, bind private declarations, or embed the ZLS semantic engine.

## Reference source / commit / license

Use the installed Zig 0.16.0 standard library reflection APIs and the repository's ignored `ref/zls` checkout as implementation references only. No reference source is copied into production code.

## Completion criteria for the whole plan

Automatic discovery, qualified AST enrichment, overrides, exclusions, compatibility tests, documentation, and the telemetry-hub migration all pass the root and example verification suites with deterministic generated outputs.
