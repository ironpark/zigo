---
perf_phase: false
status: in-progress
---
> DONE-WHEN: 예제 전부에서 `symbol` 중복이 0이고 헤더 이름과 일치하는 테스트 통과.
> NEXT: none

# 함수 심볼 규칙 단일화와 semantic.json 정정

## Planned Work

- `functionSymbolAlloc`을 공유 모듈로 옮기고 `walk.zig:187`, `lower.zig:199-210`, `validate.zig:585`가 모두 호출하게 한다. purego 접미는 lower가 덧붙인다.
- 단위 테스트: `walk.zig` 골든 JSON의 `symbol` 갱신; "같은 프로그램의 모든 `symbol`이 유일하다" 테스트; "semantic.json `symbol` == 헤더 export 이름" 테스트(generator_cases 골든에서 `zigo_*.h`와 `semantic.json`을 대조).
- 예제 10개 `zigo/semantic.json` 재생성. `abi-check` 이행 전략 결정·구현(CONTEXT 참조)과 그 테스트.
- `docs/generated-code.md` 메타데이터 계약 절에 `symbol` 의미 명시.

## Done When

- 예제 전부에서 `symbol` 중복이 0이고 헤더 이름과 일치하는 테스트 통과.
- `abi-check`가 예제 10개에서 통과한다(이행 전략 포함).
- `zig build test` 통과.
