---
completed_at: "2026-08-29T22:37:53Z"
depends_on:
- "01-zigo-go-bindings#2"
perf_phase: false
status: done
---
> DONE-WHEN: Running `zigo-gen` on the scalar fixture writes a shim, a header, `internal/raw` and
> NEXT: none

# Generator emitting scalar bindings

## Planned Work

- Implement `zigo-gen` argument handling: IR inputs, output directory, package name and
  symbol prefix.
- Implement `validate.zig` and `lower.zig` for the scalar subset, including the
  `bool` to `uint8_t` mapping.
- Implement `naming.zig`: snake_case symbol construction, PascalCase Go identifiers, and
  a table-driven initialism fixer covering ID, URL and UTF8.
- Implement the four emitters behind the shared `Emitter` interface: Zig shim, C header,
  Go raw package and Go public package.
- Golden tests for each emitter driven purely by IR fixtures, with no Zig project.

## Done When

- Running `zigo-gen` on the scalar fixture writes a shim, a header, `internal/raw` and
  the public package matching the goldens.
- All three of the shim, header and Go raw package agree on the same lowered signature.
- Generator tests run without compiling any example project.
