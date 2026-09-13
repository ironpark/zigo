---
completed_at: "2026-09-13T07:37:22Z"
perf_phase: false
status: done
---
> DONE-WHEN: `.{ .type = Search, .plural = "Searches" }`가 `Searches()` 접근자를 낸다.
> NEXT: none

# Session child plural

## Planned Work

- `declare.SessionChild`와 `author.SessionChild`에 `plural: ?[]const u8`을 더한다.
- `normalize`와 `reflect/walk.zig`가 그것을 `semantic.SessionChild`로 옮긴다.
- `SessionChild.plural()`을 더해 `base()` + `s`를 쓰던 두 자리를 모두 바꾼다.
- 빈 문자열이나 `base()`와 같은 값을 거절하는 컴파일 시점 검사를 둔다.

## Done When

- `.{ .type = Search, .plural = "Searches" }`가 `Searches()` 접근자를 낸다.
- `Add<Base>`는 `base()`를 그대로 쓰고, plural을 쓰지 않은 기존 세션의 골든이 변하지 않는다.
