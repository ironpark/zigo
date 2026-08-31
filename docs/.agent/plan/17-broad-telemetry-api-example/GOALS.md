# GOALS

## Problem and the end result from the user's point of view

Provide a deliberately broad application API whose generated surface is large
enough to expose symbol collisions, ordering drift, ownership mistakes, error-code
growth, documentation gaps, and unwieldy Go bindings that small examples miss.

## Measurable goals

- Add `examples/08-telemetry-hub` with at least 40 bound functions.
- Cover one owned opaque hub, three enums, UTF-8 rename/state, scalar and slice
  ingestion, retained observation, typed failures, transforms, queries, statistics,
  maintenance, lifecycle accounting, and a custom raw package.
- Exercise every API family from Zig and Go tests and record the exact generated
  function/type/error counts in the example README.
- Add generation, ABI, Go, repository, cross-target, formatting, and CI coverage.

## Supported scope and non-goals

This is a breadth/stress example for existing zigo contracts. It is intentionally
more verbose than production guidance and is not a durable telemetry database,
thread-safe shared service, or a new ABI feature implementation.

## Reference source / commit / license

All example code is original and targets the current repository with Zig 0.16.0.
No external implementation is copied.

## Completion criteria for the whole plan

The generated public Go package exposes at least 40 operations, all focused and
repository-wide checks pass, regeneration is clean, ABI checking works after the
baseline commit, CI includes the eighth example, and documentation distinguishes
this breadth fixture from the scenario-focused examples.
