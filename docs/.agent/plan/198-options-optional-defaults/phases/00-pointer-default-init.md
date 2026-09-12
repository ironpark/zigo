---
perf_phase: false
status: in-progress
---
> DONE-WHEN: `zig build test`가 통과한다.
> NEXT: none

# 포인터 기본값을 낼 수 있는 초기화

## Planned Work

- `renderFunctionOptionsInit`이 optional 필드의 null 아닌 기본값을 만나면 `cfg` 앞에
  `var zigoDefault<Field> <T> = <값>`을 쓰고 필드 값으로 `&zigoDefault<Field>`를 쓰도록
  고칩니다. 이름은 필드의 Go 이름에서 만들고, 필드 이름이 유일하므로 함수 안에서 충돌하지
  않습니다.
- `formatGoDefaultAlloc`은 값 표현만 계속 맡습니다. 포인터가 필요한지 판단하는 자리는
  초기화 한 곳입니다.
- optional의 child 타입 spelling은 `writePublicGoType`을 그대로 씁니다. enum과 실수, bool
  기본값이 같은 경로로 나옵니다.
- `public.zig`에 단위 테스트를 더할 수 없으면(렌더링이 program 전체를 요구하면) golden으로
  덮는다는 것을 phase 1에서 확인합니다.

## Done When

- `zig build test`가 통과한다.
- optional 필드의 null 아닌 기본값이 `var` + 주소로 방출되고, `= null`과 non-optional
  필드의 방출은 바뀌지 않는다.
