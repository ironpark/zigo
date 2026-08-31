# SCOPE

Files expected to change: `src/gen/emit.zig` (variant type + accessor
emission), possibly `src/gen/naming.zig` (variant type-name derivation and
collision handling), golden/snapshot fixtures under `tests/`, regenerated
`examples/*/go*` trees, and new/updated hand-written tests in
`examples/10-tagged-union`. The change is additive to the generated public
API; no existing names change.

# CONTEXT

## Current implementation and bottlenecks

Post-plan-50 state (`examples/10-tagged-union/go/tagged_union/
tagged_union_type_gen.go`, 793 lines):

- Per union: `<Union>Tag` enum, shared unexported projection functions
  (`zigoValueAsInteger(receiver zigoHandle) (int64, bool, error)`), and
  one-line `As*`/`MustAs*` delegations on the handle and ref types.
- Scalar-only unions additionally get `<Union>Snapshot` (one native call via
  `raw.<Union>ReadSnapshot` returning tag + every scalar payload) with
  getter methods.
- Payload kinds observed: none (void), scalars (int/bool/enum/float), slices
  (`[]int16`, defensively copied), and child handles surfaced as `*ChildRef`
  parented to the receiver.
- Consuming code must branch on `Tag()` and then call the right `As*`,
  which is N native calls in the worst case and un-Go-like.

## Target structure and invariants

- Sealed interface per union: `type ValueVariant interface {
  isValueVariant() }`; concrete types `ValueNone struct{}`,
  `ValueInteger struct { Value int64 }`, `ValueFlag struct { Value bool }`,
  `ValueModeVariant`-style names only on collision (see naming), 
  `ValueSamples struct { Values []int16 }`, `ValueChild struct { Child
  *ChildRef }`. Exported payload fields — variants are plain data carriers.
- Naming: variant type name is `<Union><PascalVariant>`. `naming.zig` must
  detect and deterministically resolve collisions with existing generated
  identifiers (e.g. a variant named like the union's tag type or another
  declared type) and surface a diagnostic rather than emitting invalid Go.
- One shared unexported builder per union (`zigoValueVariant(receiver
  zigoHandle) (ValueVariant, error)`): scalar-only unions read the snapshot
  in one native call and switch on the tag; unions with non-scalar payloads
  read the tag, then invoke only the matching projection (tag read + one
  projection call, never N probes). Child-handle payloads parent their ref
  to the receiver exactly as `AsChild` does today.
- `Variant`/`MustVariant` follow plan 50's conventions: error-first base
  name, `Must*` panics via the existing `zigoMust` helper, handle and ref
  methods are one-line delegations.
- Purego and cgo emission stay in lockstep; goldens cover both.
