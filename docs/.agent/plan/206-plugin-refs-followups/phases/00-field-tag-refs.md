---
perf_phase: false
status: in-progress
---
> DONE-WHEN: `.use(P, .{ .target = api.typeRef("X") })` on a value field and on an enum tag round-trips and resolves in the golden; the wrong-kind case fails to compile.
> NEXT: none

# Field and tag use with authoring refs

## Planned Work

- Move the authoring-facing `HandleField`, `ValueField`, `EnumField` structs (and their `use`/`extend`) into `src/author.zig`, leaving `declare.zig` with the plain normalized structs `normalize.zig` produces. Re-export from `src/root.zig` under the same names so `bindings.zig` files do not change.
- Route their `use` through `authoredOptions(P, .field / .enum_tag)` with the same root check as `Entry.use` (the owning type's root is known from the enclosing `api.value(...)`/`api.enumeration(...)` call; if the field literal is built before that call, defer the root check to `normalize` and report it there with a compile error).
- Update `normalize.zig`, `reflect/walk.zig` if any type names changed, and the REFS test plugin to add a field-level and a tag-level ref option; extend golden `plugin_refs` and add `tests/binding_errors/plugin_ref_field_kind`.
- Docs: `binding-api.md` `use` location table says all sites take authoring refs; `api-reference.md` removes the "path string on fields/tags" note; CHANGELOG entry.

## Done When

- `.use(P, .{ .target = api.typeRef("X") })` on a value field and on an enum tag round-trips and resolves in the golden; the wrong-kind case fails to compile.
- All existing goldens and examples byte-identical.
