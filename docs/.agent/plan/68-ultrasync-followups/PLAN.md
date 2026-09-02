---
depends_on:
- out-slice-written
- metadata-and-godoc-fidelity
description: 패키지 doc 소스, 잉여 KeepAlive 제거, .return의 _written 제거(ABI), LockOSThread 비용 측정과 조건부 대체
plan_status: in-progress
registered_at: "2026-09-02T06:10:00Z"
---
> NEXT: 패키지 doc fallback을 `bindings.zig`에서 루트 모듈 `//!`로 옮긴다. ([Phase 0](phases/00-package-doc-source.md))

# Phases

- [ ] [Phase 00: 패키지 doc fallback을 루트 모듈 `//!`로](phases/00-package-doc-source.md)
- [ ] [Phase 01: handle 획득 경로의 `KeepAlive` 제거](phases/01-drop-keepalive.md)
- [ ] [Phase 02: `.return` out 슬라이스에서 `_written` 제거](phases/02-return-drops-written.md)
- [ ] [Phase 03: `LockOSThread` 비용 측정](phases/03-lock-os-thread-benchmark.md)
- [ ] [Phase 04: 패닉 메시지 전달을 스레드 고정 없는 ABI로](phases/04-panic-message-abi.md)

# Shared Verification

- `zig build test --summary all`, `zig fmt --check build.zig src tests examples`.
- 예제 루프 + purego 4개(04/07/08 `purego-go`·`purego-go-check`, 10 `-Dpurego=true`).
- 골든 갱신은 실패 출력의 actual 경로를 `zig build snapshot -- <expected> <actual> --update-snapshots`에.
- 벤치마크: `go test -bench . -benchmem -count=5` 로 안정된 수치.

# Decisions That Constrain Ordering

0, 1, 2는 독립이라 병행 가능하며 각각 별도 커밋. 3은 1 뒤(잉여 defer가 벤치마크 수치를 오염시키지 않게). 4는 3의 결과에 조건부. 2와 4는 ABI breaking이므로 다음 태그는 0.2.0이어야 한다 — 태그는 별도 지시.

# Next Implementation Target

패키지 doc fallback을 `bindings.zig`에서 루트 모듈 `//!`로 옮긴다.
