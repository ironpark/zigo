---
depends_on:
- "26-26-zig-test-hardening#2"
perf_phase: false
status: in-progress
---
> DONE-WHEN: parser 실패 공간과 핵심 lowering role이 구조체 수준의 unit test로 고정된다.
> NEXT: none

# Parser and lowering unit coverage

## Planned Work

- malformed/unknown/missing/default/nested semantic parse와 parser OOM을 검증한다.
- receiver, out slice, return slice, error payload, usize/isize, enum tag의 ABI lowering을 직접 검증한다.
- test discovery가 새 test를 정확히 한 번 실행하도록 build module을 조정한다.

## Done When

- parser 실패 공간과 핵심 lowering role이 구조체 수준의 unit test로 고정된다.
