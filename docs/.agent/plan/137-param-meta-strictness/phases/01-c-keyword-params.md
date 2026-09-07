---
completed_at: "2026-09-07T02:52:28Z"
perf_phase: false
status: done
---
> DONE-WHEN: `double` 파라미터 문서가 ZIGO021 진단을 받는 테스트가 통과한다.
> NEXT: none

# Reject C keyword parameter names

## Planned Work

- `naming.zig`에 `isCKeyword` 추가.
- `names.zig` `identifierIssue`에서 비주입 파라미터 이름을 검사해 ZIGO021 진단 반환.
- 테스트와 문서 추가.

## Done When

- `double` 파라미터 문서가 ZIGO021 진단을 받는 테스트가 통과한다.
