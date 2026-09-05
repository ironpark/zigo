---
description: Lowering builds one ownership record per function; emit and validate read it instead of re-deriving release, string, materialized and handle facts. Golden-invariant.
plan_status: in-progress
registered_at: "2026-09-05T07:47:46Z"
---
> NEXT: `abi.Ownership`과 `lower.ownershipOf`를 추가하고 골든 case별 레코드 테스트를 쓴다. ([Phase 0](phases/00-record-in-lowering.md))

# Phases

- [ ] [Phase 00: Record in lowering](phases/00-record-in-lowering.md)
- [ ] [Phase 01: Emit reads the record](phases/01-emit-reads-record.md)
- [ ] [Phase 02: Validate shares the release lookup](phases/02-validate-shares-lookup.md)
- [ ] [Phase 03: Document the record](phases/03-document-record.md)

# Shared Verification

- 각 phase: `zig build test` (golden 비교 포함).
- phase 1 이후: `grep -rn release_symbol src/`가 비어 있다.
- phase 2 이후: `grep -rn releaseCandidateParameter src/`가 비어 있다.

# Decisions That Constrain Ordering

0 → 1 → 2 → 3. 레코드가 먼저 있어야 emit이 읽을 수 있고, emit이 옮겨진 뒤에야 validate가
같은 helper를 안전하게 공유할 수 있다. 문서는 최종 형태가 정해진 뒤 쓴다.

# Next Implementation Target

`abi.Ownership`과 `lower.ownershipOf`를 추가하고 골든 case별 레코드 테스트를 쓴다.
