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
  `linkLibrary`로 붙인 정적 라이브러리는 reflection용 호스트 변형을 만들며, 재귀적인 module
  설정과 설치 헤더, libc/libc++ 요구를 보존한다. 동적 라이브러리와 `.static_path` archive는
  호스트 reflector에 링크하지 않으므로 reflection 중 실제로 그 심볼을 호출하는 코드는
  지원하지 않는다.
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
- Go 파라미터 이름과 함수 본문이 만드는 지역 이름의 충돌 검사는 아직 함수 전체의 이름
  할당기가 아니다. 고정 목록의 `err`, `code`, `result` 등은 `err_`, `code_`, `result_`로
  escape하지만, handle receiver 검사에서 생기는 `ptr`이나 파라미터에서 파생되는
  `<name>Ptr`·`<name>Raw`·`<name>Handle` 같은 이름까지 모두 예약하지는 않는다. `.params`로
  이름을 지정할 때 이런 생성 local과 같은 이름은 피해야 하며, 생성 뒤 `go vet ./...` 또는
  `go test ./...`로 확인한다. receiver 자체와 파라미터의 충돌만 별도의 접두 확장 규칙으로
  처리한다.
- 한 Go 실행 파일에 zigo 바인딩을 둘 이상 링크하려면 `prefix`가 서로 달라야 한다.
  생성되는 C 심볼은 런타임 것(`<prefix>_panic_bridge`, `<prefix>_last_error_message`)
  까지 전부 접두사를 쓰므로, 기본값 `zg`를 둘 다 쓰면 정적 링크에서 중복 심볼로 실패한다.
- `go_package_path = "."`은 공개 생성 파일을 `go_dir` 루트에 둔다. stale 정리는 marker 없는
  `go.mod`와 사용자 Go 파일을 보존하지만, `<go_package>_gen.go` 같은 생성 파일명과 사용자가
  만든 파일명이 같으면 생성 단계가 그 파일을 갱신 대상으로 본다. 루트 발행 시 이 이름들은
  생성기 전용으로 비워 둔다.
- 공개 하위 패키지 의존은 DAG만 지원한다. 두 패키지가 서로의 타입을 시그니처나 등록 타입
  필드에서 참조하면 Go import cycle이 되므로 생성 전에 `ZIGO032`로 거부한다. 공통 값 타입을
  세 번째 하위 패키지로 옮기거나 의존 방향을 하나로 정해야 한다.
- `.cgo_static`은 module에 붙은 별도 정적 archive를 최종 cgo LDFLAGS에 나열하지만 fat
  archive로 병합하지 않는다. 따라서 바인딩 archive 하나만 복사해 다른 링커에서 독립적으로
  쓰는 배포물은 만들지 않는다. `compiler_rt`나 `ubsan_rt`가 module의 `.other_step` 또는
  `.static_path`로 드러나면 자동 전달되며, Zig 내부에서만 생성되어 link object로 관찰할 수
  없는 runtime은 `.cgo_flags.extra_ldflags`에 archive 경로를 명시한다. `undefined symbol:
  __ubsan_*` 같은 오류는 그 runtime이 빠졌다는 신호다.

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
- `std.atomic.Value(T)`는 T가 bool, 정수, 부동소수 또는 등록 enum일 때 값 자리에서 T로
  노출된다. field accessor 한 번은 `seq_cst` load/store지만, 여러 atomic field를 담은 struct나
  union snapshot 전체는 원자적이지 않다. atomic field가 있는 `extern struct` slice는 항상
  원소별 복사 경로를 사용한다.
- atomic 포인터 파라미터는 `*std.atomic.Value(u32|i32|u64|i64)`와 const 변형만 지원하며
  Go에서는 대응하는 `*sync/atomic` 타입이다. 주소는 호출 범위에서만 빌리므로 retained는
  `ZIGO043`이고, native가 주소를 저장하거나 호출 뒤 사용하는 것은 정의되지 않는다. `.cancel`
  플래그는 계속 별도 `context.Context` 계약을 따른다.
