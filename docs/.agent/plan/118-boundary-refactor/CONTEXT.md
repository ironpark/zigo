# SCOPE

Internal architecture and tests; user-facing behavior remains stable.

# CONTEXT

## Current implementation and bottlenecks

Doctor mixes process execution and formatting; tests are duplicated; Materialized responsibilities span encoder, decoder and a large lowering module.

## Target structure and invariants

Process results own their buffers, renderers consume borrowed data, backend tests share contracts, lowering owns layout decisions.
