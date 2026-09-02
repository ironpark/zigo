---
description: 호스트 reflection 모듈 복제가 .other_step 라이브러리의 libc++/include 설정을 잃는 0.4.0 회귀 수정
plan_status: in-progress
registered_at: "2026-09-02T17:32:43Z"
---
> NEXT: C++ 라이브러리를 `linkLibrary`로 붙인 예제로 회귀를 재현하고 `hostReflectionModule`을 고친다. ([Phase 0](phases/00-reproduce-and-fix.md))

# Phases

- [ ] [Phase 00: 회귀 재현과 수정](phases/00-reproduce-and-fix.md)
- [ ] [Phase 01: 문서와 CHANGELOG](phases/01-docs.md)

# Shared Verification

- `zig build test --summary all`, `zig fmt --check build.zig src tests examples`.
- 전 예제: `zig build --build-file examples/NN/build.zig test go-check abi-check`, Go 모듈 디렉터리에서 `go vet ./...`·`go test -count=1 ./...`; purego 04/07/08/11 `purego-go`+`purego-go-check`, 10 `-Dpurego=true`.
- 회귀 예제: `zig build --build-file examples/NN/build.zig go-lib -Dtarget=<x86_64-windows-gnu|x86_64-linux-gnu|aarch64-linux-musl>`.

# Decisions That Constrain Ordering

0 → 1. 다른 플랜과 독립이며, 회귀이므로 가장 먼저 진행한다.

# Next Implementation Target

C++ 라이브러리를 `linkLibrary`로 붙인 예제로 회귀를 재현하고 `hostReflectionModule`을 고친다.
