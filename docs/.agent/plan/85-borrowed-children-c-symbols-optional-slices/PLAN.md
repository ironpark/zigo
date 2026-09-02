---
description: 빌린 handle의 자식 카운트 불일치, C 심볼 공간 충돌 미검사, optional slice의 .returns = .caller 거부 수정
plan_status: in-progress
registered_at: "2026-09-02T20:35:34Z"
---
> NEXT: 빌린 뷰에서 만든 자식의 예약·해제가 같은 소유 handle에 가도록 고친다. ([Phase 0](phases/00-borrowed-children.md))

# Phases

- [x] [Phase 00: 빌린 뷰의 자식 카운트](phases/00-borrowed-children.md)
- [ ] [Phase 01: C 심볼 공간 진단](phases/01-c-symbol-space.md)
- [ ] [Phase 02: optional slice의 caller 소유권](phases/02-optional-slice-caller.md)
- [ ] [Phase 03: 문서와 CHANGELOG](phases/03-docs.md)

# Shared Verification

- `zig build test --summary all`, `zig fmt --check build.zig src tests examples`.
- 전 예제: `zig build --build-file examples/NN/build.zig test go-check abi-check go-lib`, Go 모듈 디렉터리에서 `go vet ./...`·`go test -count=1 ./...`(07은 `-race`도); purego 04/07/08/11 `purego-go`+`purego-go-check`, 10 `-Dpurego=true`.
- 골든 갱신은 실패 출력의 actual 경로로 `zig build snapshot -- <expected> <actual> --update-snapshots`.

# Decisions That Constrain Ordering

0, 1, 2는 독립, 3은 마지막. 권장: 0(가장 해로운 증상) → 2 → 1 → 3.

# Next Implementation Target

빌린 뷰에서 만든 자식의 예약·해제가 같은 소유 handle에 가도록 고친다.
