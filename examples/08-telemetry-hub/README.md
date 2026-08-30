# Broad telemetry hub API

This example is intentionally much larger than the scenario-focused examples. It is a
binding-generator breadth fixture built around one stateful opaque `TelemetryHub`.

The generated package covers:

- three enums and multiple stable typed error sets;
- owned UTF-8 configuration and a retained Go observer;
- scalar and slice ingestion with two overflow policies;
- processing modes, filtering, counters, statistics, queries, and in-place transforms;
- deterministic close and lifecycle accounting;
- a custom raw package at `go/internal/native`.

Automatic discovery finds **51 functions** while the 26-line binding declaration retains only
the opaque representation and three exceptional UTF-8/callback contracts. Reflection records
**4 public types** (one opaque handle and three enums). Generation produces a 347-line public API file, a separate 56-line
public error file, a 29-line private helper file, and a 236-line raw cgo file under
`go/internal/native`. The Go suite drives every API family, including failed construction cleanup,
transactional batch rejection, callback panic recovery, and independent concurrent lifecycles.

```sh
zig build test
zig build go
zig build go-check abi-check
cd go
go test -count=1 ./...
```

The hub is not safe for concurrent calls. Concurrency tests use one hub per goroutine.
