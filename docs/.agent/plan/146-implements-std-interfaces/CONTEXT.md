# SCOPE

- `src/declare.zig`: `pub const Implements = enum { writer, reader, writer_to, reader_from }`;
  `Function.implements: ?Implements = null`; `FunctionOptions.implements`.
- `src/dsl.zig`: overlay the new option wherever `FunctionOptions` fields are copied.
- `src/reflect/walk.zig`: copy the key onto the reflected function (next to `.iterator`).
- `src/gen/ir/semantic.zig`: `SemanticFn.implements: ?Implements`, serialized as
  `"implements": "writer"`; parsed back; round-trip test.
- `src/gen/validate/functions.zig`: `implementsIssue` → `ZIGO058`; registered next to
  `iteratorIssue`.
- `src/gen/emit/implements.zig` (new): the wrapper renderer, called from
  `src/gen/emit/public.zig` after the iterator wrapper.
- `src/gen/emit/public_runtime.zig` + `common.zig`: `zigoCountingWriter` /
  `zigoCountingReader` helpers, emitted only when a `void`-result `.writer_to` /
  `.reader_from` exists.
- `src/gen/emit/docs.zig`: the generated package doc lists the interfaces a handle
  implements, if the doc renderer already lists methods per handle.
- `tests/generator_cases/implements_std{,_purego}`; `examples/11-io-streams`; docs; changelog.

# CONTEXT

## Current implementation and bottlenecks

- Every handle method's Go signature ends in `error` (handle check, poison, native error
  mapping) — see `SignatureShape` in `src/gen/emit/public.zig`. A `[]const u8` + `!void`
  method is `Feed(p []byte) error`; `!usize` is `(uint, error)`; an out buffer with
  `.written = .result` is `(uint, error)` (`EventQueue.ExtractSamplesInto`).
- `*std.Io.Writer`/`*std.Io.Reader` parameters are already `io.Writer`/`io.Reader`
  (`Document.Dump(w io.Writer) error`, `Document.Load(r io.Reader) (uint, error)`).
- Stream accessors give `Sink.Write(p []byte) (int, error)` and `Source.Read` with
  `result == 0 → io.EOF`. That convention is reused for `.reader`.
- Public-file imports are derived from qualifiers the body writes
  (`public_std_imports`), so a wrapper that writes `io.EOF` pulls `io` in by itself.
- `.iterator` is the template: declare → reflect → semantic JSON → validate → emit a
  second method after the source method, calling the public method so checks are shared.

## Target structure and invariants

- The wrapper never touches raw/shim code; it calls the public method. Handle checks,
  poisoning, range checks, and error mapping are therefore identical to a direct call.
- Wrapper name is fixed by the interface: `Write`, `Read`, `WriteTo`, `ReadFrom`.
  A receiver may carry each interface once, and the name must not collide with another
  Go method already on that receiver (including a renamed `.name = "Write"`).
- Result adaptation, per interface:
  - `.writer`: `n := len(p)` for `void`; `n := int(r)` for an integer result. If
    `err == nil && n < len(p)` return `io.ErrShortWrite` (the `io.Writer` contract).
  - `.writer_to`: `void` → wrap `w` in `zigoCountingWriter`, return its count as `int64`;
    integer → `int64(r)`.
  - `.reader_from`: mirror of `.writer_to` with `zigoCountingReader`.
  - `.reader`: `n, err := m(p)`; `err != nil → (0, err)`; `n == 0 && len(p) > 0 → io.EOF`;
    else `(int(n), nil)`.
- No `Must` variant for wrappers; `go-coverage` is unaffected because the Zig function
  is still mapped by its own Go method.
- Text-hinted byte slices (`string` in Go) are rejected for `.writer` with a hint to drop
  the hint; the wrapper must not copy on every write.
- Semantic JSON remains backward compatible: the key is optional.
