# SCOPE

`src/reflect/walk.zig`, `src/gen/ir/semantic.zig`, `src/gen/validate.zig`,
`src/gen/lower.zig`, `src/gen/emit.zig`, `src/gen/abi_diff.zig`,
`examples/10-tagged-union`, `docs/.agent/design/03-lowering-rules.md`,
`docs/configuration.md`, `docs/limitations.md`.

# CONTEXT

## Current implementation and bottlenecks

`.repr = .tagged_union`은 union을 opaque handle로 내리고 variant마다 projection 심볼을
만든다. 상태 코드는 `0` mismatch, `1` success, `2` invalid handle/output, `3` panic이다.
Go는 `TryTag`/`TryAs*`와 panic하는 `Tag`/`As*`를 제공한다. 값 읽기 한 번에 최소 두 번의
native 호출이 필요하고, tag 확인과 payload 읽기 사이에 상태가 바뀔 수 있다.

## Target structure and invariants

- 값 스냅샷은 Zig union 배치를 복제하지 않는다. zigo가 소유한 `extern struct`를 정의하고
  shim이 변환해 채운다.
- 스냅샷은 반환값이 아니라 out 포인터로 전달한다. by-value struct 반환의 ABI 편차와
  purego의 struct 전달 제약을 피한다.
- 적격 조건은 "모든 variant payload가 void, bool, 정수/부동소수 스칼라, 또는 등록된 enum"이다.
  `bool`은 zigo의 다른 모든 경로와 마찬가지로 C ABI에서 `uint8_t`로 내려가고 public Go에서만
  `bool`로 복원되므로 스냅샷도 예외를 두지 않는다. 하나라도 벗어나면 opt-in을 진단으로
  거부한다. 스냅샷 구조체가 discriminant를 `tag` 멤버로 쓰므로 `tag`라는 이름의 variant도
  같은 진단으로 거부한다.
- 기존 `.repr = .tagged_union`의 동작과 심볼은 바뀌지 않는다.
