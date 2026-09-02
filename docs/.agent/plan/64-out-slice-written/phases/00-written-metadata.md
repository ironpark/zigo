---
completed_at: "2026-09-02T04:34:14Z"
perf_phase: false
status: done
---
> DONE-WHEN: `.written = .return`이 `semantic.json`에 `"written": "return"`으로 나오고, 옛 JSON이 그대로 읽힌다.
> NEXT: none

# `.written` 메타데이터와 진단, abi_diff

## Planned Work

- `src/gen/ir/semantic.zig`: `pub const Written = enum { all, @"return" }`, `Parameter.written: Written = .all`, JSON 직렬화·역직렬화(필드 부재 → `.all`).
- `src/reflect/walk.zig`: `param_meta`의 `written` 필드 반영, 골든 JSON(`walk.zig:692-745`) 갱신.
- `src/gen/validate.zig`: `ZIGO017` — `.written`이 `.out`이 아닌 파라미터에 붙거나, `.return`인데 반환 payload가 `usize`가 아니면 거부. 메시지·힌트를 기존 코드 양식에 맞춘다.
- `src/gen/abi_diff.zig`: `signatureEqual`에서 `written`을 비교하지 않고, 별도 `writtenEqual`로 차이를 `.compatible`로 보고.
- 단위 테스트: 반영, 직렬화 왕복, ZIGO017 두 경우, abi_diff compatible 분류.

## Done When

- `.written = .return`이 `semantic.json`에 `"written": "return"`으로 나오고, 옛 JSON이 그대로 읽힌다.
- 반환이 `usize`가 아닌 fixture와 `.in` 파라미터에 붙인 fixture가 `ZIGO017`로 거부되는 테스트 통과.
- `.all` → `.return` 이 `abi_diff`에서 non-breaking으로 보고되는 테스트 통과.
