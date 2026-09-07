---
depends_on:
- "146-implements-std-interfaces#1"
perf_phase: false
status: planned
---
> DONE-WHEN: Goldens are generated and reviewed; both expected trees compile with
> NEXT: none

# Emission and golden cases

## Planned Work

- New `src/gen/emit/implements.zig` with `renderImplementsWrapper`, called from
  `public.zig` after `renderIteratorWrapper`; doc comment says which interface it
  satisfies and which method it calls.
- `zigoCountingWriter`/`zigoCountingReader` in `public_runtime.zig`, gated by new
  `common.programHasCountingWriter/Reader` predicates.
- Generator cases `implements_std` and `implements_std_purego` covering all four keys,
  both result shapes for `.writer_to`/`.writer`, and an error-set method; `go vet`
  the expected trees as the case runner already does.
- Let `docs.zig` mention the implemented interfaces on the handle doc if it lists methods.

## Done When

- Goldens are generated and reviewed; both expected trees compile with
  `go build ./...` and `go vet`; all prior goldens unchanged.
