---
depends_on:
- "200-zigo-gostty-gaps#2"
perf_phase: false
status: in-progress
---
> DONE-WHEN: 바인딩이 쓴 멤버 doc이 Zig 소스의 `///`를 이긴다.
> NEXT: none

# Member doc overrides

## Planned Work

- `declare.ValueField`에 `doc`을 더하고 `semantic`을 선택 항목으로 낮춘다.
- `declare.Enum`에 멤버별 doc을 적는 `fields: []const EnumField`를 더한다.
- 리플렉터가 두 오버라이드를 `fields[].doc`에 싣고, 소스에서 채운 값보다 우선시킨다.
- 존재하지 않는 멤버 이름을 적으면 컴파일 시점에 거절한다.

## Done When

- 바인딩이 쓴 멤버 doc이 Zig 소스의 `///`를 이긴다.
- 기존 `.{ .name = ..., .semantic = ... }` 표기가 그대로 컴파일된다.
