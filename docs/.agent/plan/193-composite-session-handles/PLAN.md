---
description: 부모-자식 핸들을 하나로 묶어 자식부터 닫는 Session 타입 생성 (Go 출력 전용, ABI 불변)
plan_status: in-progress
registered_at: "2026-09-12T03:59:14Z"
---
> NEXT: phase 0에서 `zigo.session` 선언을 열고 부모-자식 관계 검증 진단을 세웁니다. ([Phase 0](phases/00-session-declaration.md))

# Phases

- [ ] [Phase 00: 선언 표면과 관계 검증](phases/00-session-declaration.md)
- [ ] [Phase 01: Session 타입과 접근자 방출](phases/01-session-emission.md)
- [ ] [Phase 02: Close 의미론](phases/02-session-close.md)
- [ ] [Phase 03: 예제와 ABI 불변 확인](phases/03-example-and-abi.md)
- [ ] [Phase 04: 문서와 CHANGELOG](phases/04-docs-and-changelog.md)

# Shared Verification

- `zig build test --summary all` -- 선언, 진단, 골든 테스트
- 예제에서 `zig build go-check abi-check --summary all`
- `(cd examples/07-event-queue/go && go test ./...)` -- 순서 계약과 대조 경로
- `(cd examples/07-event-queue/go && go test -race ./...)` -- `Close` 동시 호출
- `zig fmt --check`와 예제 Go 모듈의 `staticcheck -checks U1000`
- 세션 도입 커밋 앞뒤의 `abi-check` 출력 비교 -- ABI 불변이라는 핵심 주장
- `git status --porcelain examples`가 깨끗한지

# Decisions That Constrain Ordering

phase 0이 먼저입니다. 어떤 관계가 유효한지 정하지 않으면 무엇을 방출할지도 정할 수
없고, 관계 검증이 곧 Session의 안전성 근거입니다. phase 1은 수명 의미론을 빼고
타입·생성자·접근자만 세워 이름과 파일 배치를 먼저 확정합니다. phase 2가 그 위에 이
계획의 본론인 `Close`를 올립니다. 1과 2를 나눈 이유는 이름 충돌 문제와 동시성 문제를
한 번에 디버깅하지 않기 위해서입니다. phase 3은 방출된 코드가 있어야 예제를 바꿀 수
있고, phase 4는 실제 생성 결과를 보고 문서를 써야 하므로 마지막입니다.

# Next Implementation Target

phase 0에서 `zigo.session` 선언을 열고 부모-자식 관계 검증 진단을 세웁니다.
