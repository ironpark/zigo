---
completed_at: "2026-09-10T04:08:31Z"
perf_phase: false
status: done
---
> DONE-WHEN: `grep -rn "exportedNameAlloc" src build build.zig plugins tests` finds
> NEXT: none

# Split the exported-name rule into a type rule and a function rule

## Planned Work

- Replace `VTable.exportedNameAlloc` with `exportedTypeNameAlloc` and
  `exportedFunctionNameAlloc`, and give `Target` a forwarding method for each.
- Point `Target.publicFunctionNameAlloc` at the function rule, including the
  constructor branch that spells a `.name` override.
- Answer both with `naming.pascalAlloc` in `src/gen/targets/go.zig`, so Go's
  behaviour is unchanged by construction.
- Decide `unexportedNameAlloc`, which has no caller today: keep it if the Rust
  target has a use for it in a later phase, otherwise say so in the phase
  outcome rather than leaving unexplained surface.
- Add `naming.pascalWithInitialismsAlloc(allocator, input, table)` and redefine
  `pascalAlloc` and `camelAlloc` over it with the Go table, so the initialism
  set becomes a parameter without moving a call site.
- Extend the `targets.zig` tests to assert both rules exist and that Go answers
  them identically.

## Done When

- `grep -rn "exportedNameAlloc" src build build.zig plugins tests` finds
  nothing; `exportedTypeNameAlloc` and `exportedFunctionNameAlloc` both exist.
- `grep -c "pascalAlloc" src/gen/emit` is unchanged from before the phase: no
  emitter call site moved.
- `zig build test --summary all` green at the repository root.
- `scripts/update-generator-cases.sh` then
  `git status --short tests/generator_cases` is empty.
- Each of the thirteen examples passes
  `zig build test go-check go-lib abi-check go-coverage` and
  `(cd go && go test ./...)`, and `git status --short examples` is empty.
- `zig fmt --check src build build.zig` clean.
- Committed.
