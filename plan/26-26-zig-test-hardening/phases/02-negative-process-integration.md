---
depends_on:
- "26-26-zig-test-hardening#1"
perf_phase: false
status: in-progress
---
> DONE-WHEN: dead fixture가 root `zig build test`에서 실행되고 성공 로그에 의도된 stderr noise를 남기지 않는다.
> NEXT: none

# Negative process integration

## Planned Work

- invalid-project를 child process expected-failure test에 연결한다.
- non-zero exit와 ZIGO007 stderr를 캡처해 함께 검사한다.
- CLI help/parse/stale/ABI/invalid semantic의 process exit 계약을 가능한 범위에서 고정한다.

## Done When

- dead fixture가 root `zig build test`에서 실행되고 성공 로그에 의도된 stderr noise를 남기지 않는다.
