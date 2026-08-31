---
completed_at: "2026-08-31T09:50:30Z"
depends_on:
- "40-tagged-union-value-mirroring#2"
- "40-tagged-union-value-mirroring#3"
perf_phase: false
status: done
---
> DONE-WHEN: 예제가 CI에서 두 백엔드로 빌드·테스트된다.
> NEXT: none

# Example and documentation

## Planned Work

- `examples/10-tagged-union`에 값 스냅샷 union을 추가하거나 별도 예제를 만든다.
  cgo와 purego 양쪽에서 검증한다.
- `03-lowering-rules.md` §7에 두 표현의 선택 기준과 ABI 차이를 적는다.
- `configuration.md`와 `limitations.md`에 opt-in 조건과 제약을 적고,
  `05-implementation-status.md`의 후속 작업 항목을 갱신한다.

## Done When

- 예제가 CI에서 두 백엔드로 빌드·테스트된다.
- 문서가 표현 선택 기준, 적격 조건, ABI 결과를 서술한다.
