# 제한사항과 운영 주의사항

새 API를 설계할 때는 먼저 이 문서에서 타입과 수명 계약을 확인하세요. 실제 선언 방법은
[`bindings.zig` 선언](bindings.md), backend별 설정은 [빌드 설정](configuration.md)에 있습니다.

## 지원 환경

- 기본 cgo 백엔드의 지원 범위는 Zig 0.16.0, Go 1.24 이상, cgo가 활성화된
  macOS/Linux/Windows다. 생성된 handle이 항상 `runtime.AddCleanup`을 등록하므로
  Go 1.24가 하한이다. Windows는 amd64에 gnu ABI 전용이고 `CC="zig cc"`를 요구한다.
  mingw-w64를 따로 설치할 필요는 없다. zigo 사용자는 이미 Zig를 갖고 있고 `zig cc`가
  mingw 헤더·CRT·링커를 함께 제공하기 때문이다. MSVC ABI(`-target *-windows-msvc`),
  386, arm32는 지원하지 않는다. 레시피는 [시작 가이드](getting-started.md)에 있다.
- opt-in `.link = .purego`는 Go 빌드에서 C 컴파일러와 cgo를 제거하고 네이티브
  macOS/Linux/Windows의 amd64·arm64를 지원하지만, 공유 라이브러리 배포를 요구한다.
  모바일과 purego Tier 2 타깃은 후속 작업이다. 정적 링크는 cgo 전용이다.
- purego 콜백의 결과 타입은 `void` 또는 `i32`만 지원한다. Windows의
  `compileCallback`이 포인터 크기 결과 하나를 요구하므로 콜백 dispatcher는 모든
  플랫폼에서 `uintptr` 하나를 반환하고, 그 밖의 결과 타입은 실어 보낼 곳이 없다.
  생성 시점에 `ZIGO014`로 거부한다. 값은 userdata를 통해 돌려준다.
  부동소수 **파라미터**는 제약이 아니다. 모든 플랫폼에서 같은 폭의 정수에 IEEE-754
  비트 패턴으로 실려 건너가므로 `compileCallback`은 부동소수 인자를 보지 않는다.
- purego는 v1 이전 베타 소프트웨어다. zigo는 `github.com/ebitengine/purego v0.10.2`를
  고정해 생성·검증하며 사용을 생성된 raw 파일에만 격리한다. 다른 버전을 요구하는
  `go.mod`는 `go-doctor`가 경고로 보고한다.
- 공유 라이브러리는 타깃별 아티팩트다. purego는 Go 애플리케이션 빌드에서 C 컴파일러를
  없앨 뿐 하나의 Zig 아티팩트를 여러 타깃에 이식해 주지 않으므로, 배포하는 OS·아키텍처
  조합마다 아티팩트를 하나씩 만들어야 한다. 다만 그 아티팩트를 만들 호스트는 하나면
  된다. `zig build go-lib -Dtarget=x86_64-windows`처럼 크로스 컴파일할 수 있고,
  Windows DLL도 POSIX 호스트에서 만든다.
- Go race detector는 여전히 cgo를 요구하므로 `CGO_ENABLED=0` 테스트에는 사용할 수 없다.
  Windows purego 테스트도 같은 이유로 race 커버리지를 얻지 못한다.
