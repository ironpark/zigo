# SCOPE

Modify the semantic-to-Go emitter, generator CLI and build integration, their Zig and Go regression tests, generated example artifacts, and public wiki/README documentation. Preserve compatibility for existing generated convenience methods and build handles.

# CONTEXT

## Current implementation and bottlenecks

`renderPublic` emits `.ptr` directly for receivers and opaque parameters. `zigoPointer` exists only when tagged-union projections are present. Projection helpers panic with string values and do not expose checked variants. `GoBindings` returns update/check/optional ABI handles but each project manually registers named steps. The CLI supports generate/check/abi-diff but no report or doctor command. Source documentation is forwarded when present, but generated types, lifecycle methods, accessors, errors, and undocumented functions do not consistently receive GoDoc.

## Target structure and invariants

All public wrapper calls acquire validated pointers through one generated helper and never enter cgo with a nil handle. Typed errors carry the operation and category; convenience methods panic with those error values, while checked projection methods return them. Diagnostic commands remain read-only. Build-step registration is explicit and reusable. Generated comments begin with the exported identifier and accurately state ownership, lifetime, mismatch, and error behavior.
