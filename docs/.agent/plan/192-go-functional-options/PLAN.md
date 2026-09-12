---
description: Zig 옵션 구조체를 Go functional options 생성자로 노출 (opt-in, ABI 불변)
plan_status: in-progress
registered_at: "2026-09-12T03:37:08Z"
---
> NEXT: phase 0에서 `FlattenedField.default`를 추가하고 reflection이 Zig 기본값을 싣게 합니다. ([Phase 0](phases/00-flattened-field-defaults.md))

# Phases

- [x] [Phase 00: 기본값을 IR과 reflection에 싣기](phases/00-flattened-field-defaults.md)
- [x] [Phase 01: `zigo.param.options` authoring API](phases/01-options-authoring-api.md)
- [x] [Phase 02: 옵션 계약 진단](phases/02-options-diagnostics.md)
- [x] [Phase 03: 옵션 타입과 `With*` 이름](phases/03-options-naming.md)
- [x] [Phase 04: 공개 Go 생성자 방출](phases/04-options-emission.md)
- [ ] [Phase 05: 예제와 ABI 불변 확인](phases/05-example-and-abi.md)
- [ ] [Phase 06: 문서와 CHANGELOG](phases/06-docs-and-changelog.md)

# Shared Verification

- `zig build test --summary all` -- 단위, 골든과 진단 테스트
- 예제에서 `zig build go-check abi-check --summary all` -- 생성 트리와 C 표면
- `(cd examples/07-event-queue/go && go test ./...)` -- 기본값이 실제로 적용되는지
- `zig fmt --check`와 예제 Go 모듈의 `staticcheck -checks U1000`
- 옵션 도입 커밋 앞뒤의 `abi-check` 출력 비교 -- ABI 불변이라는 이 계획의 핵심 주장
- `git status --porcelain examples`가 깨끗한지 -- 생성물 stale 검사

# Decisions That Constrain Ordering

phase 0이 먼저입니다. 기본값이 문서에 없으면 이후 어떤 phase도 옵션의 기본값을 쓸 수
없습니다. phase 1이 그 위에서 authoring 표면을 열고, phase 2와 3은 phase 1에만
의존하므로 순서를 바꾸거나 나란히 진행할 수 있습니다. phase 4는 이름(3)과 규칙(2)이
정해진 뒤에야 방출할 수 있습니다. phase 5는 방출된 코드가 있어야 예제를 바꿀 수 있고,
phase 6은 실제 생성 결과를 보고 문서를 써야 하므로 마지막입니다.

# Next Implementation Target

phase 0에서 `FlattenedField.default`를 추가하고 reflection이 Zig 기본값을 싣게 합니다.
