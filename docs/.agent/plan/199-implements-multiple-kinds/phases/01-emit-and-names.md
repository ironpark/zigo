---
depends_on:
- "199-implements-multiple-kinds#0"
perf_phase: false
status: planned
---
> DONE-WHEN: `zig build test`가 갱신된 골든과 함께 통과한다.
> NEXT: none

# 여러 래퍼 방출과 이름 검사

## Planned Work

- `src/gen/plugins/implements.zig`의 검증이 kind마다 돌도록 고칩니다. 진단 메시지는 어느
  kind가 맞지 않는지 계속 이름으로 말합니다.
- `methodHook`이 나열된 순서대로 래퍼를 모두 냅니다. counting stream 헬퍼 판단도 목록을
  보게 합니다.
- `src/gen/validate/names.zig`의 래퍼 이름 충돌 검사가 한 함수의 여러 래퍼와, 다른 함수의
  래퍼들까지 모두 비교하도록 고칩니다.
- `src/gen/validate/functions.zig`에서 `.implements`의 존재를 묻는 자리를 목록에 맞춥니다.
- `tests/generator_cases/implements_std{,_purego}`에 kind 두 개를 가진 메서드를 더하고
  골든을 갱신합니다. 기존 메서드의 출력이 바뀌지 않는지 diff로 확인합니다.

## Done When

- `zig build test`가 갱신된 골든과 함께 통과한다.
- 한 메서드에서 나온 두 래퍼가 골든에 함께 나타나고, 각각 같은 공개 메서드를 부른다.
- 래퍼 이름이 이미 있는 Go 메서드와 겹치면 `ZIGO024`가 난다.
- 기존 단수 선언의 골든이 바뀌지 않는다.
