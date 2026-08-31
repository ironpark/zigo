# Tagged-union accessor example

This example registers `Value` with `.repr = .tagged_union`. zigo reflects its discriminant and
payloads, then generates checked `Tag() (ValueTag, error)` and
`As<Variant>() (payload, bool, error)` methods for both owned `*Value` and borrowed `*ValueRef`
handles. `MustTag()` and `MustAs<Variant>() (payload, bool)` companions panic with the
same typed errors. The Zig union stays behind an opaque C pointer.

The projection ABI distinguishes mismatch, success, invalid input, and Zig panic. Public accessors
reject nil, closed, and parent-invalid borrowed handles before entering native code. Checked calls
support `errors.Is(err, ErrInvalidHandle)` and `errors.Is(err, ErrNativePanic)`. Ordinary generated
methods and opaque arguments use the same lifecycle guard. Callers must still synchronize `Close`,
variant mutation, and accessor calls on the same handle.

`Signal` sits alongside `Value` and registers with `.repr = .tagged_union, .access = .snapshot`. Every one of its
variant payloads is void, a bool, a scalar, or an enum, so zigo also generates a value snapshot: a
zigo-owned `extern struct` that the shim fills from the active variant. `Snapshot() (SignalSnapshot, error)`
and its panicking `MustSnapshot()` companion carry the tag and the payload back in a single native call,
and reading them off the snapshot afterwards is plain Go. The projection accessors stay available on
the same type; the snapshot is an addition, not a replacement. Appending a variant to a snapshot
union is a breaking ABI change, because the struct's size and layout move.

This example also enables Go 1.24 `runtime.AddCleanup` as a leak fallback. Explicit `Close` remains
the deterministic lifecycle contract, including when projections are in use.

The tests cover scalar and enum variants, wrong-variant access, a copied numeric-slice payload, and
an opaque child payload. They also verify output preservation and lifecycle rejection. Void variants
have a tag constant but no payload accessor.

```sh
zig build test
zig build go
zig build go-doctor
zig build go-report
zig build go-check abi-check
cd go && go test ./...
```
