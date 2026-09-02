---
description: 비exhaustive enum을 .exhaustive = false opt-in으로 명명 상수를 가진 Go 정수 타입으로 노출
plan_status: in-progress
registered_at: "2026-09-02T14:13:46Z"
---
> NEXT: 타입 등록의 `.exhaustive = false` opt-in을 반영하고 ZIGO002를 완화한다. ([Phase 0](phases/00-open-enum-opt-in.md))

# Phases

- [ ] [Phase 00: opt-in 등록과 검증](phases/00-open-enum-opt-in.md)
- [ ] [Phase 01: 예제와 문서](phases/01-example-and-docs.md)

# Shared Verification

- `zig build test --summary all`, `zig fmt --check build.zig src tests examples`.
- 전 예제: `zig build --build-file examples/NN/build.zig test go-check abi-check`, `go/`에서 `go vet ./...`·`go test -count=1 ./...`; purego 04/07/08/11 `purego-go`+`purego-go-check`, 10 `-Dpurego=true`.
- 골든 갱신은 실패 출력의 actual 경로로 `zig build snapshot -- <expected> <actual> --update-snapshots`.

# Decisions That Constrain Ordering

0 → 1. 플랜 75/76과 겹치는 파일은 CHANGELOG와 docs 정도라 병행 가능하나, 75 완료 후 시작을 권장한다.

# Next Implementation Target

타입 등록의 `.exhaustive = false` opt-in을 반영하고 ZIGO002를 완화한다.
