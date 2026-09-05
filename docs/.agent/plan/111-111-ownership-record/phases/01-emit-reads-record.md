---
completed_at: "2026-09-05T07:55:53Z"
depends_on:
- "111-111-ownership-record#0"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test` 녹색, golden 44개 바이트 동일.
> NEXT: none

# Emit reads the record

## Planned Work

- `raw.writeCgoSliceReturn`과 `purego.writePuregoSliceReturn`이 `release_symbol` 대신
  `function.ownership == .buffer`의 `release`/`release_receiver`를 읽는다. materialized의 byte
  특례 호출 지점도 `buffer.element`로 통일한다.
- `raw.releaseFunction`, `common.releaseReceiverCName`을 지우고 남은 호출자를 레코드로 옮긴다.
- `common.writeOwnedHandleResult`와 public handle 결과 경로가 `ownership == .handle`의
  `child_of_receiver`, `type_name`을 읽는다. `common.ownedOpaqueReturn` 호출자 중 `AbiFn`을 가진
  곳은 레코드로 바꾼다.
- `AbiFn.release_symbol`을 삭제한다. `ret_string`, `slice_return_element`, `materialized_*`는
  호출 규약 필드라 남긴다.

## Done When

- `zig build test` 녹색, golden 44개 바이트 동일.
- `grep -rn release_symbol src/` 결과가 없다.
