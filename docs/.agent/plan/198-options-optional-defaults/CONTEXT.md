# SCOPE

`src/gen/emit/public.zig`, `tests/generator_cases/options_required_fields`, `CHANGELOG.md`.

# CONTEXT

## Current implementation and bottlenecks

`renderFunctionOptionsInit`은 필드마다 `formatGoDefaultAlloc`의 결과를 구조체 리터럴에
그대로 씁니다. 그 함수는 Zig 기본값을 Go 리터럴로 옮길 뿐 필드의 Go 타입을 보지 않습니다.
optional 필드의 Go 타입은 포인터이므로 `.null`이 아닌 기본값에서는 타입이 맞지 않습니다.

Go에는 리터럴의 주소를 바로 쓸 방법이 없어서 표현식 하나로는 끝나지 않습니다. 초기화 앞에
변수를 하나 두고 그 주소를 넣어야 합니다.

## Target structure and invariants

- optional 필드의 기본값이 `.null`이면 지금처럼 `nil`입니다.
- optional 필드의 기본값이 값이면 `cfg` 앞에 `var zigoDefault<Field> <T> = <값>`을 쓰고
  필드에 `&zigoDefault<Field>`를 넣습니다. `T`는 optional의 child가 공개 Go에서 갖는
  타입이고, 그 spelling이 enum·bool·실수 기본값까지 한 줄로 담습니다.
- 이 지역 변수는 `cfg`와 수명이 같고 호출 동안만 삽니다. `With*`가 그 필드를 덮어쓰면
  변수는 쓰이지 않을 뿐 문제가 되지 않습니다.
- non-optional 필드와 기본값 없는 필드의 출력은 한 글자도 바뀌지 않습니다.
