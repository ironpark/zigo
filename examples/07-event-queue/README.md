# Stateful event queue example

This application-shaped example exposes a bounded Zig event queue as a Go package:

- an opaque queue with copied UTF-8 metadata and deterministic `Close` ownership;
- `reject` and `drop_oldest` enum policies with typed capacity errors;
- scalar event batches processed through a retained Go observer callback;
- callback panic translation, lifecycle accounting, and concurrent independent queues;
- Go 1.24 `runtime.AddCleanup` fallback while deterministic `Close` remains primary;
- a custom raw cgo package at `go/bridge/cgo`;
- `extern struct` parameters and returns via `Stats`, `Limits`, `ApplyLimits`, exposed as Go
  values while the C ABI takes pointers.

Run the complete example from this directory:

```sh
zig build test
zig build go
zig build go-check abi-check
cd go
go test -count=1 ./...
```

`Stats` and `Limits` are Zig `extern struct` types. Go passes and receives them by value; the
generated code takes the address, because zigo never moves an aggregate across the C boundary
by value. `go/bridge/cgo/cheader` reads the layout the generated header defines so the layout
test can check the Go mirrors against it directly.

`EventQueue` itself is intentionally not thread-safe. The Go concurrency test creates one
queue per goroutine rather than sharing a queue without synchronization.
Every generated handle registers a `runtime.AddCleanup` safety net; the forced-GC test here
demonstrates that fallback, but application code must still call `Close` because cleanup
timing is not guaranteed.
