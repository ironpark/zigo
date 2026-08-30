# Integrated pipeline example

This example combines the repository's binding features in one application-shaped API:

- an opaque `Pipeline` that owns a copied UTF-8 name and retained Go callback;
- enum and boolean state, input slices, typed errors, and callback-panic translation;
- named `IntBatch` and `FloatBatch` generic specializations;
- an idempotent Go `Close`, lifecycle counters, and concurrent construction tests;
- propagated zlib linking through `CompressionBound`.

Generate and verify the package from this directory:

```sh
zig build test
zig build go
zig build go-check abi-check
cd go
go test -count=1 ./...
go test -run '^$' -bench BenchmarkPipelineProcess -benchmem ./pipeline
```
