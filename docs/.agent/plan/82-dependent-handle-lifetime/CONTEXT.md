# SCOPE

- 함수 메타 `.child_of_receiver = true`(receiver 있는 생성자에만 허용, 아니면 진단).
- Go: 자식 handle에 `parent *Parent` 필드, 생성 시 부모 `children++`, 자식 `Close()`에서 `children--`. 부모 `Close()`는 `children != 0`이면 `ErrHandleInUse` 반환. 부모 poison 전파는 기존 projection의 parent 패턴을 따른다.
- semantic.json: 생성자 함수에 `child_of_receiver: true`가 있을 때만 필드가 나타난다. abi_diff는 Go 표면 변화(Close가 실패할 수 있음)를 non-breaking으로 본다.
- 예제·문서·CHANGELOG.

# CONTEXT

## Current implementation and bottlenecks

- handle은 `mu`, `active`, `poison`, `closed` 상태를 가지며 `zigoCheckedPointer`로 획득한다. projection은 `parent`를 잡고 부모의 획득에 실패하면 오류를 돌려준다.
- receiver 생성자는 부모와 자식 사이에 아무 참조도 남기지 않는다.

## Target structure and invariants

- 구현 결정: 최초 계획의 "strong 참조가 아니라 카운트만"이라는 문구와 달리, 사용자 요구대로
  자식은 `parent *Parent` strong 참조와 카운트를 함께 가진다. 참조는 부모의 GC를 막고
  projection과 같은 acquire/poison 전달에 쓰이며, 카운트는 부모 `Close`를 거부한다.
- 동시성 결정: constructor는 native 호출 뒤가 아니라 receiver 획득과 같은 lock 안에서 자식
  카운트를 예약한다. 성공 시 예약을 자식에게 넘기고 실패 시 되돌려, constructor와 부모
  `Close`가 경합할 때 해제된 부모 뒤에 자식이 만들어지는 틈을 없앤다.
- 자식이 닫히지 않은 채 GC되는 경우는 다루지 않는다(문서화).
