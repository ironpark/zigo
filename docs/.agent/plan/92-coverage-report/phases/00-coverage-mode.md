---
perf_phase: false
status: in-progress
---
> DONE-WHEN: `zig build --build-file examples/NN/build.zig go-coverage` prints the report for an example with a deliberately unbound function; verification loop green.
> NEXT: none

# Coverage mode

## Planned Work

- Reflection coverage walk with classification; text/JSON renderers; `go-coverage` step in the build helper; tests, example wiring, docs, CHANGELOG.

## Done When

- `zig build --build-file examples/NN/build.zig go-coverage` prints the report for an example with a deliberately unbound function; verification loop green.
