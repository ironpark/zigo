# Stateful event queue example

This application-shaped example exposes a bounded Zig event queue as a Go package:

- an opaque queue with copied UTF-8 metadata and deterministic `Close` ownership;
- `reject` and `drop_oldest` enum policies with typed capacity errors;
- scalar event batches processed through a retained Go observer callback;
- callback panic translation, lifecycle accounting, and concurrent independent queues;
- a custom raw cgo package at `go/bridge/cgo`.

Run the complete example from this directory:

```sh
zig build test
zig build go
zig build go-check abi-check
cd go
go test -count=1 ./...
```

`EventQueue` itself is intentionally not thread-safe. The Go concurrency test creates one
queue per goroutine rather than sharing a queue without synchronization.
