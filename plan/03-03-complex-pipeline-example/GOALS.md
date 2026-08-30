# GOALS

## Problem and the end result from the user's point of view

The repository has focused examples for individual binding features, but it lacks one realistic example that combines those features into an application-shaped API. Add a pipeline package that users can inspect, generate, test, and benchmark end to end.

## Measurable goals

- Exercise opaque lifetime management, UTF-8 strings, enums, booleans, slices, typed error unions, retained Go callbacks, callback panic translation, named generic specializations, and a propagated system-library link in one example.
- Verify normal operation, failure paths, repeated and concurrent lifecycle use, leak counters, generated-source freshness, and ABI stability.
- Record a runnable Go benchmark result for the generated binding.

## Supported scope and non-goals

The example demonstrates the existing generator rather than adding a new generator feature. It is intentionally small enough to read as documentation and is not a production job scheduler or a general-purpose compression wrapper.

## Reference source / commit / license

Repository implementation and conventions on the current branch; no external source code is copied.

## Completion criteria for the whole plan

The new example builds from a clean generated state, all Zig and Go tests pass, generated-source and ABI checks pass, the callback handle count and native live-byte counter return to zero, CI includes the example, and the benchmark completes with a reported timing.
