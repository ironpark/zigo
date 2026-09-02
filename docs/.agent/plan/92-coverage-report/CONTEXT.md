# SCOPE

- Counting unit: public function declarations reachable from `root` and registered types; the percentage is bound/(bound+unbound), excluded declarations are listed but not counted.

# CONTEXT

## Current implementation and bottlenecks

- Reflection only visits what `.functions`/discovery select; nothing enumerates the rest.

## Target structure and invariants

- The coverage walk shares the discovery traversal so both agree on what is public.
