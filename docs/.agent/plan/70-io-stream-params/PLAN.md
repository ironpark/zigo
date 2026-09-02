---
depends_on:
- third-party-library-fit
description: "*std.Io.Writer / *std.Io.Reader 파라미터를 Go io.Writer / io.Reader로 연동"
plan_status: in-progress
registered_at: "2026-09-02T07:33:36Z"
---
> NEXT: `*std.Io.Writer`/`*std.Io.Reader` 파라미터를 반영·직렬화·검증하는 IR을 만든다. ([Phase 0](phases/00-stream-ir.md))

# Phases

- [ ] [Phase 00: 스트림 파라미터 인식과 IR](phases/00-stream-ir.md)
- [ ] [Phase 01: shim 어댑터와 lowering](phases/01-shim-adapters.md)
- [ ] [Phase 02: Go 트램폴린과 공개 래퍼](phases/02-go-side.md)
- [ ] [Phase 03: 예제, 테스트, 문서](phases/03-example-and-docs.md)

# Shared Verification

- `zig build test --summary all`, `zig fmt --check build.zig src tests examples`.
- 예제 루프 + purego(04/07/08 `purego-go`·`purego-go-check`, 10 `-Dpurego=true`, 11은 구성 시 결정).
- 골든 갱신은 실패 출력의 actual 경로를 `zig build snapshot -- <expected> <actual> --update-snapshots`에.

# Decisions That Constrain Ordering

0 → 1 → 2 → 3 직렬. 계획 69가 `walk.zig`·`validate.zig`·`emit.zig`를 수정 중이므로 69 완료 뒤 시작한다. 진단 코드 번호는 69가 쓴 다음 번호를 시작 시점에 확인한다. ABI 추가(새 kind)라 기존 바인딩은 불변이며 breaking 아님.

# Next Implementation Target

`*std.Io.Writer`/`*std.Io.Reader` 파라미터를 반영·직렬화·검증하는 IR을 만든다.
