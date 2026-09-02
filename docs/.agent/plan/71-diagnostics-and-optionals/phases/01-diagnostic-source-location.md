---
perf_phase: false
status: planned
---
> DONE-WHEN: CLI 테스트 통과, 기존 진단 스냅샷이 위치를 포함하도록 갱신.
> NEXT: none

# 진단의 소스 위치

## Planned Work

- `names.zig`: 함수·파라미터 토큰 위치 기록. `semantic.zig`: `source` 선택 필드 직렬화. `diagnostic.zig`: `Site.line/column`, 렌더링. `validate.zig`: 함수·파라미터 진단에 위치 주입.
- 골든 JSON 갱신(위치 필드 추가는 abi_diff에 영향 없음을 테스트). CLI 계약 테스트: `bindings.zig:LINE:COL`.
- `docs/generated-code.md` 메타데이터 계약에 `source` 필드.

## Done When

- CLI 테스트 통과, 기존 진단 스냅샷이 위치를 포함하도록 갱신.
