# SCOPE

`src/gen/lower.zig`, `src/gen/emit.zig`, `src/gen/validate.zig`, `src/gen/abi_diff.zig`,
`src/gen/ir/abi.zig`, `src/reflect/walk.zig`, `tests/generator_cases/`,
`examples/`, `docs/.agent/design/03-lowering-rules.md`, `docs/.agent/design/00-constraints.md`,
`docs/configuration.md`, `docs/limitations.md`.

# CONTEXT

## Current implementation and bottlenecks

`value_struct`는 semantic IR, validate, abi_diff, report에는 있으나 lower와 emit에는 없다.
`ZIGO003`은 `layout == null`인 struct만 거부하므로 `extern struct`는 검증을 통과한 뒤
하강에서 패닉한다. 즉 문서가 권장하는 경로가 도달 가능한 `unreachable`이다.

## Target structure and invariants

- **zigo는 어떤 aggregate도 C 경계를 값으로 넘기지 않는다.** extern struct는 in이면
  `const T*`, out이면 `T*`로 내린다. 플랫폼별 aggregate 전달 규칙과 purego의 스칼라·포인터
  전용 raw 시그니처를 모두 피한다. tagged union snapshot이 out 포인터를 쓰는 것과 같은 원칙이다.
- Go 공개 API는 값 의미를 유지한다. 포인터화는 생성 코드 내부에서만 일어난다.
- 레이아웃은 `extern`이므로 C 헤더가 struct를 미러링하고 shim이 `comptime` size/align 단언으로
  고정한다. Zig의 미지정 배치에 의존하지 않는다.
- 필드는 재귀적으로 ABI 안전해야 한다. 스칼라, 등록된 enum, 중첩 `extern struct`만 허용한다.
