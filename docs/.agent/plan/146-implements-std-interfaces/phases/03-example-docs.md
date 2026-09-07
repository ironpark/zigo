---
depends_on:
- "146-implements-std-interfaces#2"
perf_phase: false
status: planned
---
> DONE-WHEN: Example 11 tests pass on cgo and purego; other examples regenerate with no git diff;
> NEXT: none

# Example 11, docs, changelog

## Planned Work

- `examples/11-io-streams`: `Document.append` gets `.implements = .writer`,
  `Document.dump` `.writer_to`, `Document.load` `.reader_from`; add
  `Document.readInto(dst: []u8) !usize` for `.reader` (returns 0 at end). Regenerate
  `go/` and `go-purego/`.
- Go tests (cgo and purego): `fmt.Fprintf(doc, ...)`, `io.Copy(doc, strings.NewReader)`,
  `doc.WriteTo(&buf)` returning `buf.Len()`, `io.ReadAll(doc)` ending with `io.EOF`,
  a closed handle returning `*HandleError` through `Write`, and compile-time assertions
  `var _ io.Writer = (*streams.Document)(nil)` etc.
- Docs: new section "handle이 io 인터페이스를 구현하기" in `docs/bindings-streams.md`
  (both directions side by side with stream accessors); a pointer from
  `docs/bindings-handles.md`; cheatsheet row; `docs/limitations.md` rows for
  `fmt.Stringer` and non-`io` interfaces; example README; `CHANGELOG.md` Unreleased.

## Done When

- Example 11 tests pass on cgo and purego; other examples regenerate with no git diff;
  `zig fmt --check` and `gofmt -l` clean; docs cross-links resolve.