- `.direction = .out` slice에 `.written = .@"return"`을 쓰려면 반환 payload가
  `usize`(또는 `!usize`)여야 하고, `.out`이 아닌 파라미터에는 붙일 수 없다. 둘 다
  `ZIGO017`로 거부된다.
- native 메모리를 그대로 들여다보는 뷰 반환은 제공하지 않는다. 반환된 slice의 수명이
  native 객체의 수명에 묶이면 Go 쪽에서 그 규칙을 강제할 방법이 없기 때문이며, 복사를
  피하고 싶다면 `.direction = .out` 파라미터로 결과를 받는다.
- `*std.Io.Writer`/`*std.Io.Reader`를 **받는** 자리는 파라미터뿐이고 call-scoped만 된다. shim이
  만드는 어댑터가 호출 스택에 살기 때문이다. extern struct 필드, 콜백 시그니처, 슬라이스
  원소, optional, `.retention = .retained`는 `ZIGO023`으로 거부된다. handle에 보관되는 스트림,
  `std.Io.File`/fd 전달, `sendFile` 최적화, Go `io.ReaderAt`/`io.Seeker`는 지원하지 않는다.
- 스트림을 **내주는** 쪽(`fn writer(self) *std.Io.Writer`)은 파라미터 없는 메서드여야 하고
  스트림이 반환 타입 그 자체여야 한다(error union·optional 안은 `ZIGO023`). 포인터는 Go로
  건너가지 않고 handle의 `Write`/`Flush`/`Read`가 생성되며, 매 호출마다 접근자를 다시
  부른다. 한 타입이 같은 방향의 스트림을 둘 내주면 Go 메서드 이름이 겹쳐 `ZIGO024`다.
- `.go_error` 콜백이 error를 돌려주면 native 쪽은 결과로 `-5`를 받는다. 대상 Zig 함수가
  그것을 어떻게 다루는지는 zigo가 강제하지 않는다 — 계속 콜백을 부르는 함수는 계속 불린다.
  Go error가 나면 멈춰야 하는 API라면 Zig 쪽이 `-5`를 검사해야 한다. `go_error`는 하나의
  ABI 시그니처 전체의 성질이라, 한 파라미터에 켜면 그 시그니처를 쓰는 모든 콜백 파라미터의
  Go 타입이 함께 넓어진다.
- 스트림 콜백은 native 호출 안에서 같은 스레드로 동기 호출된다. 대상 Zig 함수가 어댑터를
  다른 스레드로 넘기거나 호출이 끝난 뒤까지 들고 있으면 동작은 정의되지 않는다.
- `io.Reader` 인자가 `Bytes() []byte`나 `zigoBytes() []byte`를 가지면 남은 바이트가
  슬라이스 하나로 넘어가고 콜백은 0회다. 이 경로에서는 zigo가 Go reader를 **전진시키지
  않는다** — ABI가 소비한 바이트 수를 보고하지 않기 때문이다. 호출 뒤에도 `*bytes.Buffer`에는
  같은 바이트가 남아 있으므로, 소비 위치가 중요한 reader는 빠른 경로에 들어가지 않는
  타입(`bytes.NewReader` 등)으로 넘긴다.
- 취소는 **협조적**이다. `.cancel` 함수가 플래그를 폴링하지 않으면 아무 일도 일어나지
  않는다 — zigo는 native 스레드를 강제로 중단하지 않고, 그럴 수 있는 안전한 방법도 없다.
  폴링 간격이 곧 취소 지연이다. 플래그의 주소는 호출 동안만 유효하므로 대상 함수가 그것을
  보관하거나 다른 스레드로 넘겨 호출 뒤에 읽으면 동작은 정의되지 않는다.
- 정수 backing의 `packed struct`는 `.repr = .value`로 등록할 수 있다. 필드는 bool, 정수,
  등록 enum, 다시 등록한 정수-backed packed struct만 가능하며 다른 필드는 `ZIGO044`다.
  C 경계에서는 backing 정수 하나로 전달된다. backing 폭을 유지한 끝 필드 추가만 ABI
  compatible이고 삭제·재정렬·폭/타입 변경은 breaking이다.
