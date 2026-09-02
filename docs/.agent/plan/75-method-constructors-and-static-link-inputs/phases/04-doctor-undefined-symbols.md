---
depends_on:
- "75-method-constructors-and-static-link-inputs#1"
entry_condition: 사용자가 요청하거나, phase 1 이후에도 정적 링크 실패가 zigo/Zig/모듈 중 어디 원인인지 구분되지 않는 사례가 남을 때
perf_phase: false
status: conditional
---
> DONE-WHEN: 미해결 심볼이 있는 아카이브에서 doctor가 원인 힌트를 출력, 테스트 추가, 커밋.
> NEXT: none

# doctor의 미해결 심볼 진단

## Planned Work

- `go-doctor`가 정적 아카이브의 미해결 심볼을 `nm -u`(호스트 도구 있을 때만)로 나열하고, compiler_rt/ubsan_rt 심볼이면 힌트를 붙인다.

## Done When

- 미해결 심볼이 있는 아카이브에서 doctor가 원인 힌트를 출력, 테스트 추가, 커밋.
