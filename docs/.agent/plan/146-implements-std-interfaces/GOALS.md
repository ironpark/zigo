# GOALS

## Problem and the end result from the user's point of view

A handle method that takes bytes (`Stream.feed(self, bytes: []const u8) !void`) becomes
`Feed(p []byte) error` in Go. That is one integer short of `io.Writer`, so callers cannot
write `fmt.Fprintf(stream, ...)` or `io.Copy(stream, r)` without a hand-written wrapper in
the binding's Go package. The same gap exists for `*std.Io.Writer`/`*std.Io.Reader`
parameters (`io.WriterTo`/`io.ReaderFrom`) and for out-buffer methods (`io.Reader`).

zigo already makes a handle an `io.Writer`/`io.Reader` when the Zig type *hands out* a
`*std.Io.Writer`/`*std.Io.Reader` (stream accessors, example 11). This plan covers the other
direction: the Zig type has an ordinary method whose shape is one adapter away from a
standard interface, and the binding says so with one key:

```zig
.{ .path = "Stream.feed", .params = &.{.{ .name = "bytes" }}, .implements = .writer },
```

The generator then emits, next to `Feed`, a `Write(p []byte) (int, error)` that calls
`Feed` and adapts the result. The source method stays, so nothing about existing Go
surface, coverage, or names changes; the wrapper is additive, exactly like `.iterator`.

## Measurable goals

- `.implements = .writer | .reader | .writer_to | .reader_from` on a handle method emits
  the corresponding `io` method, on both cgo and purego backends, with no shim change.
- A wrong shape fails at `zigo-gen` with one diagnostic (`ZIGO058`) that names the
  method, the interface, and what the interface needs.
- Example 11 demonstrates all four on `Document`, with Go tests using `fmt.Fprintf`,
  `io.Copy`, `WriteTo` byte counts and `io.EOF`, passing on cgo and purego.
- Existing generator goldens and examples produce no diff.

## Supported scope and non-goals

Supported:
- `.writer` (`io.Writer`): one input `[]byte` parameter; Zig result `void` or an integer.
- `.writer_to` (`io.WriterTo`): one `*std.Io.Writer` parameter; result `void` or integer.
- `.reader_from` (`io.ReaderFrom`): one `*std.Io.Reader` parameter; result `void` or integer.
- `.reader` (`io.Reader`): one `.out` `[]u8` parameter with `.written = .result`.
- Each may carry a Zig error set; wrapper returns the mapped Go error unchanged.

Non-goals (documented in `docs/limitations.md`):
- `fmt.Stringer`: every handle method can fail (nil/closed handle, native error) and
  `String() string` has nowhere to put that, so no faithful mapping exists.
- `io.Closer`: every handle already has `Close() error`, so `io.Closer`, `io.WriteCloser`
  and `io.ReadCloser` follow from `.writer`/`.reader` for free. Documented, not a key.
- Interfaces outside `io`, user-defined interfaces, and methods with `.cancel`
  (`context.Context` has no place in the `io` signatures), `.iterator`, or callbacks.
- Renaming or hiding the source method. The wrapper is additive.

## Reference source / commit / license

- Precedent for an additive function-level wrapper: `.iterator`
  (`src/gen/emit/iterators.zig`, `src/gen/validate/functions.zig` `iteratorIssue`,
  `src/reflect/walk.zig:964`).
- Precedent for `io.EOF`/`io.Writer` shapes on a handle: stream accessors
  (`examples/11-io-streams/go/streams/streams_gen.go` `Sink.Write`, `Source.Read`).
- gostty feedback item 5 (handle implementing Go interfaces).

## Completion criteria for the whole plan

`zig build test` passes; new generator cases `implements_std` and `implements_std_purego`
are checked in; example 11 tests pass on cgo and purego; `docs/bindings-streams.md`,
`docs/bindings-handles.md`, `docs/cheatsheet.md`, `docs/diagnostics.md`,
`docs/limitations.md`, and `CHANGELOG.md` describe the key; `zig fmt --check` and
`gofmt -l` are clean.
