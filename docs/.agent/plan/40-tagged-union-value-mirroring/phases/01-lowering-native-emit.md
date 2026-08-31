---
depends_on:
- "40-tagged-union-value-mirroring#0"
perf_phase: false
status: planned
---
> DONE-WHEN: generator case 골든 트리에 헤더·shim 산출물이 고정된다.
> NEXT: none

# Lowering and native emitters

## Planned Work

- lower에서 값 스냅샷 union마다 `AbiFn` 하나(`zg_<type>_snapshot(const T*, snapshot* out)`)를
  만들고 스냅샷 struct 레이아웃을 ABI IR에 담는다.
- C 헤더에 `extern struct` 스냅샷 타입과 tag 상수를 낸다. 패딩은 명시한다.
- Zig shim이 active tag를 읽어 스냅샷을 채우고, 기존 projection과 같은 상태 코드를
  반환하도록 한다.

## Done When

- generator case 골든 트리에 헤더·shim 산출물이 고정된다.
- 스냅샷 호출이 invalid handle과 panic을 기존 상태 코드로 보고한다.