- 크로스 컴파일은 두 백엔드 모두에서 동작한다. reflector는 **호스트**로 빌드해 실행하고
  라이브러리와 shim만 `-Dtarget`으로 빌드하므로 `zig build purego-go-lib
  -Dtarget=x86_64-windows`가 POSIX 호스트에서 동작한다. cgo 백엔드도 POSIX 호스트에서
  `-Dtarget=x86_64-windows-gnu`로 정적 아카이브를 만들고 `GOOS=windows
  CC="zig cc -target x86_64-windows-gnu"`로 링크할 수 있다. 다만 `go-doctor`는 크로스
  빌드에서 cgo 백엔드를 검증하지 못하므로(관찰할 수 없는 `GOOS`·`CC` 조합에 달려 있다)
  `FAIL target`을 보고한다. 결과물은 타깃에서 실행해 확인한다. 두 가지가 여기에 따라온다.
  - 리플렉션이 관찰하는 레이아웃은 **호스트**의 것이다. 지원 타깃은 모두 64비트
    리틀엔디언이라 고정폭 정수·실수·포인터는 일치하지만 `c_long`·`c_ulong`처럼
    타깃마다 폭이 다른 C 타입은 어긋난다. 생성된 shim은 mirror하는 모든 `extern
    struct`의 크기·정렬·필드 오프셋을 comptime으로 고정하므로, 어긋나면 조용히
    잘못된 ABI를 내보내는 대신 타깃 컴파일이 `zigo ABI guard: ...` 메시지와 함께
    실패한다. 구조체 밖의 스칼라는 Zig 자신의 타입 오류로 걸리거나 shim 경계에서
    손실 없이 넓혀진다.
  - 타깃에 따라 바인딩 표면 자체가 달라지는 경우(`builtin.target`을 comptime으로
    분기해 export를 늘리거나 줄이는 코드)는 지원하지 않는다. 리플렉션은 호스트 표면
    하나만 보며, 가드는 레이아웃 차이를 잡지 표면 차이를 잡지 못한다. 그런 바인딩은
    타깃 호스트에서 생성한다.
- Go 쪽 크로스 컴파일은 별개다. 생성된 purego 패키지는 순수 Go이므로 C 툴체인 없이
  `GOOS=windows CGO_ENABLED=0 go build ./...`로 빌드된다.
- zigo는 Go 바인딩만 생성한다. IR은 다른 언어용 범용 IDL을 목표로 하지 않는다.
- 한 Go 실행 파일에 zigo 바인딩을 둘 이상 링크하려면 `prefix`가 서로 달라야 한다.
  생성되는 C 심볼은 런타임 것(`<prefix>_panic_bridge`, `<prefix>_last_error_message`)
  까지 전부 접두사를 쓰므로, 기본값 `zg`를 둘 다 쓰면 정적 링크에서 중복 심볼로 실패한다.

## Zig 타입과 ABI

- 일반 Zig `struct`의 메모리 배치는 안정된 C ABI가 아니다. 값 의미로 노출하려면
  `extern struct`를 사용하고, 일반 struct는 opaque 포인터로 노출한다.
- zigo는 어떤 aggregate도 C 경계를 값으로 넘기지 않는다. `extern struct` 파라미터는
  `const T*`, 반환은 `T*` out 파라미터로 내려가며 값 의미는 Go 쪽에서만 유지된다. 필드는
  bool, 정수/부동소수 스칼라, 등록된 enum, 또는 다시 적격한 `extern struct`여야 하고, 그
  밖의 필드나 빈 struct는 `ZIGO012`로 거부된다. scalar-only struct는 직접 slice 원소로
  사용할 수 있지만, optional이나 callback 시그니처 안에 넣으면 `ZIGO013`으로 거부된다.
  필드를 하나라도 바꾸면 ABI가 깨진다.
- slice 원소인 `extern struct`는 bool 필드가 없을 때만 주소를 그대로 넘기는 캐스트 경로를
  쓴다. Go의 `bool`과 C의 `uint8_t`는 폭은 같아도 같은 타입이 아니므로, bool 필드가 하나라도
  있으면 원소별 복사 경로로 남는다. 캐스트 경로는 생성된 compile 시점 layout 단정이
  지키므로, Go와 C의 배치가 어긋나면 바인딩이 컴파일되지 않는다.
- `.direction = .out` slice에 `.written = .@"return"`을 쓰려면 반환 payload가
  `usize`(또는 `!usize`)여야 하고, `.out`이 아닌 파라미터에는 붙일 수 없다. 둘 다
  `ZIGO017`로 거부된다.