- optional은 매개변수, 반환값, error union payload 자리에서만 쓸 수 있고, child는 bool,
  정수, 부동소수, 등록 enum, 등록 packed value, `extern struct`, 선언된 opaque type의 pointer만 지원한다.
  매개변수는 nullable pointer 하나로(NULL = 부재), 반환은 presence `bool`과 out
  parameter로 내려간다. `extern struct`의 field, callback signature, slice
  원소(`[]?T`), optional의 optional(`??T`)은 presence를 실을 자리가 없어 `ZIGO019`로
  거부된다.
- slice·문자열 optional(`?[]T`, `?[]const u8`, `?[:0]const u8`)은 slice 자신의 포인터가
  부재를 나른다: `ptr == NULL`이 부재이고 길이 0인 존재하는 slice와 구별된다. Go에서는
  `*[]T`/`*string`이 되고 반환은 `([]T, bool)`/`(string, bool)`이다. `.out` slice를
  optional로 만들거나(버퍼는 호출자가 잡는다), slice의 slice(`?[][]const u8`),
  `extern struct` slice(`?[]Point`)를 optional로 만드는 것은 거부된다. caller-owned
  `?[]T`/`!?[]T`는 `.release`가 필요하고, 성공하면서 존재하는 값에만 복사와 release를
  수행한다. Go 결과는 `([]T, bool)`/`([]T, bool, error)`이며 c_string은 `string`을 쓴다.
- tagged union은 `.repr = .tagged_union`으로 등록한다. pointer handle 표현은 생성된
  `Tag`/`As*`가 active tag를 검사하며 union 레이아웃을 C로 전달하지 않는다. 모든 payload가
  void, bool, 8/16/32/64비트 정수, `isize`/`usize`, 부동소수 scalar, 또는 등록 enum인 union은
  함수의 전체 매개변수로 값을 직접 전달할 수도 있다. 이때 C ABI는 tag와 선언 순서의
  non-void payload slot으로 평탄화하고 Go에는 variant constructor와 `Tag()`가 있는 value
  type을 생성한다. variant 추가는 signature가 늘어나는 breaking change다. slice, pointer,
  struct payload는 `ZIGO006`으로 계속 거부하며, union 값 반환과 중첩 union 값도 지원하지
  않는다. 같은 등록 union을 pointer handle과 값 매개변수 양쪽으로 동시에 쓰는 것도
  지원하지 않으므로 값 전달용 scalar union을 별도 타입으로 둔다.
- non-exhaustive enum은 `.repr = .enumeration, .exhaustive = false`로 명시 등록한 경우에만
  노출한다. 그때 이름 붙은 tag 밖의 값도 유효하며 파라미터·반환·struct 필드·slice 원소에서
  정수 그대로 왕복한다. opt-in이 없으면 `ZIGO002`다. non-exhaustive tag를 가진 tagged union은
  projection과 snapshot이 닫힌 tag 집합을 전제로 하므로 opt-in 대상이 아니며 계속 거부한다.
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
  `![]T`, `?[]T`, `!?[]T`에도 쓸 수 있으며, 복사와 release는 성공하면서 값이 존재하는
  경로에서만 일어난다.
- slice 반환의 원소는 스칼라, 등록된 enum, `extern struct`만 가능하다. 포인터를 포함하는
  원소는 `ZIGO005`로 거부한다. `![]T`와 `!?[]T`도 같은 규칙을 따르며, `![]string`은
  지원하지 않는다.
