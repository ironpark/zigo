---
depends_on:
- "165-gostty-feedback#0"
perf_phase: false
status: planned
---
> DONE-WHEN: reflect 테스트와 generator case가 optional/slice getter를 생성하고 `zig build test` 통과, 커밋.
> NEXT: none

# Optional and slice field leafs

## Planned Work

- `supportedFieldAccessLeaf` 추가: scalar, `?scalar`, `[]const scalar`(narrow int 제외). setter는 scalar/`?scalar`만.
- shim.writeFieldAccess에 optional/slice getter 분기, `?scalar` setter.
- ZIGO037 메시지·docs·generator case field_access 확장과 스냅샷 갱신.

## Done When

- reflect 테스트와 generator case가 optional/slice getter를 생성하고 `zig build test` 통과, 커밋.
