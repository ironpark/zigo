# SCOPE

- `receiverVariableAlloc`이 함수의 Go 파라미터 이름 목록을 받아 충돌하지 않는 이름을 고른다. 규칙: snake 이름의 접두 길이를 1부터 늘려가며 첫 비충돌 후보, 전부 충돌하면 `recv`. 메서드 헤더·검사·호출·release 등 receiver 이름을 쓰는 모든 emit 지점(cgo·purego)이 같은 함수를 쓴다.
- `writeCheckedErrorReturn`이 optional payload(및 optional을 감싼 error union)에서 `zero, false, err`를 쓴다. `writePublicZeroValue`가 optional의 zero를 어떻게 적는지 확인해 panic 경로(`code != 0`)와 같은 형태로 맞춘다.
- 골든 케이스 `receiver_name_clash`(또는 기존 케이스 확장)와 `optional_return_checks`: handle 검사 + narrow int 범위 검사 + optional handle 파라미터를 각각 optional 반환과 조합.
- 예제(03-opaque 또는 09)에 `t` 파라미터 메서드와 optional 반환 메서드를 추가하고 Go 테스트에서 호출.
- 문서: `docs/generated-code.md`(receiver 이름 규칙), `docs/limitations.md`(지역 이름 충돌 항목 추가), CHANGELOG.

# CONTEXT

## Current implementation and bottlenecks

- `receiverVariableAlloc`은 receiver 타입의 snake 이름 첫 글자만 돌려주고 파라미터 이름을 보지 않는다.
- `writeCheckedErrorReturn`은 constructor면 `nil, err`, void면 `err`, 그 외 `zero, err`를 쓴다. optional payload는 Go 시그니처가 `(T, bool, error)`인데 presence 값이 빠진다. handle 검사와 range 검사가 같은 함수를 쓰므로 둘 다 깨진다.
- panic 경로(`code != 0`)는 별도 writer가 presence를 넣는다.

## Target structure and invariants

- receiver 이름 선택은 결정적이며 파라미터 이름만 입력으로 받는다(순서 무관). 충돌이 없으면 현재와 같은 첫 글자라 기존 생성물이 바뀌지 않는다.
- 검사 실패 경로의 반환 형태는 panic 경로와 항상 같은 개수·순서다. 한 곳에서 "실패 시 반환 목록"을 만들어 두 경로가 공유하는 것을 권장한다.
- 파라미터 이름이 `ptr`, `err`, `code`, `result` 등 생성 코드의 지역 이름과 겹치는 경우는 이번에 고치지 않되, 확인된 목록을 limitations에 적는다.
