---
perf_phase: false
status: in-progress
---
> DONE-WHEN: `zig build test` 녹색, golden 44개와 예제 `semantic.json` 바이트 동일.
> NEXT: none

# IR and reflector

## Planned Work

- `semantic.zig`에 `Interface` 구조체와 `Semantic.interfaces: ?[]const Interface = null`을 추가한다.
  JSON round trip 테스트와 "등록하지 않으면 필드가 나타나지 않는다" 테스트를 쓴다.
- `walk.zig` `reflect`가 `.interfaces`를 읽는다. 각 항목의 `.types`는 `.types` 등록 항목의 `.type`과
  comptime으로 대조해 등록 이름으로 바꾼다. 등록되지 않은 타입, `.repr != .opaque`인 타입, 빈
  `.methods`, `.name` 누락은 `@compileError`다. `.closer` 기본값 true, `.doc` 선택.
- `.packages`가 있으면 인터페이스의 `package`는 첫 타입의 패키지를 따른다(패키지 불일치는 phase 1의
  검증이 잡는다).
- walk 테스트: 두 opaque 타입과 인터페이스 하나를 등록한 문서가 `interfaces[0]`에 이름, 메서드,
  타입 이름 순서를 그대로 담는다.

## Done When

- `zig build test` 녹색, golden 44개와 예제 `semantic.json` 바이트 동일.
- 위 테스트들이 통과한다.