- native 메모리를 그대로 들여다보는 뷰 반환은 제공하지 않는다. 반환된 slice의 수명이
  native 객체의 수명에 묶이면 Go 쪽에서 그 규칙을 강제할 방법이 없기 때문이며, 복사를
  피하고 싶다면 `.direction = .out` 파라미터로 결과를 받는다.
- `packed struct`의 정수 백킹 노출은 지원하지 않는다. `ZIGO003`으로 거부된다.
- optional은 선언된 opaque type의 pointer(`?*T`, `?*const T`)에만 쓸 수 있다. handle
  인자는 이미 pointer라서 nil이 NULL로 그대로 건너가지만, `?i32`나 `?[]u8` 같은 optional은
  별도의 presence 플래그가 필요해 reflection 단계에서 거부된다.
- tagged union은 `.repr = .tagged_union`으로 등록한 뒤 포인터로만 노출한다. 생성된
  `Tag`/`As*`가 active tag를 검사하며 union 레이아웃은 C로 전달하지 않는다. nested
  aggregate, optional, error union, callback 또는 pointer 원소 slice payload는 지원하지 않는다.
- NUL 종료 문자열은 `[*:0]const u8`만 지원하며 Go에서는 `string`이 된다. mutable 또는
  0이 아닌 sentinel pointer와 그 밖의 many-pointer는 reflection 단계에서 거부된다.
- 포인터를 품은 결과 트리(문자열 필드, 배열 필드, 중첩 struct 포인터를 가진 struct)는
  값으로 노출하지 않는다. 필드가 재귀적으로 ABI 안전해야 하므로(`ZIGO012`) 이런 결과는
  opaque handle로 다시 설계해야 하고, 각 필드 접근이 handle을 획득한 채
  native 호출 한 번씩이 된다. 필드가 많은 트리라면 호출 수가 필드 수에 비례하므로, 필요한
  값만 스칼라로 평탄화해 한 번에 돌려주는 함수를 따로 두는 편이 대개 낫다.
- `extern struct`에 필드를 추가하는 것은 `abi-check`에서 항상 breaking이다. aggregate는
  포인터로만 건너가고 크기가 따라가지 않으므로, 버퍼를 잡은 쪽과 쓰는 쪽의 필드 수가
  다르면 경계를 넘어 읽거나 쓴다. `.cgo_static`은 native와 Go가 같이 링크되어 실제로는
  안전하지만, 링크 방식별로 판정을 낮추는 opt-in은 두지 않기로 했다. 판정을 링크 설정에
  의존하게 만들면 같은 semantic 변경이 프로젝트마다 다르게 평가되기 때문이다.
- slice 반환에 `.returns = .caller`를 쓰려면 `.release`로 같은 원소 타입의 slice 하나를
  받는 해제 함수를 지정해야 한다. 생성된 코드가 복사 후 즉시 해제하므로 Go에는 해제할
  것이 남지 않고, release 함수 자체는 공개 API에 나오지 않는다. 조건을 어기면 `ZIGO016`이다.
  `![]T`에도 쓸 수 있으며, 이때 복사와 release는 성공 경로에서만 일어난다.
- slice 반환의 원소는 스칼라, 등록된 enum, `extern struct`만 가능하다. 포인터를 포함하는
  원소는 `ZIGO005`로 거부한다. `![]T`도 같은 규칙을 따르며, `![]string`과 `!?[]T`는
  지원하지 않는다.
- string slice 입력은 `[]const []const u8`에 `.utf8_string`을 지정하거나 element를
  `[:0]const u8`/`[*:0]const u8`로 선언해야 하며 Go에서는 `[]string`이 된다. native에는
  NUL을 포함한 평탄화 바이트 버퍼와 길이 배열만 전달한다. `[]string` 반환, mutable outer
  slice, 문자열이 아닌 pointer-bearing element는 지원하지 않는다.
