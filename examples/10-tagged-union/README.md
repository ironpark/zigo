# Tagged-union accessor example

This example registers `Value` with `.repr = .tagged_union`. zigo reflects its discriminant and
payloads, then generates checked `TryTag() (ValueTag, error)` and
`TryAs<Variant>() (payload, bool, error)` methods for both owned `*Value` and borrowed `*ValueRef`
handles. Compatible `Tag()` and `As<Variant>() (payload, bool)` convenience methods panic with the
same typed errors. The Zig union stays behind an opaque C pointer.

The projection ABI distinguishes mismatch, success, invalid input, and Zig panic. Public accessors
reject nil, closed, and parent-invalid borrowed handles before entering native code. Checked calls
support `errors.Is(err, ErrInvalidHandle)` and `errors.Is(err, ErrNativePanic)`. Ordinary generated
methods and opaque arguments use the same lifecycle guard. Callers must still synchronize `Close`,
variant mutation, and accessor calls on the same handle.

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
