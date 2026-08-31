# GOALS

## Problem and the end result from the user's point of view

Ubuntu CI에서 event-queue cgo layout test가 `offsetof_*` undefined reference로 링크에 실패한다.
layout 값을 외부 symbol이 아닌 C compile-time constant로 제공해 Linux와 macOS에서 같은
테스트가 링크·실행되게 한다.

## Measurable goals

- cgo helper가 `offsetof_*` 외부 data symbol을 요구하지 않는다.
- event-queue Go test와 전체 Zig test가 성공한다.
- CI와 동일한 format check가 성공한다.

## Supported scope and non-goals

event-queue의 C header layout test helper와 관련 검증만 범위다. ABI, 생성 public API와
GNU-stack 경고를 만드는 Zig object 형식은 변경하지 않는다.

## Reference source / commit / license

Ubuntu linker 오류와 현재 `examples/07-event-queue/go/bridge/cgo/cheader/cheader.go`를
기준으로 한다.

## Completion criteria for the whole plan

외부 offset symbol이 제거되고 format, event-queue Go test와 Zig test가 통과하며 변경과
plan 상태가 커밋되어 있다.
