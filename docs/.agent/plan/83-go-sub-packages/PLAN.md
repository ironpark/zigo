---
completed_at: "2026-09-02T19:48:15Z"
description: 타입·namespace·함수를 별도 공개 Go 패키지로 나누는 .packages 선언과 공용 lifecycle 런타임 패키지
plan_status: done
registered_at: "2026-09-02T19:05:03Z"
---
> NEXT: cgo 백엔드의 lifecycle 헬퍼·오류를 공용 `internal/lifecycle` 패키지로 옮기고 공개 API를 alias로 보존한다. ([Phase 1](phases/01-shared-runtime.md))

# Phases

- [x] [Phase 00: 선언과 semantic.json](phases/00-declaration-and-semantic.md)
- [x] [Phase 01: 공용 lifecycle 런타임](phases/01-shared-runtime.md)
- [x] [Phase 02: 패키지별 emit과 순환 진단](phases/02-per-package-emit.md)
- [x] [Phase 03: 예제, 문서, CHANGELOG](phases/03-example-and-docs.md)

# Shared Verification

- `zig build test --summary all`, `zig fmt --check build.zig src tests examples`.
- 전 예제: `zig build --build-file examples/NN/build.zig test go-check abi-check`, Go 모듈 디렉터리에서 `go vet ./...`·`go test -count=1 ./...`; purego 04/07/08/11 `purego-go`+`purego-go-check`, 10 `-Dpurego=true`.
- 골든 갱신은 실패 출력의 actual 경로로 `zig build snapshot -- <expected> <actual> --update-snapshots`.

# Decisions That Constrain Ordering

0과 1은 독립, 2는 둘 다 필요, 3은 마지막. 권장: 1 → 0 → 2 → 3 (1이 가장 넓게 골든을 건드리므로 먼저 안정화).

# Next Implementation Target

cgo 백엔드의 lifecycle 헬퍼·오류를 공용 `internal/lifecycle` 패키지로 옮기고 공개 API를 alias로 보존한다.
