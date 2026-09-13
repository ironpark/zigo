---
perf_phase: false
status: in-progress
---
> DONE-WHEN: `fn printAttributes(buf: []u8) ![]const u8` 모양이 래퍼 없이 바인딩된다.
> NEXT: none

# Returned slice written hint

## Planned Work

- `Written`에 `returned_slice`를 더해 declare/normalize/semantic까지 흘린다.
- ZIGO017의 조건을 갈라, `.returned_slice`는 slice(또는 error union의 slice) 반환을 요구한다.
- lowering이 `.all`과 같은 C 서명을 쓰되 shim이 반환 slice의 `.len`을 written에 넣게 한다.
- 반환 slice 자체는 Go 표면에서 사라지고 written만 남는다.
- generator case를 더해 shim과 Go 양쪽을 골든으로 고정한다.

## Done When

- `fn printAttributes(buf: []u8) ![]const u8` 모양이 래퍼 없이 바인딩된다.
- 잘못된 반환 타입에 ZIGO017이 새 문구로 뜨고 스냅샷 테스트가 그것을 담는다.
