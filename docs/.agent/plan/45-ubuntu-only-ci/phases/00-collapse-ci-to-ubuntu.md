---
perf_phase: false
status: in-progress
---
> DONE-WHEN: workflow에 `macos`, `windows`, ARM runner 또는 `${{ matrix.os }}` 참조가 없다.
> NEXT: none

# Collapse CI to Ubuntu

## Planned Work

- test와 purego job의 matrix를 제거하고 `runs-on: ubuntu-latest`로 고정한다.
- purego library suffix를 `.so`로 고정하고 플랫폼 matrix 전제의 주석을 갱신한다.
- Windows 전용 compile job을 삭제하고 workflow 및 핵심 검증 명령을 확인한다.

## Done When

- workflow에 `macos`, `windows`, ARM runner 또는 `${{ matrix.os }}` 참조가 없다.
- YAML parse, Zig test와 대표 purego 검증이 성공한다.
