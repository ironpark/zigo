# SCOPE

Files expected to change: `src/gen/emit.zig` (bulk of the work), possibly
`src/gen/naming.zig` and `src/gen/generator.zig`, golden/snapshot fixtures
under `tests/`, and all generated trees plus hand-written tests under
`examples/*/go*/`. Public API of generated packages changes deliberately
(breaking): `Try*` methods become the base names, panicking variants gain
`Must`, `Close` gains an error return.

# CONTEXT

## Current implementation and bottlenecks

The generator is Zig (`src/gen/`), with `emit.zig` producing the Go text.
Observed output issues (examples 04/05/10):

- `Tag()`/`AsInteger()` panic; `TryTag()`/`TryAsInteger()` return errors —
  inverted relative to Go's `Must` convention. Ordinary methods call
  `zigoMustPointer`, which panics on nil/closed handles.
- Handle and Ref types (`Value`/`ValueRef`, `Signal`/`SignalRef`) each get a
  full copy of every projection method; example 10's type file is 1118 lines,
  mostly duplication.
- Enum constants are emitted one `const X = N` at a time with per-constant
  comments instead of a single block; `String()` uses
  `strconv.FormatInt(int64(v), 10)`.
- `Close()` returns nothing, so handles do not satisfy `io.Closer`.
- Examples 04/05 (and possibly others) still contain an older generation
  (`mu sync.RWMutex` lifecycle) while example 10 uses the newer
  `sync.Once` + `runtime.AddCleanup` scheme.

## Target structure and invariants

- Error-first surface: `X() (T, error)` (or `(T, bool, error)` for
  projections) is the base name; `MustX` wraps it with panic-on-error. The
  internal pointer resolver keeps a checked (error) form; the panicking form
  exists only to serve `Must*`.
- One unexported implementation function per projection/operation taking the
  `zigoHandle` interface; handle and ref methods are one-line delegations.
- Enums: single `const ( ... )` block, first constant typed and the rest
  aligned, `String()` via a switch or index table using `strconv.Itoa`.
- `Close() error` always returns nil today but reserves the signature.
- All examples regenerated from the current generator in the same change set
  as each behavioral phase, keeping goldens, examples, and generator in sync.
