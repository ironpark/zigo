---
completed_at: "2026-09-12T07:35:56Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test`가 통과한다.
> NEXT: none

# 필수 필드와 선택 필드를 나누는 계약

## Planned Work

- `src/gen/validate/functions.zig`의 `.options` 검사에서 필드별 기본값 요구를 없앱니다.
  기본값을 가진 필드가 하나도 없을 때만 `ZIGO061`을 내고, hint는 `.flatten`을 안내합니다.
  필드가 비어 있는 경우의 진단은 그대로 둡니다.
- 그 진단을 단언하는 `functions.zig`의 테스트를 새 계약에 맞게 고칩니다. 기본값 없는 필드와
  있는 필드를 섞은 선언이 진단을 내지 않는 것, 전부 기본값이 없으면 `ZIGO061`이 나는 것을
  각각 확인합니다.
- `src/gen/validate/names.zig`의 옵션 이름 충돌 검사가 `With*` 이름을 만들 때 기본값이 있는
  필드만 보도록 좁힙니다. 위치 인자가 되는 필드는 `With*`를 만들지 않으므로 충돌의 원인이
  될 수 없습니다.
- `src/gen/abi_diff.zig`의 `GoParams`가 옵션 매개변수를 하나의 토큰으로 세는 자리에서,
  기본값 없는 필드를 각각 Go 토큰으로 내보내도록 고칩니다. 혼합 선언에서 위치 인자가
  늘거나 타입이 바뀌는 것은 Go 표면의 breaking change이고 비교가 그것을 보아야 합니다.
- `src/gen/abi_diff.zig`의 테스트에 혼합 선언 두 개(필수 필드 타입이 다른 경우, 필수 필드가
  옵션 필드로 바뀐 경우)를 넣어 비교 결과를 고정합니다.
- `docs/reference/diagnostics.md`의 `ZIGO061` 행을 새 조건과 hint로 맞춥니다.

## Done When

- `zig build test`가 통과한다.
- 기본값 없는 필드와 있는 필드를 섞은 `.options` 선언이 진단 없이 통과하고, 모든 필드에
  기본값이 없는 선언은 `ZIGO061`과 `.flatten` hint를 받는다.
- `abi_diff` 테스트가 혼합 선언의 위치 인자 변화를 Go 표면 변경으로 보고한다.
- `docs/reference/diagnostics.md`의 `ZIGO061` 설명이 코드와 같은 조건을 말한다.
