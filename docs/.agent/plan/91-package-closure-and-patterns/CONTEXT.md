# SCOPE

- Resolution order: explicit names, then patterns, then closure; closure runs after all explicit and pattern assignments across every package.

# CONTEXT

## Current implementation and bottlenecks

- Assignment is by exact name lists (`types`, `namespaces`, `functions`), see docs "공개 Go 하위 패키지".

## Target structure and invariants

- Assignment stays deterministic and independent of declaration order.