- `.access = .snapshot`의 값 스냅샷은 모든 variant payload가 void, bool, 정수/부동소수
  스칼라, 또는 등록된 enum일 때만 쓸 수 있고 `tag`라는 이름의 variant를 허용하지 않는다.
  그 밖의 payload는 `ZIGO011`로 거부되므로 projection 표현을 쓴다. 스냅샷 union은 variant를
  추가하면 구조체 배치가 달라져 ABI가 깨진다. 스냅샷 구조체도 Zig union의 배치가 아니라
  zigo가 정의한 `extern struct`이며, variant 수만큼 멤버를 가지므로 variant가 많은 union은
  호출마다 그만큼을 복사한다.
- generic 함수는 구체화 전에는 시그니처가 없으므로 직접 노출할 수 없다. generic 타입은
  `types`에 구체화된 타입을 이름과 함께 등록한다.
- `anyerror`, C 호출 규약이 아닌 함수 포인터, Go 포인터를 포함할 수 있는 슬라이스처럼
  안전한 계약을 만들 수 없는 선언은 생성 단계에서 거부한다.
- C가 이름 붙일 수 없는 정수 폭(`u21`, `i24`)은 파라미터·반환값·error union payload에서만
  다음 2의 거듭제곱 폭으로 승격된다. shim이 진입 시점에 범위를 검사하고 벗어나면 panic한다.
  `extern struct` 필드, slice 원소, 콜백 시그니처는 C로 바이트 그대로 비추므로 그 자리에서는
  `ZIGO018`로 거부된다. 65비트 이상의 정수와 `f80`은 어디서도 지원하지 않는다.
- 지원 타입과 정확한 하강 규칙은 [ABI 하강 규칙](.agent/design/03-lowering-rules.md)을 참고한다.

## 생성기 진단

생성 단계의 모든 거부는 `error[ZIGOnnn]` 진단 한 줄로 나온다. 스택 트레이스나 bare error는
남아 있지 않으며, 진단은 문제가 된 선언(`Owner.fn`이나 `namespace.fn`)과 파라미터 이름,
그리고 Zig 쪽 철자를 함께 알려준다.

```
error[ZIGO018]: unsupported integer width `u21` in parameter `cp`
  --> semantic.json (unicode.codepointWidth)
  hint: use an 8, 16, 32, or 64-bit integer, or `usize`
```

- `ZIGO018` — C ABI가 이름 붙일 수 없는 정수·실수 폭이다. 중첩된 위치는 `the slice element
  of parameter \`cps\``처럼 도달 경로까지 적는다.
- `ZIGO019` — 지원하지 않는 타입이다. optional은 opaque pointer 위에서만 표현할 수 있다.
- `ZIGO020` — `semantic.json`의 IR 버전이 이 zigo와 맞지 않는다. 다시 생성한다.
- `ZIGO021` — package, prefix, 함수 이름 중 하나가 비어 있다.

리플렉션 단계의 거부는 `bindings.zig`를 빌드할 때의 `@compileError`로 나오며, 제약과 함께
그것이 걸린 선언·파라미터를 적는다(`... , at \`Terminal.write\` parameter \`bytes\``).

## 이름과 메타데이터

Zig reflection에는 함수 파라미터 이름이 없다. zigo는 `bindings.zig`의 `params`, Zig AST
스캔, `p0`, `p1` 형식의 fallback 순으로 이름을 결정한다. `source_root`를 지정하면 실제
대상 모듈 루트에서 owner-qualified 선언을 찾는다. AST 정보는 타입 판단에 사용하지 않는다.
공개 Go 파라미터 이름을 Zig 소스와 독립적으로 고정하려면 `params`를 명시한다.

AST 보강에 사용하는 기본 `bindings.zig`를 읽지 못하면 reflection이 실패한다. 선택적인
같은 디렉터리의 `root.zig`가 없는 경우만 정상적으로 건너뛰며, 발견된 `.zig` import를
읽지 못하거나 AST를 파싱하지 못하면 오류 경로와 원인을 출력하고 생성을 중단한다.

