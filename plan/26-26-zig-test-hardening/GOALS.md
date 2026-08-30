# GOALS

## Problem and the end result from the user's point of view

감사에서 확인한 테스트 공백 때문에 example의 Zig 상태 테스트가 CI에서 실행되지 않고,
손상된 semantic 참조는 정상 오류 대신 generator panic을 일으킨다. negative fixture와 parser,
lowering, build option의 직접 테스트도 부족하다. 사용자는 회귀가 실제 build/test graph에서
차단되는 상태를 원한다.

## Measurable goals

- 8개 example 모두 `zig build test`를 제공하고 CI에서 14개 Zig 테스트를 실행한다.
- semantic의 type/constructor 참조 무결성을 validation error로 처리하고 panic 재현을 고정한다.
- invalid-project를 expected-failure process test로 연결해 exit와 진단을 확인한다.
- malformed semantic/default/OOM과 핵심 ABI lowering 역할을 직접 unit test한다.
- raw path/name 같은 pure build option 검증을 test 가능한 module로 분리하고 경계값을 검사한다.

## Supported scope and non-goals

Zig test/build graph와 validation/parser/lowering/build helper를 보강한다. v1 비지원인 소비자 cross
generation, filesystem 장애 전체 transaction, 장시간 coverage-guided fuzz campaign은 범위 밖이다.

## Reference source / commit / license

`06-zig-test-coverage-audit.md`의 우선순위와 현재 브랜치 HEAD를 기준으로 하며 외부 코드를
복사하지 않는다.

## Completion criteria for the whole plan

새 회귀 테스트가 기존 panic과 dead fixture를 검출하고, root 53개 및 추가 test artifact,
8개 example Zig/Go/stale/ABI 검증, CI 형식과 host compile gate가 모두 통과하면 완료한다.
