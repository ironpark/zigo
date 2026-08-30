# GOALS

## Problem and the end result from the user's point of view

Add a standalone complex example that demonstrates how a realistic stateful Zig
component becomes an ergonomic and safely owned Go package, without duplicating
the generic/system-library focus of the existing pipeline example.

## Measurable goals

- Add `examples/07-event-queue` as an independent Zig/Go project.
- Combine an opaque queue, UTF-8 queue/event metadata, enum policy, batch slices,
  typed errors, a retained Go observer, lifecycle accounting, and idempotent close.
- Test normal flow, overflow/rejection, callback panic translation, concurrency,
  stale generation, optional ABI checking, and generated Go formatting.
- Add the example to CI and user/developer documentation.

## Supported scope and non-goals

The example exercises existing zigo capabilities and may fix defects exposed by
the new integration. It does not add new ABI kinds, persistence, networking, or a
production multi-producer queue implementation.

## Reference source / commit / license

The example is original code built against the current repository and Zig 0.16.0;
no external source is copied.

## Completion criteria for the whole plan

Zig tests, generated binding checks, ABI diff, Go functional/race-style lifecycle
tests, repository tests, formatting, and CI configuration all pass with generated
artifacts committed.
