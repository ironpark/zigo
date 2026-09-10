---
completed_at: "2026-09-10T05:53:37Z"
depends_on:
- "190-rust-handles-and-buffers#0"
perf_phase: false
status: done
---
> DONE-WHEN: `grep -n 'New{s}' src/gen/targets.zig` finds nothing; the literal lives in
> NEXT: none

# Move the constructor-name rule behind the target

## Planned Work

- Add `VTable.constructorNameAlloc(allocator, type_name, declared_name)`.
  Go answers `New<Type>` for an absent declared name and the exported spelling
  of the declared one otherwise -- exactly what
  `Target.publicFunctionNameAlloc` does inline today. Rust answers `new` for an
  absent name and the snake spelling otherwise, because a Rust constructor is
  reached as `Type::new()` and the type is already in the path.
- Rewrite `Target.publicFunctionNameAlloc`'s constructor branch to call it, so
  the `New{s}` literal leaves `targets.zig`.
- Record what `constructorForInit` reads. It matches on
  `function.goOwner()`, which is `FnGo.owner` falling back to
  `SemanticFn.namespace`. The fallback is the Zig container and is neutral in
  substance; only the override is Go-namespaced. Decide during implementation
  whether to leave it, and write the reason either way -- refusing a shape that
  works for a naming-hygiene reason would be the wrong trade.
- Extend the `targets.zig` tests so both targets' answers are pinned, including
  that Go's is byte-identical to the previous inline rule.

## Done When

- `grep -n 'New{s}' src/gen/targets.zig` finds nothing; the literal lives in
  `targets/go.zig`.
- A test asserts Go answers `NewContext` and `Rust` answers `new` for the same
  input, and that a declared name goes through each target's function-name
  rule.
- Generated Go is byte-identical: 77 generator cases clean, thirteen examples
  clean. This phase changes no output at all, which is what makes it verifiable
  on its own.
- Root tests green, `zig fmt --check` clean. Committed.
