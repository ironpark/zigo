---
depends_on:
- "33-purego-library-loading-policy#2"
perf_phase: false
status: planned
---
> DONE-WHEN: The example passes `CGO_ENABLED=0` tests without an explicit load, generated files stay platform
> NEXT: none

# Example, Documentation, and CI

## Planned Work

- Configure one purego example with search paths and automatic loading, regenerate it, and drop
  its explicit load from the test.
- Document the option, the candidate order, the environment variable defaults, and the deployment
  and security consequences of automatic loading in the wiki and the shared-library contract.
- Extend the purego CI job to cover the configured example on every supported target.

## Done When

- The example passes `CGO_ENABLED=0` tests without an explicit load, generated files stay platform
  neutral, the documented commands run as written, and CI exercises the configuration.
