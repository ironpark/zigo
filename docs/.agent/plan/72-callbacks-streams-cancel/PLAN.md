---
completed_at: "2026-09-02T11:35:57Z"
depends_on:
- io-stream-params
description: callback의 Go error 표면화, []byte 무콜백 Reader, Zig가 내주는 스트림, 취소 규약
plan_status: done
registered_at: "2026-09-02T07:40:11Z"
---
> NEXT: 70의 스트림 ABI에 슬라이스 변형을 넣어 `[]byte` 입력이 콜백 없이 넘어가게 한다. ([Phase 1](phases/01-bytes-reader-fast-path.md))

# Phases

- [x] [Phase 00: callback의 Go error 표면화](phases/00-callback-go-error.md)
- [x] [Phase 01: `[]byte` 무콜백 Reader 경로](phases/01-bytes-reader-fast-path.md)
- [x] [Phase 02: Zig가 내주는 스트림](phases/02-stream-returns.md)
- [x] [Phase 03: 취소 규약](phases/03-cancellation.md)

# Shared Verification

- `zig build test --summary all`, `zig fmt --check build.zig src tests examples`.
- 예제 루프 + purego. 골든 갱신은 실패 출력의 actual 경로 사용.

# Decisions That Constrain Ordering

0, 2, 3은 독립. 1은 70의 ABI와 결합되므로 70 상태에 따라 70에 합치거나 70 직후 진행. 권장: 1(70과 함께) → 0 → 2 → 3.

# Next Implementation Target

70의 스트림 ABI에 슬라이스 변형을 넣어 `[]byte` 입력이 콜백 없이 넘어가게 한다.
