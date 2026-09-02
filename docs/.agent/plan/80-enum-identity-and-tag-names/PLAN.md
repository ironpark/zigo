---
description: comptime enum identity를 @typeName 문자열이 아닌 타입으로 판별하고, enum tag 식별자 검사를 실제 emit 이름 기준으로 변경
plan_status: in-progress
registered_at: "2026-09-02T17:32:43Z"
---
> NEXT: 등록 타입 판별을 `@typeName` 문자열 비교에서 comptime 타입 동일성으로 바꾼다. ([Phase 0](phases/00-type-identity.md))

# Phases

- [ ] [Phase 00: 타입 identity](phases/00-type-identity.md)
- [ ] [Phase 01: emit 이름 기준 식별자 검사](phases/01-emitted-name-check.md)
- [ ] [Phase 02: 문서와 CHANGELOG](phases/02-docs.md)

# Shared Verification

- `zig build test --summary all`, `zig fmt --check build.zig src tests examples`.
- 전 예제: `zig build --build-file examples/NN/build.zig test go-check abi-check`, Go 모듈 디렉터리에서 `go vet ./...`·`go test -count=1 ./...`; purego 04/07/08/11 `purego-go`+`purego-go-check`, 10 `-Dpurego=true`.
- 골든 갱신은 실패 출력의 actual 경로로 `zig build snapshot -- <expected> <actual> --update-snapshots`.

# Decisions That Constrain Ordering

0과 1은 독립, 2는 마지막. 79(회귀) 다음으로 우선한다.

# Next Implementation Target

등록 타입 판별을 `@typeName` 문자열 비교에서 comptime 타입 동일성으로 바꾼다.
