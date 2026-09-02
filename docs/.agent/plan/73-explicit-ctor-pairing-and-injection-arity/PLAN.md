---
description: 명시적 생성자/소멸자 메타(.constructs/.destroys), root 생성자의 Zig 호출 경로 수정, 주입 파라미터를 .params 인덱싱과 .release 매칭에서 제외
plan_status: in-progress
registered_at: "2026-09-02T12:34:21Z"
---
> NEXT: 주입 파라미터를 `.params` 인덱싱과 `.release` 매칭에서 제외하고 길이 불일치를 ZIGO027 진단으로 낸다. ([Phase 0](phases/00-injection-arity.md))

# Phases

- [x] [Phase 00: 주입 파라미터 arity와 release 매칭](phases/00-injection-arity.md)
- [x] [Phase 01: 생성자 Zig 호출 경로 분리](phases/01-constructor-call-path.md)
- [ ] [Phase 02: .constructs / .destroys 메타](phases/02-explicit-pairing-meta.md)
- [ ] [Phase 03: 문서와 CHANGELOG](phases/03-docs.md)

# Shared Verification

- `zig build test --summary all`, `zig fmt --check build.zig src tests examples`.
- 전 예제: `zig build --build-file examples/NN/build.zig test go-check abi-check`, `go/`에서 `go vet ./...`·`go test -count=1 ./...`; purego 04/07/08/11 `purego-go`+`purego-go-check`, 10 `-Dpurego=true`.
- 골든 갱신은 실패 출력의 actual 경로로 `zig build snapshot -- <expected> <actual> --update-snapshots`.

# Decisions That Constrain Ordering

0과 1은 독립. 2는 1의 호출 경로 분리가 있어야 root 생성자가 동작하므로 1 뒤. 3은 마지막. 권장: 0 → 1 → 2 → 3.

# Next Implementation Target

주입 파라미터를 `.params` 인덱싱과 `.release` 매칭에서 제외하고 길이 불일치를 ZIGO027 진단으로 낸다.
