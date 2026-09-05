# ABI 하강 규칙

하강은 Zig 타입을 C에서 호출할 수 있는 표현으로 바꾸면서 Go의 타입과 수명 정책을
결정하는 단계입니다. 구현은 [lower.zig](../../../src/gen/lower.zig), 출력 계약의 상세는
[생성 ABI와 메타데이터](../../generated-abi.md)에 있습니다.

## 기본값과 등록 타입

| Zig 표현 | C 경계 | 공개 Go 표현 |
|---|---|---|
| 지원되는 고정 폭 정수 | 대응 정수 | 대응 Go 정수 |
| `usize` / `isize` | 포인터 크기 정수 | `uint` / `int` |
| `bool` | 8비트 값 | `bool` |
| `f32` / `f64` | `float` / `double` | `float32` / `float64` |
| 등록 enum | 기반 정수 | 이름 있는 정수 타입과 상수 |
| 지원되는 값 struct | C 호환 필드 표현 | Go struct |
| opaque 객체 | 포인터 handle | 수명이 관리되는 Go 객체 |
| materialized 결과 | 직렬화 버퍼 | 디코딩된 Go 값 트리 |

비표준 폭 정수, packed struct와 enum에는 추가 조건이 있습니다. 지원하지 않는 표현을
무조건 cast하지 않고 검증 단계에서 거부합니다. 정확한 조건과 명시적 변환 선택은
[값 타입과 결과 트리](../../bindings-types.md)를 참고하세요.

## 함수와 오류

receiver와 주입 파라미터를 구분한 후 Go에서 전달할 인자만 공개합니다.
allocator와 `std.Io` 주입은 shim 내부에서 해결하므로 공개 C·Go 인자로 추가하지 않습니다.

Zig error union은 C에서 상태 코드와 성공 payload의 출력 인자로 분리합니다. Go에서는
성공값 뒤에 `error`를 붙입니다. 성공 payload가 없으면 `error`만 반환합니다.
handle 사용이나 콜백 오류 때문에 원래 Zig 함수보다 Go 반환 오류가 추가될 수도 있습니다.

생성 가능한 `Must` 변형과 panic 경계는 ABI IR의 결정에 따릅니다. 모든 함수에 동일한
오류 시그니처나 복구 정책을 가정하지 않습니다.

## 문자열·slice·optional

일반 slice는 포인터와 길이로 분해합니다. `c_string`은 NUL 종료 포인터이며 별도 길이
인자가 없습니다. Go에서 복사하거나 빌리는 방식은 원소 타입, 방향과 소유권에 따라 달라집니다.

| 경우 | 공개 Go 형태 |
|---|---|
| 일반 slice 인자 | `[]T` |
| 문자열 의미의 byte 인자 | `string` |
| optional 값 인자 | `*T` |
| optional slice·문자열 인자 | `*[]T` / `*string` |
| optional 값 반환 | `(T, bool)` |
| optional + error union 반환 | `(T, bool, error)` |

optional의 존재 여부와 payload 값은 별개입니다. 값 인자는 NULL 가능 포인터를 사용하고,
optional slice·문자열은 slice 포인터로 부재를 표현합니다. Go 반환값의 `bool`은 존재 여부입니다.

out slice의 `written = .all`은 별도 작성 개수 출력 인자를 사용합니다.
`written = .@"return"`은 `usize` 반환 payload를 개수로 사용합니다. 이 선택을 바꾸면
C 시그니처도 달라집니다. 작성 개수는 전체 native 쓰기를 롤백하는 기능이 아닙니다.

사용 예제와 release 선언은 [문자열과 버퍼](../../bindings-buffers.md)를 참고하세요.

## 결과 소유권

| 정책 | 생성 코드의 책임 |
|---|---|
| borrowed handle view | owner 관계와 사용 가능 상태 검사 |
| borrowed 복사 결과 | Go 소유 값으로 복사, native 결과는 해제하지 않음 |
| caller-owned handle | 객체 wrapper와 종료 경로 생성 |
| caller-owned buffer | Go 값으로 복사·디코딩 후 연결된 release 호출 |
| materialized buffer | 버퍼 검증·디코딩과 release 경로 적용 |

buffer의 release는 lowering에서 한 번 연결합니다. 오류로 결과를 받지 못한 경로와,
성공적으로 받은 결과를 Go로 옮기는 경로를 구분해야 합니다. destructor와 release는
교환 가능한 개념이 아닙니다.

handle의 종료는 진행 중인 호출, borrowed view와 부모·자식 관계를 고려합니다.
공개 Go 객체가 단순한 native 포인터 포장이라는 가정으로 emitter를 작성하지 않습니다.
[객체 수명](../../bindings-handles.md)에 사용자가 관찰하는 동작이 있습니다.

## 콜백·스트림·취소

콜백 함수와 userdata는 함께 낮춥니다. Go 콜백은 정수 토큰으로 등록하며, borrowed 토큰은
호출 종료 시, retained 토큰은 owner 종료·생성 실패 경로에서 정리합니다.
purego의 버전별 진입점과 float 전달 규칙은
[공유 라이브러리 계약](06-shared-library-contract.md)을 참고하세요.

`io.Writer`·`io.Reader`와 `context.Context`는 명시적인 스트림·취소 메타데이터에 따라
adapter를 생성합니다. 임의의 `std.Io` 사용이나 모든 Zig 함수가 자동으로 취소 가능해지는
것은 아닙니다. 사용 계약은 [스트림과 취소](../../bindings-streams.md)에 있습니다.

## Tagged union과 인터페이스

등록한 tagged union은 선택한 projection·snapshot·값 전달 방식으로 낮춥니다. union의
Zig 메모리 배치를 Go가 직접 읽지 않습니다. 인터페이스는 명시 등록한 메서드 집합에 대한
Go 표현이며 임의의 comptime generic 함수를 자동 인스턴스화하는 기능이 아닙니다.

자세한 선언은 [Tagged union](../../bindings-unions.md)과
[객체 수명](../../bindings-handles.md)을 참고하세요.

## 규칙 변경 시 검증

semantic 검증, ABI IR 테스트와 출력 스냅샷을 함께 갱신합니다. 같은 함수의 C 헤더,
Zig shim과 두 Go raw 백엔드가 같은 ABI를 사용하는지 확인하고, 수명이 달라지는 경우에는
실패 경로를 포함한 Go 통합 테스트를 추가합니다.
