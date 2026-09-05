# 지원 범위와 제한사항

zigo에 노출할 API를 설계할 때 확인하는 문서입니다. 먼저 타입의 표현을 고르고,
객체·버퍼의 수명과 실패 처리 조건을 확인하세요. 선언 예제는 [바인딩 가이드](bindings.md)에,
`ZIGO...` 오류별 해결 방법은 [생성기 진단](diagnostics.md)에 있습니다.

## 먼저 확인할 조건

- 상태를 가진 객체는 handle로, 단순 데이터는 값 타입으로 노출합니다.
- 반환 slice는 Go 소유 사본입니다. native 메모리를 그대로 참조하는 slice view는 제공하지 않습니다.
- 소유한 handle은 명시적으로 `Close`합니다. GC에 의한 정리는 실행 시점을 보장하지 않습니다.
- 동시 호출의 안전성은 원래 Zig 라이브러리의 계약을 따릅니다.
- Zig panic을 오류로 받았더라도 해당 객체를 정상 상태로 간주하면 안 됩니다.

처음부터 모든 제한을 읽을 필요는 없습니다. 새 API를 설계할 때는 [타입과 ABI](#zig-타입과-abi),
객체를 오래 보관하거나 공유할 때는 [수명과 동시 호출](#객체-수명과-동시-호출),
실패 후 계속 실행해도 되는지 판단할 때는 [오류와 panic](#오류와-panic)을 먼저 확인하세요.

## 지원 환경

| 항목 | 지원 범위 |
|---|---|
| Zig / Go | Zig 0.16.0, Go 1.24 이상 |
| cgo | macOS/Linux amd64·arm64, Windows amd64 GNU ABI |
| purego | macOS/Linux/Windows amd64·arm64 |
| Windows cgo 컴파일러 | `CC="zig cc"`; 별도 mingw-w64 설치 불필요 |
| 미지원 | MSVC ABI, 32비트 타깃, 모바일 |
| purego 의존성 | `github.com/ebitengine/purego v0.10.2`로 생성·검증 |

cgo는 `CGO_ENABLED=1`과 C 컴파일러가 필요합니다. purego는 `CGO_ENABLED=0`으로
Go 프로그램을 빌드할 수 있지만, 실행할 OS·아키텍처에 맞는 공유 라이브러리가 필요합니다.
Go race detector는 `CGO_ENABLED=0` 테스트에 사용할 수 없습니다.
설치 명령은 [시작 가이드](getting-started.md), 로드·배포는 [purego 가이드](purego.md)를 참고하세요.

### 크로스 컴파일

리플렉션은 빌드 호스트에서 실행하고, 네이티브 라이브러리는 `-Dtarget`으로 지정한 타깃에
맞춰 빌드합니다. 다음 조건을 지켜야 합니다.

- `c_long`·`c_ulong`처럼 OS에 따라 폭이 달라지는 타입 대신 고정폭 타입을 사용하세요.
  호스트와 타깃의 struct 레이아웃이 다르면 생성된 ABI guard가 컴파일을 거부합니다.
- 타깃에 따라 공개 선언이 달라지는 API는 타깃 호스트에서 생성하세요. 레이아웃 검사는
  호스트에서 발견하지 못한 선언까지 찾아주지 않습니다.
- 호스트 리플렉션에 링크되지 않는 대상 전용 archive·동적 라이브러리의 심볼을
  리플렉션 중 호출할 수 없습니다.
- cgo doctor는 크로스 빌드에서 `FAIL target`을 보고합니다. purego doctor는 외래
  공유 라이브러리의 로드 검사를 `SKIP`합니다. 두 경우 모두 결과물은 타깃에서 테스트하세요.
- cgo로 여러 플랫폼을 한 트리에서 지원하려면 `targets`를 사용하세요
  ([설정](configuration.md#여러-타깃용-cgo-라이브러리)). `addObjectFile`로 붙인 미리
  빌드된 archive는 다른 타깃용으로 다시 만들 수 없으므로 이 모드와 함께 쓸 수 없습니다.

구체적인 명령은 [Windows cgo](getting-started.md#windows에서-cgo-백엔드-쓰기)와
[purego 배포](purego.md#패키징과-배포)에 있습니다.

## Zig 타입과 ABI

### 기본값과 객체

| 노출할 데이터 | 사용할 표현 | 주요 조건 |
|---|---|---|
| bool·정수·실수 | scalar | 정수는 최대 64비트, 실수는 `f32`·`f64` |
| `u21` 같은 비정규 폭 정수 | 다음 표준 폭의 Go 정수 | 입력 범위 검사로 `error`가 추가될 수 있음 |
| enum | `.enumeration` | 열린 enum은 `.exhaustive = false` 명시 |
| 상태를 가진 일반 struct | `.@"opaque"` | 생성자·소멸자와 소유권 지정 |

### 구조화된 데이터

| 노출할 데이터 | 사용할 표현 | 주요 조건 |
|---|---|---|
| 단순 값 struct | `.value` + `extern struct` | 필드는 scalar·등록 enum·적격 extern struct; 빈 struct 불가 |
| 비트 필드 | `.value` + 정수 backing의 `packed struct` | bool·정수·등록 enum·등록 packed struct 필드 |
| 중첩 pointer·string·slice 결과 트리 | `.materialized` | allocator, `.returns = .caller`, `[]u8` 해제 함수 필요 |
| tagged union | `.tagged_union` | handle projection, snapshot, 값 전달의 payload 조건이 다름 |
| generic | 구체화된 타입 또는 Zig 래퍼 | 구체화 전 함수·`anytype` 함수는 직접 노출 불가 |

`extern struct`는 Go에서는 값이지만 C 경계에서는 포인터로 전달합니다.
pointer·slice·optional 등을 필드로 가진 일반 결과 트리는 `.value`로 등록할 수 없습니다.
그런 반환은 materialized 결과로 복사하거나 opaque handle로 노출하세요.
materialized 결과의 순환·opaque pointer·callback·union 필드는 거부됩니다.
`anyerror`와 C 호출 규약이 아닌 함수 포인터도 노출할 수 없습니다.

tagged union의 값 전달·반환에는 scalar, 등록 enum, 적격 packed/extern struct payload를
쓸 수 있습니다. 같은 union을 handle 표현과 값 표현으로 동시에 사용하거나 다른 타입 안에
union 값을 중첩할 수는 없습니다. snapshot은 scalar·enum payload로 제한됩니다.
상세 조건과 예제는 [값 타입](bindings-types.md)과 [tagged union](bindings-unions.md)에 있습니다.

### 슬라이스, 문자열과 optional

| 형태 | 제약과 사용 방법 |
|---|---|
| 일반 `[]T` 반환 | scalar·enum·extern struct 원소를 Go 메모리로 복사 |
| 호출자 소유 native slice 반환 | `.returns = .caller`와 같은 원소 타입의 `.release` 필요 |
| `![]T`, `?[]T`, `!?[]T` | 지원하는 원소 타입·소유권 규칙 적용; 성공하며 존재하는 값만 복사·해제 |
| `[]u21` 같은 slice | 입력·out에는 allocator 필요; 반환은 caller-owned와 release 필요 |
| `?[]u21`·sentinel narrow slice | 미지원 |
| `[]string` 입력 | 문자열 의미가 지정된 const 문자열 slice 또는 sentinel 문자열 원소 |
| 일반 `[]string` 반환 | 미지원; materialized 결과 안의 string slice는 별도 지원 |
| NUL 종료 pointer | `[*:0]const u8` 지원; mutable·다른 sentinel·기타 many-pointer는 미지원 |
| `?T` | 파라미터·반환·error payload 지원; struct 필드·콜백·`[]?T`·`??T`는 미지원 |
| optional slice | out slice·중첩 slice·extern struct slice에는 사용 불가 |

값이 없다는 것과 비어 있는 값은 다릅니다. optional 입력은 Go의 `*T`, 반환은
`(T, bool)`로 구분하며, handle 검사 등으로 `error`가 추가될 수 있습니다.
복사 비용을 줄이려면 Go 버퍼를 재사용하는 out 파라미터를 사용하세요.
설정 예제는 [문자열, 슬라이스와 optional](bindings-buffers.md)에 있습니다.

out 버퍼의 `written`은 성공한 결과의 개수를 알려줄 뿐, native가 쓴 내용을 되돌리지
않습니다. 오류가 나도 입력한 Go 버퍼는 바뀌었을 수 있으므로 실패 시 내용 보존을 가정하지 마세요.

## 객체 수명과 동시 호출

| 객체 | 호출자가 지킬 조건 |
|---|---|
| caller-owned handle | 사용 후 `Close`; 이후 호출은 `ErrInvalidHandle` |
| `.child_of_receiver` 자식 | 자식을 먼저 닫고 부모를 닫음; 열린 자식이 있으면 부모는 `ErrHandleInUse` |
| `.returns = .borrowed` view | 부모가 살아 있는 동안만 사용; view의 `Close`는 조기 분리이며 native 해제 없음 |
| projection의 `*TRef` | 소유 union의 수명 안에서 사용; 별도 `Close` 없음 |

handle의 진행 중 호출 수는 메모리 해제 시점을 지키지만, native 함수 호출 전체를 잠그지는
않습니다. Zig 객체가 동시 변경을 허용하지 않으면 Go 호출자가 잠금을 제공해야 합니다.

일반 handle의 `Close`는 진행 중 호출을 기다리지 않습니다. 닫힘으로 표시한 뒤 마지막 호출이
끝나면 native 자원을 해제하므로, `Close` 반환이 즉시 해제 완료를 뜻하지는 않습니다.
borrowed view를 내주는 부모는 진행 중 view 호출이 있으면 `ErrHandleInUse`를 반환합니다.
호출이 끝난 뒤 다시 닫으세요.

열린 자식이나 retained callback이 있는 객체도 명시적으로 닫아야 합니다.
`runtime.AddCleanup`은 실행 시점, 프로그램 종료 전 실행, 참조 순환 해소를 보장하지 않습니다.
선언과 자세한 관계는 [객체 수명](bindings-handles.md)에 있습니다.

### Atomic 값과 포인터

atomic 필드의 getter·setter 한 번은 원자적이지만 struct나 union snapshot 전체가 원자적인 것은
아닙니다. atomic 필드가 있는 extern struct slice는 원소별로 복사합니다.

atomic 포인터 파라미터는 `u32`, `i32`, `u64`, `i64`만 지원하며 호출 동안만 빌립니다.
native 코드가 주소를 저장하거나 호출이 끝난 뒤 사용하면 안 됩니다.
[Atomic 선언](bindings-types.md#atomic-값-scalar)을 참고하세요.

## 콜백, 스트림과 취소

| 기능 | 사용자가 지킬 조건 |
|---|---|
| retained 콜백·포인터 | 소유 객체가 닫힐 때까지 유효하게 유지 |
| 콜백 `reentrancy`·`thread` | 문서 계약이며 런타임에서 자동 강제하지 않음 |
| purego 콜백 | 반환은 `void` 또는 `i32`; 부동소수 파라미터는 지원 |
| `.go_error` 콜백 | Zig 반환은 `i32`; 같은 ABI 시그니처의 콜백들이 설정을 공유 |
| 스트림 인자 | 같은 스레드에서 호출 범위 안에만 사용; retained·optional·필드·콜백 인자로 사용 불가 |
| 스트림 반환 | 인자가 없는 메서드의 직접 반환만 지원; optional·error union 불가 |
| `.cancel` | Zig 함수가 취소 플래그를 직접 확인하고 설정된 취소 오류를 반환 |

콜백 오류가 생겨도 native 실행을 강제로 중단하지 않습니다. Zig 코드가 실패 반환값을
처리하거나 취소 플래그를 확인해야 합니다. 취소 플래그와 스트림 어댑터는 호출 뒤까지
보관할 수 없습니다. `io.ReaderAt`, `io.Seeker`, 파일 디스크립터 전달은 지원하지 않습니다.

`Bytes() []byte`를 가진 reader는 빠른 경로에서 원본의 읽기 위치가 전진하지 않습니다.
읽기 위치를 유지해야 한다면 `bytes.NewReader`처럼 이 경로에 들어가지 않는 타입을 사용하세요.

[콜백 설정](bindings-callbacks.md)과 [스트림·취소](bindings-streams.md)에서 예제를 확인할 수 있습니다.

## 오류와 panic

| 실패 | Go에서 관찰하는 결과 | 후속 처리 |
|---|---|---|
| Zig error union | 생성된 `error` | `errors.Is`로 분류 |
| Zig panic — 공개 함수가 `error` 반환 | `*NativePanicError` | 작업 중단, 해당 handle 재사용 금지 |
| Zig panic — 오류 반환 자리가 없는 함수 | 메시지 출력 후 프로세스 중단 | Zig 함수를 error union으로 설계 |
| Go 콜백 panic | native 호출 뒤 `*CallbackPanicError`로 다시 panic | 일반 오류 반환과 구분해 처리 |
| 손상된 native 메모리·하드웨어 fault | 복구 보장 없음 | panic 경계를 메모리 안전 장치로 간주하지 않음 |

Zig panic 경계는 native 프레임의 `defer`·`errdefer`를 실행하지 않고 빠져나옵니다.
그 호출에 참여한 handle은 **poison 상태**가 되어 후속 호출이 실패하며,
`Close`도 native 소멸자를 실행하지 않습니다. 자원 누수가 생길 수 있으므로 정상 복구로
간주하지 마세요. handle 없이 변경한 전역 상태의 복구는 호출자가 판단해야 합니다.

native가 별도 스레드에서 부른 retained 콜백의 오류·panic은 그 handle의 다음 호출에서
전달될 수 있습니다. 원인 확인 방법은 [Go 오류 처리](bindings-callbacks.md#생성된-go-error-판별)에 있습니다.

## 이름과 메타데이터

- 한 실행 파일에 여러 바인딩을 링크하면 서로 다른 C `prefix`를 지정합니다.
- namespace가 달라도 공개 Go 자유 함수 이름은 겹칠 수 있습니다. `.name`으로 구분하세요.
- 하위 패키지의 타입 참조는 순환할 수 없습니다. 공통 타입을 별도 패키지로 옮기세요.
- 파라미터 이름은 명시적 `params`, Zig 소스 분석, `p0` 등의 기본 이름 순으로 정합니다.
  생성 지역 변수와의 모든 충돌을 피하는 것은 아니므로 생성 후 Go 테스트를 실행하세요.
- 문자열 의미, 반환값 소유권과 retained 수명은 타입만으로 추론할 수 없어 명시해야 합니다.
- 자동 발견을 켜면 새 `pub fn`도 바인딩에 들어올 수 있습니다. 안정된 API가 필요하면
  함수 목록을 명시하고, 자동 발견에서는 `exclude`를 관리하세요.

설정 예제는 [함수 선택, 이름과 패키지](bindings-functions.md)에 있습니다.

## ABI 호환성

`extern struct`의 필드 변경, snapshot·값 union의 variant 추가, 타입의 optional 전환,
소유권·해제 함수 변경은 호환성을 깨뜨릴 수 있습니다. `abi-check`는 cgo 정적 링크로
동시에 배포하는 경우에도 이 계약 변경을 검사합니다.

바인딩 정적 archive는 의존 archive를 합친 단일 파일이 아닙니다. 다른 링커로 배포하려면
그 의존성도 함께 제공해야 합니다. 자동 수집되지 않는 Zig 내부 runtime archive는
`cgo_flags.extra_ldflags`로 연결해야 할 수 있습니다.

C 표현과 판정 근거는 [생성 ABI 참조](generated-abi.md), 링크 설정은
[빌드 설정](configuration.md)에 있습니다.

## 생성물 관리

생성된 Go 소스와 `zigo/` 메타데이터를 함께 커밋하고, CI에서 생성물 검사와 네이티브 빌드 후
Go 테스트를 실행합니다. 정적 링크 입력 파일의 예외와 자동 정리 범위는
[생성물과 CI 관리](generated-code.md)에 정리되어 있습니다.