`semantic.json`의 `symbol`은 함수가 export되는 C 심볼 이름이며 헤더·링커와 같은 규칙에서
나온다. purego의 `_purego_v2` 접미처럼 백엔드가 덧붙이는 장식은 포함하지 않는다.

Zig doc 주석은 형식만 조정되고 본문은 그대로 옮겨진다. Go doc 관례에 맞는 첫 문장을
원하면 Zig 쪽 doc을 그렇게 쓴다. Go doc의 마크다운 확장(목록, 링크, 제목)은 해석하지
않고 그대로 통과시킨다.

문자열, 반환 포인터 소유권, retained 포인터와 콜백 수명은 타입만으로 결정할 수 없다.
`semantic`, `returns`, `param_meta.retention`을 통해 계약을 명시해야 한다.

`.discover = .public`은 공개 Zig API와 바인딩 API가 같은 프로젝트를 위한 opt-in 정책이다.
공개 helper나 지원하지 않는 generic 함수까지 발견될 수 있으므로 `exclude`로 의도를
명시한다. 일부 함수만 안정적으로 노출해야 하는 라이브러리는 명시적인 `functions` 목록을
유지한다.

## 런타임 주의사항

- Zig panic은 C 경계에서 오류 코드 `-2`와 마지막 오류 메시지로 변환되지만 정상 복구를
  뜻하지 않는다. Go에서는 `errors.Is(err, ErrNativePanic)`으로 판별한다. 메시지를 수집한 뒤
  현재 작업을 중단한다. 메시지는 native 쪽 thread-local에 남으므로, error를 반환하는 생성
  함수와 union accessor는 호출 동안 `runtime.LockOSThread`로 goroutine을 그 thread에
  고정한다. 호출당 비용은 작지만 0은 아니다.
- panic은 `longjmp`로 native 프레임을 빠져나오므로 그 프레임들의 `defer`/`errdefer`는
  실행되지 않는다. 잠금·할당·파일 핸들이 새고 객체는 반쯤 바뀐 채 남을 수 있다. 그래서
  `-2`로 끝난 호출이 닿은 모든 handle(receiver, handle 인자, projection의 소유자)은
  **poison** 되어, 이후 호출은 처음 panic을 가리키는 `*NativePanicError`를 돌려주고
  `Close`는 native deinit 없이 객체를 누수시킨다. handle이 없는 호출(자유 함수)은 poison할
  것이 없으므로, 그런 함수가 건드린 전역 상태는 호출자가 판단한다.
- Go 콜백의 panic은 trampoline이 복구해 native에는 `-3`(부호 있는 32비트 결과)으로 전달하고,
  native 호출이 돌아온 뒤 `*CallbackPanicError`로 **다시 일으킨다**. native가 `-3`을 자기
  error로 바꿔도 Go 호출자는 error가 아니라 panic을 본다. 다시 일어나는 시점은 그 호출이
  돌아온 뒤이므로, native가 콜백 실패를 무시하고 계속 진행하면 그 진행은 이미 끝난 뒤다.
  생성된 호출 밖에서 — 예컨대 native가 만든 thread에서 — 호출된 retained 콜백의 panic은
  그 handle의 다음 method 호출에서 다시 일어난다.
- 모든 public opaque receiver와 handle 인자는 cgo 진입 전에 nil·closed 상태를 검사한다.
  검사 실패는 `*HandleError`로 반환하며, 오류 반환이 없던 메서드에는 `error` 결과가
  추가된다. Tagged-union의 `Tag`와 `As*`도 같은 상태를 error로 반환하고, `MustTag`와
  `MustAs*`만 typed error로 panic한다.
- tagged-union projection은 별도 status `3`으로 실제 Zig panic을 구분해
  `*NativePanicError`로 반환한다. null handle과 필수 out 파라미터는 status `2`로
  거부하지만, `SIGSEGV` 같은 하드웨어 fault나 손상된 native 메모리까지 복구하지는 않는다.
