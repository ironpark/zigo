---
depends_on:
- consume-ghostty-vt
- ultrasync-followups
description: Go 식별자 검증과 enum 등록, 승격 정수의 Go 사전검사, infallible 함수의 패닉 가시성, 패키지 doc 순서, allocator 주입
plan_status: in-progress
registered_at: "2026-09-02T07:14:37Z"
---
> NEXT: reflection이 유도한 모든 Go 이름을 `ZIGO021`로 검증해 `4])` 같은 이름이 생성 전에 거부되게 한다. ([Phase 0](phases/00-identifier-validation.md))

# Phases

- [x] [Phase 00: 유도 Go 식별자 검증](phases/00-identifier-validation.md)
- [x] [Phase 01: enum을 `.types`에 등록](phases/01-enum-registration.md)
- [x] [Phase 02: 승격 정수의 Go 사전검사](phases/02-narrow-int-precheck.md)
- [x] [Phase 03: checked infallible 함수의 패닉 가시성](phases/03-panic-visibility.md)
- [x] [Phase 04: 패키지 doc 순서에 `bindings.zig` 복귀](phases/04-package-doc-order.md)
- [x] [Phase 05: Allocator/Io 주입](phases/05-allocator-injection.md)
- [ ] [Phase 06: 값 반환 `init`을 caller-owned pointer로](phases/06-by-value-init.md)

# Shared Verification

- `zig build test --summary all`, `zig fmt --check build.zig src tests examples`.
- 예제 루프 + purego 4개(04/07/08 `purego-go`·`purego-go-check`, 10 `-Dpurego=true`).
- 골든 갱신은 실패 출력의 actual 경로를 `zig build snapshot -- <expected> <actual> --update-snapshots`에.
- gostty: `zig build go && zig build && (cd go && go vet ./... && go test ./...)`.

# Decisions That Constrain Ordering

0 → 1, 0 → 5 → 6, 2 → 3. 4는 독립. 3은 breaking ABI라 별도 커밋이며 다음 태그는 0.3.0. 권장 실행 순서: 0, 4, 2, 1, 3, 5, 6(작고 확실한 것부터, breaking은 뒤에, 낮은 우선순위 D는 마지막).

# Next Implementation Target

reflection이 유도한 모든 Go 이름을 `ZIGO021`로 검증해 `4])` 같은 이름이 생성 전에 거부되게 한다.
