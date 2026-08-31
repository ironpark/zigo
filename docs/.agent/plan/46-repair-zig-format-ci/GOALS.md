# GOALS

## Problem and the end result from the user's point of view

Ubuntu CI의 `zig fmt --check build.zig src tests examples`가 `src/gen/emit.zig`에서 실패한다.
해당 파일을 정규 Zig 형식으로 갱신해 CI 포맷 gate를 복구한다.

## Measurable goals

- 전체 저장소 대상 `zig fmt --check`가 성공한다.
- 포맷 변경 후 Zig test가 모두 성공한다.

## Supported scope and non-goals

`src/gen/emit.zig`의 기계적 포맷과 검증만 범위다. 동작과 공개 API는 변경하지 않는다.

## Reference source / commit / license

현재 main과 Zig 0.16.0 formatter를 기준으로 한다.

## Completion criteria for the whole plan

포맷과 test 명령이 성공하고 변경 및 plan 상태가 커밋되어 있다.
