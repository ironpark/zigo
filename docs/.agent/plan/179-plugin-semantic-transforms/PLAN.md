---
depends_on:
- plugin-contract-extensibility
description: Add plugin-driven type adapters, public naming and validated semantic document transforms.
plan_status: in-progress
registered_at: "2026-09-08T05:13:22Z"
---
> NEXT: Implement the semantic customization pipeline and verify external plugins end to end. ([Phase 0](phases/00-semantic-customization.md))

# Phases

- [ ] [Phase 00: Semantic customization](phases/00-semantic-customization.md)

# Shared Verification

Run targeted external lifecycle tests, full zig build test -j4, zig build check -j4, zig fmt --check and git diff --check. Compile and execute generated Go wrappers and native shims on both backends, checking conversion results and asymmetric argument order.

# Decisions That Constrain Ordering

One coherent pipeline phase follows the completed plugin contract work.

# Next Implementation Target

Implement the semantic customization pipeline and verify external plugins end to end.
