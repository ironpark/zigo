# Tagged-union accessor example

This example registers `Value` with `.repr = .tagged_union`. zigo reflects its discriminant and
payloads, then generates `Tag()` and checked `As<Variant>() (payload, bool)` methods for both owned
`*Value` and borrowed `*ValueRef` handles. The Zig union stays behind an opaque C pointer.

The tests cover scalar and enum variants, wrong-variant access, a copied numeric-slice payload, and
an opaque child payload. Void variants have a tag constant but no payload accessor.

```sh
zig build test
zig build go
zig build go-check abi-check
cd go && go test ./...
```