- `.returns = .borrowed`는 receiver가 있는 메서드의 등록 opaque pointer 반환에만 쓸 수 있다.
  자유 함수에는 수명을 묶을 owner가 없고, slice·scalar·struct 반환은 borrowed handle이
  아니다. borrowed view를 caller-owned로 승격하거나 부모보다 오래 살게 만드는 API는 없다.
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
- C가 이름 붙일 수 없는 정수 폭(`u21`, `i24`)은 파라미터·반환값·error union payload와
  직접 non-sentinel slice 원소에서 다음 2의 거듭제곱 폭으로 승격된다. 승격된 파라미터가 있는 함수는 공개 Go 시그니처가
  `error`를 하나 더 반환하고, 범위 검사는 cgo 호출 전에 Go에서 이뤄져 `*RangeError`
  (`errors.Is(err, ErrOutOfRange)`)로 돌아온다. shim의 범위 검사는 raw 패키지를 직접 부르는
  코드를 위한 두 번째 방어선으로 남는다.
  narrow integer 입력·out slice는 `.allocator`로 원소 타입의 임시 버퍼를 만들며, 설정이 없으면
  `ZIGO045`다. caller-owned 반환 slice는 `.release`가 있을 때 원소별 승격 복사하고, borrowed
  반환과 optional/sentinel narrow slice는 `ZIGO018`로 거부한다. `extern struct`/value struct
  field, union payload, callback 시그니처, 중첩 slice의 규칙은 바뀌지 않았다. 65비트 이상의
  정수와 `f80`은 어디서도 지원하지 않는다.
- 지원 타입과 정확한 하강 규칙은 [ABI 하강 규칙](.agent/design/03-lowering-rules.md)을 참고한다.

## 생성기 진단

생성 단계의 모든 거부는 `error[ZIGOnnn]` 진단 한 줄로 나온다. 스택 트레이스나 bare error는
남아 있지 않으며, 진단은 문제가 된 선언(`Owner.fn`이나 `namespace.fn`)과 파라미터 이름,
그리고 Zig 쪽 철자를 함께 알려준다.
이름이나 수명 계약을 고칠 수 있는 구체적인 대안이 있으면 `hint:` 다음의 `note:`가
그 선언에 적용할 수 있는 `.name`이나 release 함수 철자를 제안한다. `note:`는 해결 방법만
설명하며 진단 결과 자체에는 영향을 주지 않는다.

```
error[ZIGO018]: unsupported integer width `u21` in parameter `cp`
  --> semantic.json (unicode.codepointWidth)
  hint: use an 8, 16, 32, or 64-bit integer, or `usize`
```

- `ZIGO002` — non-exhaustive enum을 opt-in 없이 노출했다. enum을 exhaustive로 만들거나
  `.types`에 `.repr = .enumeration, .exhaustive = false`로 등록한다. tagged union의
  non-exhaustive tag에는 이 opt-in을 적용할 수 없다.
- `ZIGO018` — C ABI가 이름 붙일 수 없는 정수·실수 폭이다. 중첩된 위치는 `the slice element
  of parameter \`cps\``처럼 도달 경로까지 적는다.
- `ZIGO019` — 지원하지 않는 타입이다. optional이 매개변수·반환·error payload가 아닌
  자리에 있으면 실을 presence 자리가 없다는 힌트와 함께 이 코드로 거부된다.
- `ZIGO020` — `semantic.json`의 IR 버전이 이 zigo와 맞지 않는다. 다시 생성한다.
- `ZIGO022` — `std.mem.Allocator`나 `std.Io` 파라미터를 만났는데 바인딩이 `.allocator`나
  `.io`를 정하지 않았다. 이 두 타입만 주입 대상이며, 그 밖의 Zig 전용 타입은 여전히
  `ZIGO019`다.
- `ZIGO023` — `*std.Io.Writer`/`*std.Io.Reader`를 쓸 수 없는 자리에 썼거나, 스트림에
  `.retention = .retained`를 달았거나, `buffer`가 4096..16777216 밖이거나 스트림이 아닌
  파라미터에 붙었다. 메시지가 넷을 구분한다.
- `ZIGO021` — 이름이 비어 있거나 Go 식별자가 아니다. package, prefix, 함수 이름의 공백과,
  reflection이 유도했든 `.name`으로 준 것이든 생성될 Go 이름이 모두 여기서 검사된다.
  등록된 타입 이름은 Go에 그대로 나가므로 쓰인 철자 그대로, 필드·함수 이름은 zigo가
  PascalCase로 바꾼 뒤의 철자로 판단한다(Zig의 `type` 필드는 Go `Type`이라 통과한다).
  enum tag는 실제 상수 철자 `<Type><Pascal(tag)>` 전체를 검사하므로 `80_cols`도
  `DeccolmMode80Cols`처럼 유효한 이름이 되면 통과한다. Pascal 변환 결과가 비는 tag처럼 실제
  생성 이름을 만들 수 없는 경우는 계속 거부한다.
  `@typeName`이 식별자가 아닌 comptime 생성 타입(`lib.Enum(...)[0..4])`)은 `.types`에
  `.name`과 함께 등록해 이름을 준다. 메시지는 Zig 타입 경로를 함께 적는다.
