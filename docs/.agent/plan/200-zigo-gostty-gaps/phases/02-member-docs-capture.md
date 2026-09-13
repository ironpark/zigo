---
perf_phase: false
status: in-progress
---
> DONE-WHEN: `/// 0xRRGGBB.`가 붙은 Zig 필드가 생성된 Go에서 같은 문장을 단다.
> NEXT: none

# Member docs from source

## Planned Work

- `semantic.TypeField`에 `doc: ?[]const u8`을 더한다.
- `names.zig`의 소스 스캔이 컨테이너 멤버의 `///`를 수집해 lexical path로 등록 타입에
  맞추고, 비어 있는 `fields[].doc`만 채운다. 후보가 둘 이상이면 채우지 않는다.
- enum 상수와 값 struct 필드의 에미터가 doc이 있으면 그것을 쓰고, 없을 때만 기존
  플레이스홀더 문장을 쓴다.
- 필드 문서가 붙은 generator case를 하나 더해 골든으로 고정한다.

## Done When

- `/// 0xRRGGBB.`가 붙은 Zig 필드가 생성된 Go에서 같은 문장을 단다.
- 문서가 없는 멤버는 기존 문장을 그대로 유지해 나머지 골든이 변하지 않는다.
