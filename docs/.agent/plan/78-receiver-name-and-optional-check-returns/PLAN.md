---
completed_at: "2026-09-02T14:39:33Z"
description: receiver 변수명이 파라미터와 충돌하지 않게 밀고, handle/range 검사 실패 경로가 optional 반환의 presence 값을 함께 돌려주도록 수정
plan_status: done
registered_at: "2026-09-02T14:15:41Z"
---
> NEXT: handle/range 검사 실패 경로가 optional 반환의 presence 값을 함께 돌려주게 한다. ([Phase 0](phases/00-optional-check-returns.md))

# Phases

- [x] [Phase 00: optional 반환의 검사 실패 경로](phases/00-optional-check-returns.md)
- [x] [Phase 01: receiver 변수명 충돌 회피](phases/01-receiver-name-clash.md)
- [x] [Phase 02: 문서와 CHANGELOG](phases/02-docs.md)

# Shared Verification

- `zig build test --summary all`, `zig fmt --check build.zig src tests examples`.
- 전 예제: `zig build --build-file examples/NN/build.zig test go-check abi-check`, `go/`에서 `go vet ./...`·`go test -count=1 ./...`; purego 04/07/08/11 `purego-go`+`purego-go-check`, 10 `-Dpurego=true`.
- 골든 갱신은 실패 출력의 actual 경로로 `zig build snapshot -- <expected> <actual> --update-snapshots`.

# Decisions That Constrain Ordering

0과 1은 독립, 2는 마지막. 둘 다 `emit.zig`만 건드리므로 플랜 75(build.zig 중심)와 병행 가능하다.

# Next Implementation Target

handle/range 검사 실패 경로가 optional 반환의 presence 값을 함께 돌려주게 한다.