- `ZIGO024` — 공개 Go 이름이 충돌한다. receiver가 없는 함수는 namespace가 아니라 마지막
  세그먼트(또는 `.name`)만으로 이름이 정해지므로, 서로 다른 namespace의 같은 이름 함수나
  namespace 함수와 등록된 타입이 이름을 나눠 가질 수 있다. 메서드는 receiver별로 이름
  공간이 나뉘므로 다른 receiver의 같은 메서드 이름은 충돌이 아니다. 같은 enum 안에서
  두 tag가 PascalCase로 같은 이름이 되는 경우도 여기서 잡는다. 메시지는 충돌하는 두 Zig
  경로를 모두 적으며, `.name`으로 한쪽 이름을 바꾸면 통과한다. 충돌 범위는 공개 패키지
  하나이므로 서로 다른 `.packages` 항목에서는 같은 이름을 쓸 수 있다.
- `ZIGO025` — `param_meta.<이름>.go_error`를 콜백이 아닌 파라미터에 달았거나, 콜백의 Zig
  반환 타입이 `i32`가 아니다. Go error는 결과 자리에 `-5`로 실려 건너가므로 `i32` 결과가
  없는 콜백은 그것을 알릴 방법이 없다.
- `ZIGO026` — `.cancel`이 존재하지 않는 파라미터를 가리키거나, 그 파라미터 타입이
  `*const std.atomic.Value(u32)`가 아니거나, 함수의 error set에 `Canceled`가 없거나,
  취소 플래그 파라미터가 있는데 `.cancel`이 그것을 가리키지 않는다.

- `ZIGO027` — `.params`가 적은 이름 개수가 Go에 보이는 파라미터 개수와 다르다. receiver와
  주입 파라미터(`std.mem.Allocator`, `std.Io`)는 C에도 Go에도 나타나지 않으므로 `.params`에
  적지 않는다. 메시지는 적은 개수와 기대 개수, 그리고 선언 경로를 적는다.
- `ZIGO028` — `.constructs`/`.destroys`가 등록되지 않은 타입을 가리키거나, `.constructs`를
  단 함수가 그 타입의 pointer를 반환하지 않거나, `.destroys`를 단 함수가 그 타입의
  pointer를 (주입 파라미터를 제외한) 첫 파라미터로 받지 않거나 void를 반환하지 않거나, 한 타입에 대해 한쪽만
  선언했거나, 같은 타입을 둘이 겹쳐 선언했다. 메시지가 이들을 구분한다.
- `ZIGO029` — 실제로는 exhaustive인 enum 등록에 `.exhaustive = false`를 붙였다. opt-in을
  제거하거나 Zig enum을 non-exhaustive로 바꾼다.
- `ZIGO030` — `.child_of_receiver = true`를 receiver constructor가 아닌 함수에 붙였다.
- `ZIGO031` — `.packages`의 경로·이름·selector가 잘못됐거나, 같은 선언을 중복 선택했거나,
  타입과 그 메서드·constructor·destructor를 서로 다른 패키지로 나누려 했다.
- `ZIGO032` — 공개 패키지 타입 참조 그래프에 import cycle이 있다. 메시지는 순환을 만든
  선언과 `a -> b -> a` 형태의 패키지 경로를 함께 적는다.
- `ZIGO033` — `.returns = .borrowed`를 receiver 없는 함수에 붙였다.
- `ZIGO034` — `.returns = .borrowed` 반환이 등록 opaque 타입의 `*T`, `?*T`, `!*T`, `!?*T`가
  아니다.
- `ZIGO035` — constructor가 아닌 메서드가 opaque pointer를 반환하면서 `.returns`를
  생략했다. receiver-owned view면 `.borrowed`, ownership transfer면 constructor/destructor와
  `.caller`를 명시한다.
