# GOALS

## Problem and the end result from the user's point of view

현재 53개 Zig 테스트는 모두 통과하지만 production module과 build graph의 각 분기가 직접
검증되는지는 별도 문제다. 사용자는 테스트 개수보다 중요한 미검증 계약과 그 보강 순서를
근거와 함께 알아야 한다.

## Measurable goals

- 모든 Zig production/test/example 파일의 test declaration과 build discovery 경로를 집계한다.
- 직접 unit, generator golden, 소비자 build, Go runtime 간접 검증을 구분한다.
- parser, lowering/emission, build API, CLI process, FFI failure 및 target branch의 공백을 찾는다.
- 누락을 위험도와 구현 비용으로 우선순위화하고 구체적인 추가 test case를 제안한다.

## Supported scope and non-goals

현재 소스와 CI의 Zig 테스트 구조를 감사한다. 이 단계에서는 테스트 보강 자체나 공개 API 변경,
정량 line coverage 도구 도입은 수행하지 않는다.

## Reference source / commit / license

현재 브랜치 HEAD의 `build.zig`, `src`, `tests`, `examples`, CI workflow를 기준으로 하며 외부
코드를 사용하지 않는다.

## Completion criteria for the whole plan

실제 test discovery를 재실행하고, production 영역별 현재 근거·누락 시나리오·권장 테스트
형태·우선순위가 감사 문서에 기록되면 완료한다.
