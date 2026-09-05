# 생성 Go 코드의 내부 구조

생성 파일을 읽거나 zigo 구현을 수정할 때 참고하는 문서입니다. 애플리케이션에서 쓸 선언은
[`bindings.zig` 선언](bindings.md), 생성·커밋·검사는 [생성물과 CI 관리](generated-code.md)에 있습니다.

[파일별 역할](#생성-파일의-역할), [이름과 포맷](#go-이름과-포맷),
[하위 패키지의 공유 코드](#하위-패키지의-공유-코드), [purego 로더](#purego-로더-파일)를 설명합니다.

## 생성 파일의 역할

- `<package>_gen.go`: 공개 함수와 method, `.iterator` 메서드의 `iter.Seq` wrapper
- `<package>_enums_gen.go`: enum type, 상수, `String()`
- `<package>_structs_gen.go`: `extern struct` 공개 value type과 raw 변환, 값 매개변수로
  쓰는 tagged union의 variant constructor와 `Tag()` accessor
- `<package>_handles_gen.go`: opaque handle type과 lifecycle method. borrowed `<T>Ref`는
  그것을 내주는 함수나 projection이 있는 type에만 생성된다
- `<package>_runtime_gen.go`: handle interface, projection status, `Must*`
  wrapper, bool 변환, callback type과 handle 등 private runtime support
- `<package>_union_<union>_gen.go`: tagged union 하나마다 projection, snapshot,
  sealed variant type
- `<package>_errors_gen.go`: error type, `Err*` sentinel, code 변환
- raw `_gen.go`: C ABI 또는 purego symbol 호출 계층

enum은 정수 기반 Go 타입, 이름 붙은 상수, `String()`으로 생성됩니다. opt-in한 open enum의
GoDoc은 이름 붙은 상수 밖의 값도 유효하다고 명시하며, 그런 값의 `String()`은
`EraseDisplay(42)`처럼 `Type(N)`을 반환합니다. cgo와 purego 모두 정수 값을 검사하거나
좁히지 않고 왕복시킵니다. `abi-check`는 exhaustive enum과 open enum 사이의 변경을 양방향
breaking으로 보고합니다. `.text = true`로 등록한 enum은 같은 파일에 `Parse<Enum>`,
`MarshalText`, `UnmarshalText`를 더 갖고, 그런 enum이 하나라도 있으면 파일 앞에
패키지 공용 `EnumParseError`가 생성됩니다.

선언이 하나도 없는 파일은 생성하지 않습니다. enum이 없으면 `_enums_gen.go`가,
tagged union이 없으면 union 파일이 아예 만들어지지 않습니다.

scalar/void payload만 가진 tagged union 값 매개변수는 C에서 tag 정수와 variant 선언
순서의 non-void payload slot들로 평탄화됩니다. raw cgo와 purego 함수는 같은 순서를 쓰고,
Zig shim이 tag를 switch해 원래 union 값을 재구성합니다. variant를 추가하면 C signature와
semantic ABI가 함께 커지므로 `abi-check`는 breaking으로 판정합니다.

모든 exported 선언에는 GoDoc이 생성됩니다. Zig source doc이 있으면 AST 보강 결과를 사용하고,
없으면 bound Zig operation과 ownership·lifetime·failure contract를 설명하는 기본 문서를
생성합니다.

GoDoc은 항상 Go 이름으로 시작하므로, Zig doc의 첫 단어가 그 선언의 이름(Zig 이름이든 Go
이름이든, 대소문자 무시)이면 그 단어를 빼고 붙입니다. `/// clone copies the queue.`는
`// Clone clone copies ...`가 아니라 `// Clone copies the queue.`가 됩니다.

## Handle의 수명 관리

호출 중 handle의 수명은 handle 검사가 붙이는 `defer x.zigoRelease()`가 지킵니다. 그
defer가 `x`를 붙잡고 native 호출 뒤에 역참조하므로 함수가 끝날 때까지 살아 있고,
receiver나 handle parameter에 `runtime.KeepAlive`를 따로 걸지 않습니다. 생성 코드에
남는 `runtime.KeepAlive`는 두 가지뿐입니다: `Close`가 `cleanup.Stop()` 뒤 자기 자신을
붙잡는 것과, 문자열·slice 데이터처럼 Go 메모리의 포인터를 native에 넘긴 동안 그 메모리를
붙잡는 것.

| handle 종류 | native 자원 소유 | `Close` | 부모가 닫힌 뒤 |
|---|---:|---|---|
| 일반 caller-owned | 예 | destructor를 한 번 호출 | 자신의 호출이 `HandleError` |
| `.child_of_receiver` 자식 | 예 | destructor 후 부모 등록 해제 | 열린 자식이 있으면 부모 Close 거부 |
| `.returns = .borrowed` view | 아니요 | view 조기 detach, destructor 없음 | view 호출이 `HandleError` |
| tagged-union `*TRef` | 아니요 | 제공하지 않음 | projection 호출이 `HandleError` |

borrowed view는 일반 `*T` handle 구조를 쓰되 owner lifecycle interface를 보관합니다. 호출은
owner를 먼저 acquire하고 view를 acquire하며, release는 역으로 둘을 놓습니다. view를 반환하는
부모의 `Close`는 active 호출이 있으면 `*HandleInUseError`로 거부되므로 destructor가 view의
native 호출과 경합하지 않습니다. view를 통한 panic은 owner에 poison을 전달합니다. 이 계약은
단일 package에서는 package-local helper로, `.packages`가 있으면 `internal/lifecycle` interface로
같게 생성됩니다.

borrowed view를 receiver로 자식을 예약할 때는 중간 view의 로컬 카운터에 예약을 남기지 않습니다.
`zigoAcquireChild`가 owner 사슬을 재귀적으로 따라가 최종 owning handle을 획득하고, 그 정확한
reservation owner를 생성된 자식에 저장합니다. 정상 `Close`와 cleanup은 저장된 같은 대상에
drop하므로 여러 단계 view에서도 카운터가 음수가 되거나 다른 handle에 남지 않습니다.

`.child_of_receiver = true`인 constructor는 receiver 획득과 같은 잠금 안에서 자식 하나를
예약합니다. 성공하면 생성된 자식의 `parent` 참조와 부모의 `children` 카운트로 예약을
넘기고, 실패하면 예약을 되돌립니다. 그래서 constructor와 부모 `Close`가 동시에 실행돼도
자식이 부모 해제 뒤에 생길 수 없습니다. 부모 `Close`는 `children != 0`이면 상태를 닫힘으로
바꾸지 않고 `*HandleInUseError`(`ErrHandleInUse`)를 반환합니다. 자식 `Close`는 진행 중 호출이
끝나 native destructor가 실행된 뒤에만 부모 카운트를 내립니다. 자식 호출은 부모도 함께
acquire/release하므로 부모의 closed·poison 상태를 그대로 따릅니다.

## 콜백 등록의 수명

callback parameter는 익명 함수가 아니라 생성된 정의 type을 사용합니다. borrowed callback
handle은 호출 후 즉시 해제하고, retained callback handle은 소유 객체의 멱등 `Close`에서
해제합니다. retained callback을 받는 method는 native 등록이 성공한 뒤 함수·파라미터별
slot을 새 handle로 교체하고 이전 handle을 해제합니다. cgo에서는 기존 constructor 경로와
같이 native 호출이 반환된 시점을 이전 callback에 새 호출이 들어오지 않는 경계로 사용하고,
purego registry는 이미 진행 중인 호출이 끝날 때까지 기다립니다.

## Go 이름과 포맷

- Zig snake_case parameter는 camelCase로 바뀝니다.
- Go keyword나 생성 local과 충돌하면 `type_`, `code_`처럼 escape합니다.
- 변환 후 이름이 겹치면 뒤쪽 이름에 숫자를 붙입니다.
- method receiver는 타입마다 한 번 정합니다. receiver 타입의 snake_case 이름에서 길이 1부터
  늘리며, 그 타입의 **모든** 메서드가 쓰는 Go 파라미터 이름(flatten된 필드와 `ctx` 포함)과
  겹치지 않는 첫 접두사를 쓰고, 전체 이름까지 모두 겹치면 `recv`를 씁니다. 예를 들어
  `Terminal.setTitle(t)`가 있으면 `Terminal`의 모든 메서드와 lifecycle·projection helper가
  `te`를 receiver로 씁니다. 메서드마다 다른 이름이 나오지 않으므로 `staticcheck`의
  ST1016(receiver 이름 일관성)을 만족합니다.
- 공개 Go 함수 이름은 namespace를 붙이지 않습니다. 중첩 namespace의 함수도
  `CodepointWidth`처럼 함수 이름만 씁니다.
- C가 이름 붙일 수 없는 정수 폭(`u21`)은 파라미터·반환값에서 다음 폭으로 승격되어
  `uint32`로 나옵니다. 승격된 파라미터가 있는 함수는 공개 시그니처에 `error`가 붙고,
  범위 검사는 cgo 호출 전 Go에서 이뤄져 `*RangeError`를 돌려줍니다.
- 모든 생성 source는 기록 전 `gofmt`로 포맷됩니다.

C 헤더는 typedef, 함수, enum macro가 충돌할 수 있는 식별자 공간을 lowering 결과 그대로
검사합니다. handle·enum·value struct·snapshot typedef, 함수·projection·snapshot·last-error
심볼, enum 상수를 cgo와 purego별로 모으고 중복이면 `ZIGO036`을 냅니다. 진단은 두 선언과
충돌한 최종 C 이름을 보여 주며 `.name` 또는 `.prefix` 변경을 안내합니다.

`go-check`도 같은 `gofmt` 결과와 비교합니다. 사용자 소유 Go 파일은 포맷하거나 검사하지
않습니다.

## 하위 패키지의 공유 코드

`.packages`가 있으면 `internal/lifecycle`이 모든 공개 패키지가 공유하는 handle 계약, pointer
검사와 poison 전파, 오류 형식과 sentinel identity를 소유합니다. 각 공개 패키지는 기존 공개
이름을 type alias와 sentinel 변수로 다시 내보내므로 어느 패키지의 sentinel을 사용해도
`errors.Is`가 같은 error code를 찾습니다. cgo의 C 호출 계층은 `internal/raw`에 남고,
purego의 로더·함수 테이블·callback token registry는 설정한 `internal/native` 같은 raw
패키지에 남습니다. `.packages`가 없는 기존 단일 패키지는 shared lifecycle을 만들지 않아
생성 바이트와 공개 API를 유지합니다.

## purego 로더 파일

purego raw 패키지는 로더 primitive를 build tag로 나눈 파일 두 개를 함께 생성합니다.

```text
go-purego/internal/raw/raw_load_posix_gen.go    // go:build !windows
go-purego/internal/raw/raw_load_windows_gen.go  // go:build windows
```

생성된 C(`panic.c`)와 헤더는 공개 진입점에 `ZIGO_EXPORT`를 붙입니다. ELF와 Mach-O는
공유 라이브러리의 non-static 심볼을 모두 내보내지만 COFF는 명시적 annotation 없이는
아무것도 내보내지 않으므로, 이것이 없으면 DLL이 로드는 되고 심볼은 하나도 해석되지
않습니다. 매크로는 `_WIN32`에서만 `__declspec(dllexport)`로 확장되고 그 밖에서는 비어
있으므로 생성물은 모든 호스트에서 동일합니다. 대상은 생성된 로더가 이름으로 찾는
심볼뿐입니다. 내부 `_impl` 절반은 내보내지 않습니다.

콜백 dispatcher는 모든 플랫폼에서 `uintptr` 하나를 반환합니다. Windows의
`syscall.NewCallback`이 정확히 포인터 크기의 결과 하나를 요구하기 때문이며,
반환값이 없는 Zig 콜백도 `0`을 돌려줍니다. 네이티브 쪽은 `int32_t` 반환으로
선언되어 하위 워드만 읽으므로 값은 그대로 왕복합니다.

두 파일은 `openLibrary`, `closeLibrary`, `resolveSymbol` 세 함수를 똑같이 정의하며
POSIX는 purego의 `Dlopen`/`Dlsym`/`Dlclose`를, Windows는 표준 라이브러리
`syscall.LoadLibrary`/`GetProcAddress`/`FreeLibrary`를 사용합니다. purego v0.10.2는
Windows용 로딩 API를 공개하지 않으므로 이 선택은 모듈 의존성을 늘리지 않습니다. 후보
경로 결정, `LoadLibrary`, `*LibraryError` 모양은 공용 파일에 그대로 남으므로 공개
API는 세 OS에서 동일합니다.

## 콜백 panic 검사 비용

retained 콜백을 가진 타입의 메서드는 native 호출 뒤 콜백 slot을 확인합니다. raw 계층의
`PendingCallbackPanics()`가 0이면 순회를 건너뛰므로 정상 경로는 원자적 load 한 번입니다.
이 검사를 넣기 전 `EventQueue.Enqueue`는 slot 3개마다 mutex와 handle 조회를 했고,
같은 환경에서 324 ns/op이 260 ns/op으로 줄었습니다(20코어 Apple Silicon, Go 1.27,
`-count=5` 평균).

## 패닉 메시지 전달

Zig panic은 `panic.c`가 `setjmp`/`longjmp`로 붙잡습니다. 붙잡힌 메시지는 시퀀스 번호가 붙은
64칸 slot 테이블에 실리고, C 함수는 `-(256 + 시퀀스)`를 상태 코드로 돌려줍니다. Go는
`errorForCode`·`zigoProjectionError`에서 `-256` 이하 코드를 보면 `PanicMessage(code)`로
그 slot을 읽어 `*NativePanicError`를 만듭니다. 메시지가 코드에 묶여 있으므로 어느
스레드에서든 읽을 수 있고, 생성 함수는 OS 스레드를 고정하지 않습니다. 같은 slot이 64번
뒤의 panic에 재사용되면 메시지는 빈 문자열이 되며 코드와 연산 이름은 그대로 남습니다.

`{prefix}_last_error_message`는 마지막 panic의 thread-local 메시지를 돌려주는 진단용
심볼로 남아 있습니다. 생성 코드는 더 이상 이 심볼로 오류를 만들지 않습니다.

이전 설계는 메시지를 thread-local에만 두고 두 번째 호출로 읽었기 때문에 error union
함수마다 `runtime.LockOSThread`가 필요했습니다. 그 비용은 호출당 약 5 ns(2%)로 작았고,
raw 시그니처가 바뀌는 minor 릴리스에 맞춰 ABI를 정리하면서 없앴습니다.

