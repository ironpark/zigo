---
completed_at: "2026-09-13T19:35:29Z"
depends_on:
- "201-api-consistency-refactor#1"
perf_phase: false
status: done
---
> DONE-WHEN: `grep -rn "api.in(\|\.members(\|\.named(\|\.documented(\|enumType\|taggedUnion\|api.val(" examples src tests docs` returns nothing.
> NEXT: none

# DSL naming and single spellings

## Planned Work

- Rename scope constructors to `handle / value / materialized / enumeration / union / callback` in `src/author.zig`.
- Remove `Scope.in`, `Entry.members`, `Entry.named`, `Entry.documented`; keep `Entry.with` and `.context()` with `.members(entries)` (renamed from `Context.define`) and `.select(selector)`.
- Remove `.root` from `zigo.define` options; `zigo.scope(library)` is the single root source (define takes the scope or the scope is recorded in entries).
- Make helper forms the only public spelling: remove `Param.contract` and `Returns.lifetime` literal fields from `author` types (keep them in `declare`); `zigo.result.borrowed()` needs no enum payload.
- Unify `on_failure` naming with `declare.on_callback_failure`; unify `Returns.lifetime` vs `ownership/release`; rename `Discovery`/`Discover` to one name.
- `features.implements` takes only `.kinds`; drop `.kind`.
- Merge `CallbackOptions` contract fields and `CallbackContract` into one struct with documented precedence in code, not prose.
- Replace `session.children[].plural` + `.name` with a single `accessor` option.
- Turn `features.*` into real `plugin.Plugin` values (register TEXT as a plugin or move `.text` to a `TypeOptions` field) so `Entry.use` takes one type.
- Update `docs/reference/binding-api.md`, `docs/authoring/*`, all example `bindings.zig`, and tests.

## Done When

- `grep -rn "api.in(\|\.members(\|\.named(\|\.documented(\|enumType\|taggedUnion\|api.val(" examples src tests docs` returns nothing.
- All example verify steps, `zig build test` pass; goldens change only where names changed.