- `ZIGO036` — lowering 뒤 C 식별자가 충돌한다. 함수 심볼, handle·enum·struct·snapshot
  typedef, enum 상수, projection, runtime helper를 함께 검사하며 진단이 두 선언을 지목한다.
  `.name`이나 바인딩 `.prefix`를 바꿔 구분한다. `note:`는 constructor 이름 변경을 제안하지
  않고, 타입과 함수가 충돌하면 타입 쪽의 구체적인 `.name`을 우선 제안한다.
- `ZIGO037` — opaque 타입의 `.fields` 경로가 없거나, struct 값 또는 non-optional single
  pointer 이외의 값을 가로지르거나, bool·정수·실수·등록 enum 이외의 타입에서 끝난다.
  메시지는 경로와, 경로가 해석된 경우 지원하지 않는 필드 타입을 함께 적는다.
- `ZIGO038` — 명시한 함수 receiver가 등록 opaque 타입의 첫 비주입 pointer 파라미터와
  일치하지 않거나, receiver group의 함수 이름이 `strip_prefix`로 시작하지 않는다.
- `ZIGO043` — atomic 포인터 파라미터의 scalar가 `u32`, `i32`, `u64`, `i64` 중 하나가
  아니거나 `.retention = .retained`를 지정했다. 지원하는 `sync/atomic` 폭을 사용하고 주소는
  호출 범위에서만 빌린다.
- `ZIGO044` — `.repr = .value`인 packed struct에 bool, 정수, 등록 enum, 등록 integer-backed
  packed struct 이외의 필드가 있다. 진단에 표시된 필드를 지원하는 값 타입으로 바꾼다.
- `ZIGO045` — narrow integer를 직접 원소로 둔 입력·out slice의 임시 변환 버퍼에 쓸 allocator가
  없다. 바인딩에 `.allocator = .c_allocator`, `.page_allocator`, `.smp_allocator` 또는 선언 경로를
  지정한다.

`ZIGO027`, `ZIGO028`, `ZIGO037`, `ZIGO038`은 reflection이 문서를 만들기 전에 걸리므로 `semantic.json` 자리가
아니라 선언 경로를 가리키며, 생성기는 이 진단을 출력하고 종료한다.

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

바인딩 경로는 임의 깊이의 namespace struct를 따라간다. `semantic.json`의 `namespace`는 점으로
이은 경로를 담고 심볼·raw Go 이름·ABI identity가 모두 거기서 파생된다. 공개 Go 함수 이름에는
namespace가 들어가지 않으므로, 서로 다른 namespace의 같은 함수 이름은 `.name`으로 구분한다.
구분하지 않으면 생성 시점에 `ZIGO024`로 거부된다.

`.discover = .public`은 공개 Zig API와 바인딩 API가 같은 프로젝트를 위한 opt-in 정책이다.
공개 helper나 지원하지 않는 generic 함수까지 발견될 수 있으므로 `exclude`로 의도를
명시한다. 일부 함수만 안정적으로 노출해야 하는 라이브러리는 명시적인 `functions` 목록을
유지한다. namespace struct 안까지 내려가는 `.discover = .recursive`도 opt-in이며, 기본값은
바뀌지 않는다.

## 런타임 주의사항

- **패닉 규칙**: 생성된 Go 시그니처에 `error`가 있으면 native 패닉은 모두 그 `error`로
  도달하고(그 호출이 닿은 handle은 poison된다), 없으면 패닉은 Zig 의미 그대로 fatal이다 —
  메시지를 stderr에 적고 프로세스를 `abort()`한다. `error`가 붙는 경우는 세 가지다: Zig가
  error union을 반환할 때, receiver나 handle 파라미터가 있을 때, 승격된 정수 파라미터가
  있을 때. 이 함수들은 모두 상태 코드 + `out_result` 모양의 C ABI를 쓴다. 그래서
  "handle을 받지만 오류를 반환하지 않는 함수"의 패닉이 조용한 성공으로 돌아오는 일은
  없다. 아무 것도 받지 않는 자유 함수의 패닉을 error로 받고 싶으면 Zig 쪽을 error union으로
  바꾼다.
