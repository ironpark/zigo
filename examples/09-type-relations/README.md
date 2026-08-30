# Multi-type relations

This focused example exposes two opaque types from one binding document. `Accumulator.absorb`
is owned by `Accumulator` but accepts a borrowed `*const Counter`, demonstrating that semantic
ownership and parameter type references are independent.

The generated Go API contains two independent constructors and lifecycles:

```go
counter, _ := NewCounter(40)
defer counter.Close()
accumulator, _ := NewAccumulator()
defer accumulator.Close()
total := accumulator.Absorb(counter)
```

Run the complete example contract with:

```sh
zig build test
zig build go
zig build go-check abi-check
cd go && go test -count=1 ./...
```
