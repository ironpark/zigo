# GOALS

## Problem and the end result from the user's point of view

Three gaps remain in the generated Go surface and the build integration:

1. A Zig `next()`-style method returning `?T` is exposed as `Next() (T, bool, error)`,
   so Go callers write the `for { v, ok, err := it.Next() ... }` loop by hand.
   After this plan a binding marks such a method with `.iterator = .{}` and the
   generated handle gains an `All() iter.Seq2[T, error]` (or `iter.Seq[T]` when
   the Go signature carries no error) that drives the loop with range-over-func.
2. Generated enums have `String()` but no way back from text, so JSON, CLI flags
   and config files need hand-written parsing. After this plan an enum registered
   with `.text = true` gains `Parse<Enum>(string) (<Enum>, error)`,
   `MarshalText` and `UnmarshalText`.
3. `targets` is rejected for `.link = .purego`, so a purego project builds one
   prefix per platform by hand. After this plan `targets` works with purego: every
   listed platform's shared library installs under `library_dir/<goos>_<goarch>/`,
   and the generated loader looks in the `<GOOS>_<GOARCH>` subdirectory of each
   search-path entry at run time.

## Measurable goals

- A generator case with `.iterator` pins the wrapper for a no-error and an
  error-carrying method; existing cases stay byte-identical.
- A generator case with `.text = true` pins the parse/marshal code; `open_enum`
  and every other case stay byte-identical.
- A purego build with `.targets` installs two libraries in two platform
  subdirectories and the emitted candidates join the platform subdirectory;
  a purego build without `targets` keeps today's generated files and layout.
- `zig build test` passes, and the touched examples pass `go test`.

## Supported scope and non-goals

Supported: iterator wrappers on registered handle methods whose only Go
parameters are the receiver (and an optional `ctx`), whose return is `?T` or
`!?T` with any payload the method already supports. Enum text encoding on
explicitly registered enums, including open enums (which also parse the
`Name(N)` spelling `String()` prints). purego `targets` with the same install
subdirectory convention as cgo.

Non-goals: iterators over free functions or methods with data parameters,
`iter.Pull` helpers, text encoding on auto-discovered enums or packed structs,
JSON encoding beyond what `encoding.TextMarshaler` gives for free, per-target
`library_loading` policies, and mobile/32-bit targets.

## Reference source / commit / license

Own code. Go `iter` package semantics (`iter.Seq2`) and
`encoding.TextMarshaler`/`TextUnmarshaler` contracts from the Go standard library.

## Completion criteria for the whole plan

All three phases done, `zig build test --summary all` green, generator cases
added for each feature, the affected example(s) regenerated and passing
`go test`, and `docs/`, README and CHANGELOG describing the three options.
