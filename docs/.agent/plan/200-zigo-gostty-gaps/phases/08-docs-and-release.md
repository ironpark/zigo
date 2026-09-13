---
depends_on:
- "200-zigo-gostty-gaps#0"
- "200-zigo-gostty-gaps#1"
- "200-zigo-gostty-gaps#2"
- "200-zigo-gostty-gaps#3"
- "200-zigo-gostty-gaps#4"
- "200-zigo-gostty-gaps#5"
- "200-zigo-gostty-gaps#6"
perf_phase: false
status: planned
---
> DONE-WHEN: `zig build test`가 통과하고 문서가 실제 동작과 일치한다.
> NEXT: none

# Docs, changelog and release

## Planned Work

- 새 기능마다 해당 reference/authoring 문서를 고친다.
- 진단 문서에 바뀐 ZIGO017 문구와 새 진단을 싣는다.
- CHANGELOG에 릴리즈 항목을 적고 버전을 올린다.
- 실린 것과 미룬 것을 릴리즈 노트에 구분해 적는다.

## Done When

- `zig build test`가 통과하고 문서가 실제 동작과 일치한다.
- 버전이 올라간 릴리즈 커밋이 있다.
