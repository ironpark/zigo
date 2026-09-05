# GOALS

## Problem and the end result from the user's point of view

A review of the generated Go in the examples found four things worth fixing:

1. Every method of a type with retained callbacks sweeps every callback slot
   after every call (a mutex and a `cgo.Handle` map lookup per slot), even
   when the call could not have reached a callback.
2. Receiver names drift per method (`c` here, `co` there) when a parameter
   shares the letter, and a Zig doc that opens with a capitalized sentence
   leaves a bare `// Name` line so `go doc` summaries are empty.
3. UTF-8 strings are copied twice on the way in (`[]byte(s)`) and out
   (`C.GoBytes` then `string(...)`), and non-castable struct slices are
   converted field by field in the raw layer and again in the public layer.
4. Every fallible call pins the OS thread so the panic message can be read
   from C thread-local storage in a second cgo call. On this machine that is
   35 ns of a 324 ns call (11%), above the 10% threshold plan 68 set for
   changing the panic-message ABI.

After this plan the sweep is one atomic load on the fast path, receiver names
are chosen once per type, GoDoc summaries keep the first sentence, strings and
struct slices cross with one copy, and the panic message travels through a
sequence-tagged slot table so the thread pin goes away.

## Measurable goals

- `BenchmarkEnqueue` in 07-event-queue loses the `LockOSThread` cost and the
  per-slot sweep: within noise of `BenchmarkEnqueueUnlocked` or better.
- Generated receiver names are identical across all methods of a type in every
  example; `staticcheck` ST1016 stays clean.
- `Name()`-style string returns and string parameters allocate once.
- Generator cases pin every change; `zig build test` and every example's
  `go test` pass on both backends.

## Supported scope and non-goals

In scope: the emitters for public, raw (cgo and purego), runtime, docs and the
C panic bridge; docs and CHANGELOG; example regeneration. Not in scope:
changing the public API shape (return arities), `c_string` inputs (they still
need a NUL copy), and `.release` struct slices beyond the raw memcpy.

## Reference source / commit / license

Own code. Go `unsafe.String`/`unsafe.StringData` (Go 1.20+), C11 atomics.

## Completion criteria for the whole plan

All phases done, tests green, examples regenerated on both backends, docs and
CHANGELOG updated, `go-check`/`purego-go-check` clean for every example.
