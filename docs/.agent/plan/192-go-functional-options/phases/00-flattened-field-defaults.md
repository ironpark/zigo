---
perf_phase: false
status: in-progress
---
> DONE-WHEN: 선택 필드의 기본값이 `semantic.json`에 나타나고, 기본값이 없는 필드는 키가 없다.
> NEXT: none

# 기본값을 IR과 reflection에 싣기

## Planned Work

- `semantic.FlattenedField`에 `default: ?Value = null`을 추가한다. 값 표현은
  `.flatten`이 허용하는 타입만 담으면 되므로 bool, 정수, 실수, enum 태그 이름을
  구분하는 최소 union으로 둔다.
- `src/reflect/walk.zig`의 `reflectFlattenedFields`에서 선택 필드의
  `default_value_ptr`를 comptime에 읽어 기록한다. 기본값이 없으면 `null`.
- optional 스칼라 필드의 `null` 기본값과 "기본값 없음"을 문서에서 구분한다.
- `ir_version`은 2로 둔다. `migrate`에 항목을 추가하지 않는다는 판단을 주석으로 남긴다.
- serialize/parse 왕복 테스트와 reflection 단위 테스트를 추가한다.

## Done When

- 선택 필드의 기본값이 `semantic.json`에 나타나고, 기본값이 없는 필드는 키가 없다.
- `zig build test`가 통과하고 기존 골든 중 `.flatten`을 쓰는 문서만 `default` 키가
  늘어난다.
- `ir_version`이 여전히 2이고 기존 문서가 그대로 읽힌다.