- Zig panic은 C 경계에서 오류 코드 `-2`와 마지막 오류 메시지로 변환되지만 정상 복구를
  뜻하지 않는다. Go에서는 `errors.Is(err, ErrNativePanic)`으로 판별한다. 메시지를 수집한 뒤
  현재 작업을 중단한다. 메시지는 native 쪽 thread-local에 남으므로, error를 반환하는 생성
  함수와 union accessor는 호출 동안 `runtime.LockOSThread`로 goroutine을 그 thread에
  고정한다. 그 비용은 측정했다(아래).

  `examples/07-event-queue`의 `lock_os_thread_bench_test.go`가 그 비용을 잰다. 생성된
  `EventQueue.Enqueue`와, `LockOSThread` 쌍만 뺀 손으로 쓴 같은 함수를 비교한다
  (Apple M1 Ultra, macOS 15, Go 1.27, `go test -bench . -benchmem -count=5`):

  | 백엔드 | 생성 경로 | `LockOSThread` 없음 | 차이 | 비율 |
  | --- | --- | --- | --- | --- |
  | cgo | 289.2 ns/op | 284.4 ns/op | +4.8 ns | 1.7% |
  | purego | 516.0 ns/op | 505.6 ns/op | +10.4 ns | 2.0% |

  `LockOSThread`/`UnlockOSThread` 쌍만 따로 재면 4.2 ns/op이고, 세 벤치마크 모두
  호출당 추가 할당이 없다(cgo 0 B/op, purego는 두 경로 모두 304 B/op로 동일).

  즉 스레드 고정은 가벼운 error union 호출 총비용의 2% 안쪽이다. 계획 68이 정한
  기준(10% 이상)에 못 미치므로, 패닉 메시지 전달 ABI(전역 슬롯 배열이나 호출자 버퍼
  포인터)로 바꾸지 않는다. 그 변경은 breaking이고 `{prefix}_last_error_message`를
  없애야 하는데, 2%를 위해 치를 값이 아니다. 호출 비용을 지배하는 것은 경계 통과 자체다.

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
  projection(`Tag`/`As*`/`Snapshot`/`Variant`), borrowed handle/`Ref`는 호출 전에 receiver와
  handle 인자를 획득하고 돌아온 뒤 놓으며, `Close`는 표시만 하고 마지막 호출이 돌아올 때
  해제된다. 어떤 호출도 다른 goroutine의 native 호출 뒤에서 기다리지 않는다. 특히
  `Close`가 대기 중이라고 해서 이후의 호출(예: 다른 스레드의 `cancel`)이 막히지 않고,
  즉시 `*HandleError`를 받는다. `Close`가 돌아왔다고 native 메모리가 이미 해제된 것은
  아니다. 진행 중이던 호출이 돌아오는 시점에 해제된다.
- `.child_of_receiver = true`인 constructor가 만든 자식은 부모보다 먼저 명시적으로 닫아야
  한다. 열린 자식이 있으면 부모 `Close`는 `*HandleInUseError`를 반환하고 아무것도 닫지
  않는다. 자식을 자동으로 닫거나 임의의 두 handle 사이 관계를 추론하지 않는다. 특히
  **닫지 않은 자식이 GC되더라도 부모의 자식 카운트를 내리는 것으로 처리하지 않는다**.
  cleanup 안전망의 실행 시점은 보장되지 않고 수명 순서를 대신할 수 없으므로, 이런 자식은
  반드시 `Close`하고 나서 부모를 닫아야 한다.
- borrowed view를 receiver로 자식을 만들면 view 깊이와 관계없이 최종 owning handle에 자식
  하나를 예약하고 같은 handle에서 해제한다. view 자체를 보관하는 것은 자식 수에 포함되지 않는다.
- `.returns = .borrowed` view는 child handle과 달리 native 자원을 소유하지 않으며 매번
  `Close`할 의무가 없다. 부모가 닫히면 자동으로 무효화된다. 다만 view의 native 호출이 진행
  중이면 부모 `Close`는 `ErrHandleInUse`로 거부되며, 호출이 끝난 뒤 다시 닫아야 한다.
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
