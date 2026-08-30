---
perf_phase: false
status: in-progress
---
> DONE-WHEN: 8개 example의 test step과 CI 연결이 존재하고 14/14 테스트가 통과한다.
> NEXT: none

# Example test discovery and CI

## Planned Work

- test step이 없는 5개 example에 module-aware Zig test step을 추가한다.
- CI example loop가 8개 `zig build test --summary all`을 실행하도록 한다.
- 14개 example Zig 테스트의 실제 실행을 확인한다.

## Done When

- 8개 example의 test step과 CI 연결이 존재하고 14/14 테스트가 통과한다.
