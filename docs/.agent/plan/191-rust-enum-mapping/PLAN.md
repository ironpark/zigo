---
description: Map registered Zig enums to safe named Rust types without changing the shared ABI or Go output
plan_status: in-progress
registered_at: "2026-09-10T06:54:22Z"
---
> NEXT: Implement and verify scalar enum mapping. ([Phase 0](phases/00-scalar-enums.md))

# Phases

- [ ] [Phase 00: Map scalar enums safely](phases/00-scalar-enums.md)
- [ ] [Phase 01: Verify the repository and document the mapping](phases/01-verification-and-handoff.md)

# Shared Verification

zig build test --summary all; scripts/update-generator-cases.sh; git status --short tests/generator_cases (empty after new goldens committed). Compile all accepted non-rust cases with fresh zig-out/bin/zigo-gen and rustc --edition 2021 -D warnings; separate diagnostics from crashes. rustfmt and cargo clippy for new golden crates. zig fmt --check src build build.zig. Each Go example: zig build test go-check go-lib abi-check go-coverage --summary all and go test ./.... Rust example: zig build test rust-check rust-lib abi-check rust-coverage; cargo fmt --check, cargo clippy --all-targets -- -D warnings, cargo test, cargo run --example demo. Compare example generated Go/header/shim/panic/semantic artifacts to branch base.

# Decisions That Constrain Ordering

Implement and prove scalar mapping first; full repository verification and handoff second. Each phase follows start, implementation, verification, commit, done; no force. Existing branch refs and remote remain untouched.

# Next Implementation Target

Implement and verify scalar enum mapping.