- cgo 호출 비용은 무시할 수 없다. 호출당 작업이 작은 API를 그대로 노출하기보다 배치
  지향 함수를 제공하는 편이 낫다.
- retained Go 콜백과 포인터는 생성된 `Close` 경로에서 해제될 때까지 유효해야 한다.
  소유 객체는 사용 후 반드시 닫고, 콜백에서 발생한 panic의 전달 규칙도 테스트한다.
- handle은 잠금이 아니라 진행 중 호출 수로 지켜진다. 생성된 메서드, tagged-union
  projection(`Tag`/`As*`/`Snapshot`/`Variant`), borrowed `Ref`는 호출 전에 receiver와
  handle 인자를 획득하고 돌아온 뒤 놓으며, `Close`는 표시만 하고 마지막 호출이 돌아올 때
  해제된다. 어떤 호출도 다른 goroutine의 native 호출 뒤에서 기다리지 않는다. 특히
  `Close`가 대기 중이라고 해서 이후의 호출(예: 다른 스레드의 `cancel`)이 막히지 않고,
  즉시 `*HandleError`를 받는다. `Close`가 돌아왔다고 native 메모리가 이미 해제된 것은
  아니다. 진행 중이던 호출이 돌아오는 시점에 해제된다.
- `runtime.AddCleanup` 안전망은 실행 시점과 프로그램 종료 전 실행을 보장하지 않는다.
  callback이 소유 객체를 캡처하는 강한 참조 순환과 특정 thread에서만 가능한 해제를
  해결하지 않으므로 명시적 `Close`의 대체로 사용하지 않는다.
- `errors.lock.json`의 정수 코드는 append-only 계약이다. 삭제된 에러의 코드를 다른
  에러에 재사용하지 않는다.
- purego 백엔드는 기본적으로 바인딩 호출 전에 `LoadLibrary`가 성공해야 한다.
  `library_loading.loader`를 `.automatic`으로 두면 첫 호출에서 한 번 자동으로 시도하지만, 모든 후보가
  실패하면 panic한다. 공개 API가 오류를 반환하지 않는 형태이므로 다른 선택지가 없다. 로드는 원자적이라
  실패해도 부분적으로 호출 가능한 패키지를 남기지 않지만, 성공한 라이브러리는 프로세스
  수명 동안 언로드하지 않는다. `LoadLibrary`는 임의의 네이티브 코드를 로드하므로
  애플리케이션이 통제하는 경로만 넘긴다.
- purego 콜백은 고유 시그니처마다 영구 dispatcher를 만든다. 콜백 panic은 부호 있는
  32비트 콜백 결과에서 `-3`으로 native에 전달된 뒤 위 규칙대로 다시 일어나고, 이미
  해제된 토큰 호출은 `-4`로 변환된다. 세부 사항은
  [공유 라이브러리와 purego](purego.md)에 있다.

## 생성물 관리

생성된 Go 파일과 ABI metadata는 커밋하고 CI에서 `go-check`를 실행합니다. 독립 배포
버전과 호환성을 보증할 때는 `abi_base`와 `abi-check`도 사용합니다. raw package 경로를
바꾼 뒤에는 이전 `_gen.go`를 직접 삭제해야 합니다.

생성기는 모든 산출물을 메모리에서 준비한 뒤 쓰므로 검증·렌더링·메모리 실패에는 기존
tree가 유지됩니다. 다만 최종 파일 쓰기 중 전원 차단이나 filesystem 장애가 발생했을 때
여러 파일을 하나의 transaction으로 복구하는 것까지는 보장하지 않습니다. 파일별 역할과
commit·CI 정책은 [생성물과 CI 관리](generated-code.md)가 정본입니다.

제약의 설계 근거와 전체 리스크 목록은 [제약과 리스크](.agent/design/00-constraints.md)에 있다.
