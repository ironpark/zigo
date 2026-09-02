# Changelog

형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를 따르고, 버전은
[Semantic Versioning](https://semver.org/lang/ko/)을 따릅니다. 0.x 동안은 minor 버전이
생성물의 C ABI 또는 `semantic.json` 계약이 바뀌는 릴리스를 뜻합니다.

## [0.4.0] - 2026-09-03

### Added

- `go_package_path` 옵션을 추가했습니다. 공개 Go 패키지 이름과 생성 경로를 분리하며,
  `"."`을 지정하면 `go_dir`의 모듈 루트에 생성되어 `<go_module>` 자체로 import할 수
  있습니다. 같은 경로의 `raw_package`는 계속 colocate됩니다.
- `.types`의 enum 등록에 `.exhaustive = false` opt-in을 추가했습니다. Zig non-exhaustive enum을
  cgo와 purego에서 이름 붙은 상수 밖의 값까지 그대로 왕복하며, 생성된 Go `String()`은
  미지의 값을 `Type(N)`으로 표시합니다. opt-in이 없으면 기존 `ZIGO002`가 유지되고,
  exhaustive enum에 잘못 붙이면 `ZIGO029`입니다.
- 다른 handle의 메서드인 생성자를 지원합니다. 예를 들어 allocator가 주입되는
  `fn newStream(gpa, terminal: *Terminal) !*Stream`은
  `func (t *Terminal) NewStream() (*Stream, error)`가 되고, 반환된 `Stream`은 자신의
  destructor와 짝지어진 caller-owned handle입니다.
- `cgo_flags.extra_ldflags`를 추가했습니다. 기본 또는 override LDFLAGS 뒤, module의 system
  library 앞에 추가됩니다.
- `.cgo_static`이 module의 `.other_step` 정적 라이브러리와 `.static_path` archive를 절대
  경로로 최종 cgo 링크에 전달하고, install step도 그 artifact에 의존합니다. cache 경로는
  commit하지 않는 별도 Go 파일에만 기록되어 `go-check`는 플랫폼 간 결정성을 유지합니다.

### Fixed

- method receiver의 한 글자 이름이 같은 함수의 파라미터와 겹쳐(`Terminal.setTitle(t)` 등)
  컴파일되지 않던 문제를 고쳤습니다. receiver 타입 snake_case 이름의 가장 짧은 비충돌
  접두사를 쓰고 모든 함수 emit 경로가 같은 이름을 공유합니다.
- handle·승격 정수 범위·optional handle 파라미터 검사가 실패할 때 optional 반환의 presence
  값이 빠져 Go 반환값 개수가 부족하던 문제를 고쳤습니다. 직접 optional과 error union 안의
  optional 모두 이제 `zero, false, err`를 반환합니다.
- `addStandardSteps`가 네이티브 바인딩 라이브러리를 기본 `install` 스텝에도 연결합니다.
  plain `zig build` 뒤에 `zig-out/lib`를 바로 사용할 수 있으며,
  `.install_library_by_default = false`로 이 연결을 끌 수 있습니다.

## [0.3.3] - 2026-09-02

### Fixed

- 주입 파라미터(`std.mem.Allocator`, `std.Io`)가 handle보다 앞에 선언된 함수
  (`fn freeTerminal(gpa: Allocator, self: *Terminal) void`)도 메서드와 `.destroys` 대상으로
  인식합니다. receiver 판정이 주입 파라미터를 건너뛰고, shim은 `self`를 Zig가 선언한
  자리에 넣어 호출합니다. `semantic.json`은 이 경우에만 `receiver_at`을 적습니다.

## [0.3.2] - 2026-09-02

### Added

- 함수 메타 `.constructs = "<Type>"` / `.destroys = "<Type>"`. 타입 밖에 자유 함수로
  선언된 생성자와 소멸자를 이름 규칙과 무관하게 짝지어 Go의 생성자와 `Close()`로
  내보냅니다. 메타가 없으면 기존 이름 규칙이 그대로 fallback으로 남습니다.

### Fixed

- 타입 밖에 선언된 함수가 생성자·소멸자로 짝지어지거나 handle 파라미터로 메서드가 될 때,
  shim이 선언되지도 않은 `target.<Type>.<name>` 경로를 부르던 문제를 고쳤습니다. Go의
  소속(`go_owner`)과 Zig 호출 경로(`zig_path`)가 `semantic.json`에서 분리되었고, `.name`으로
  이름을 바꾼 함수도 원래 선언을 부릅니다.
- `.params`가 주입 파라미터(`std.mem.Allocator`, `std.Io`)를 세지 않습니다. 이름을 Go에
  보이는 파라미터만 적으면 되고, 개수가 맞지 않으면 zigo 내부의 comptime 인덱스 오류가
  아니라 `ZIGO027` 진단이 나옵니다.
- `.release`가 가리키는 함수가 allocator를 받아도 됩니다. 주입 파라미터를 뺀 시그니처로
  판정하고 shim이 호출할 때 채우므로, 더 이상 `ZIGO016`으로 거부되지 않습니다.
- `abi-diff`가 주입 파라미터를 시그니처 비교에서 제외합니다. allocator를 파라미터로
  받도록 바꾸는 것은 C 시그니처를 움직이지 않으므로 breaking이 아니며, 대신 `go_owner`가
  바뀌면 breaking으로 보고합니다.

## [0.3.1] - 2026-09-02

### Fixed

- `semantic.json`의 `source.path`가 생성기를 호출한 디렉터리에 따라 달라지던 문제를
  고쳤습니다. 이제 `bindings.zig`가 있는 디렉터리 기준 상대 경로를 `/` 구분자로 기록하므로
  같은 소스는 어디서, 어느 OS에서 생성해도 같은 바이트가 나옵니다. 0.3.0으로 생성한
  `semantic.json`은 재생성해야 `go-check`가 통과합니다.

## [0.3.0] - 2026-09-02

### Breaking

- 공개 Go 시그니처에 `error`가 있는 모든 함수의 C ABI가 상태 코드 반환 + `out_result`
  파라미터로 통일됐습니다. 이전에는 error union을 반환하는 함수만 그랬고, handle이나 승격
  정수 때문에 `error`가 붙은 함수는 C 래퍼의 패닉 착지점에 돌려줄 상태가 없어 zero value를
  반환했습니다 — 즉 fatal한 Zig 패닉이 조용한 성공이 됐고 handle도 poison되지 않았습니다.
  이제 그런 함수의 패닉은 `*NativePanicError`로 돌아오고 handle을 poison합니다. C 헤더와
  raw Go 계층의 시그니처가 바뀌므로 직접 링크하는 코드는 재생성이 필요합니다. (계획 69)
- `error`를 반환하지 않는 순수 함수의 패닉은 이제 메시지를 stderr에 적고 `abort()`합니다.
  이전에는 zero value를 반환했습니다. (계획 69)
- 승격된 정수 파라미터(`u21`, `i24` 등)를 받는 함수의 공개 Go 시그니처가 `error`를 하나 더
  반환합니다. 범위 검사가 shim이 아니라 cgo 호출 이전의 Go에서 일어나므로, 범위 밖 인자는
  native를 부르지 않고 `*RangeError`(`errors.Is(err, ErrOutOfRange)`)로 돌아옵니다. C ABI는
  바뀌지 않습니다. (계획 69)

### Added

- 함수 메타 `.cancel = .{ .param = "..." }`로 긴 native 호출을 Go `context.Context`로 끊을 수
  있습니다. 지정한 파라미터(타입은 `*const std.atomic.Value(u32)`)는 Go 시그니처에서 사라지고
  `ctx context.Context`가 첫 인자가 됩니다. 호출마다 Go가 플래그 워드를 하나 만들고
  `ctx.Done()`을 감시하는 goroutine이 그것을 세우며(호출이 끝나면 정리), Zig가
  `error.Canceled`를 돌려주고 ctx가 실제로 취소됐으면 `ctx.Err()`가 반환됩니다. 폴링은 원자적
  load 하나라 경계를 넘지 않습니다. 취소는 협조적이라 대상 함수가 플래그를 읽어야 합니다.
  `.cancel`이 없는 함수의 생성물은 바이트 그대로입니다. (계획 72)

- Zig 메서드가 스트림을 **내주는** 방향을 지원합니다. `fn writer(self) *std.Io.Writer`는
  handle에 `Write([]byte) (int, error)`와 `Flush() error`를, `fn reader(self) *std.Io.Reader`는
  `Read([]byte) (int, error)`(끝은 `io.EOF`)를 생성하므로 `io.Copy`가 양방향으로 그대로
  동작합니다. 포인터는 Go로 건너가지 않고 shim이 매 호출마다 접근자를 다시 부르므로 보관된
  스트림이 상할 일이 없고, 수명은 receiver handle의 기존 획득·해제·poison 규칙이 답합니다.
  스트림 반환은 파라미터 없는 메서드에서 반환 타입 그 자체여야 하며, 아니면 `ZIGO023`입니다.
  (계획 72)

- Go 콜백이 `error`를 돌려줄 수 있습니다. `param_meta.<이름>.go_error = true`를 켜면 Go 콜백
  타입이 `func(...) (i32, error)`가 되고, 콜백이 돌려준 error는 native 호출이 끝난 뒤 공개
  함수에서 `*CallbackError`(`errors.Is(err, ErrCallbackFailed)`, `Unwrap`으로 원래 error)로
  돌아옵니다. trampoline은 error를 저장하고 native 쪽에 `-5`를 돌려줍니다 — `-3`(panic),
  `-4`(삭제된 토큰)와 구별됩니다. retained 콜백의 error는 그 handle을 건드리는 다음 호출에서
  나옵니다. Zig 콜백 반환은 `i32`여야 하며 아니면 `ZIGO025`입니다. 기본값은 꺼짐이라 기존
  바인딩의 생성물은 바뀌지 않고, C ABI도 바뀌지 않습니다. (계획 72)

- `*std.Io.Reader` 파라미터에 무콜백 경로가 생겼습니다. Go `io.Reader`가 `Bytes() []byte`
  (`*bytes.Buffer`)나 `zigoBytes() []byte`(직접 정의한 타입을 위한 훅)를 가지면 남은 바이트가
  슬라이스 하나로 넘어가고, shim이 `std.Io.Reader.fixed`로 감싸므로 경계를 넘는 콜백이
  **0회**입니다. C ABI는 계획 70이 미리 잡아 둔 `(<name>_data, <name>_data_len)` 자리를 그대로
  쓰므로 바뀌지 않습니다. 이 경로에서는 소비한 바이트 수가 보고되지 않아 Go reader가
  전진하지 않습니다. 그 밖의 reader는 예전처럼 트램폴린으로 읽습니다. (계획 72)

- slice·문자열 optional(`?[]T`, `?[]const u8`, `?[:0]const u8`)을 매개변수, 반환값,
  error union payload 자리에서 지원합니다. presence 플래그를 더하지 않고 slice 자신의
  포인터가 부재를 나릅니다(`ptr == NULL`), 그래서 부재와 길이 0인 존재하는 slice가
  구별됩니다. Go에서는 매개변수가 `*[]T`/`*string`, 반환이 `([]T, bool)`/`(string, bool)`
  입니다. 반환은 기존 슬라이스 반환의 소유권 규칙(`.release` 포함)을 그대로 따릅니다.
  cgo와 purego 모두 지원합니다. `.out` slice를 optional로 만들거나, slice의 slice와
  `extern struct` slice를 optional로 만드는 것은 거부합니다. (계획 71)
- scalar·bool·enum·`extern struct` optional(`?T`)을 매개변수, 반환값, error union
  payload 자리에서 지원합니다. 이전에는 선언된 opaque type의 pointer(`?*T`)만 가능했고
  나머지는 reflection 단계의 컴파일 오류였습니다. 매개변수는 nullable pointer
  하나(`const T *`, NULL = 부재)로, 반환은 presence `bool` 반환 + `T *out_result`로,
  `E!?T`는 상태 코드 + `bool *out_result_has` + `T *out_result`로 내려갑니다. Go에서는
  매개변수가 `*T`(nil = 부재), 반환이 `(T, bool)` 또는 `(T, bool, error)`가 되므로 부재와
  "값이 0인 present"가 구별됩니다. cgo와 purego 모두 지원하며, 새 kind가 늘어난 것이라
  기존 바인딩의 ABI는 그대로입니다. `extern struct`의 field, callback signature, slice
  원소(`[]?T`), optional의 optional은 `ZIGO019`로 거부합니다. `abi-check`는 `T`와 `?T`
  사이의 변경을 breaking으로 봅니다. (계획 71)
- `*std.Io.Writer`/`*std.Io.Reader` 파라미터를 지원합니다. Go에서는 `io.Writer`/`io.Reader`가
  되고, shim이 만든 어댑터가 staging 버퍼(기본 65536, `param_meta.<name>.buffer`로 조정,
  4096..16777216)를 채울 때만 Go로 건너갑니다 — 총 `N` 바이트 출력의 `Write` 호출은
  `ceil(N / 버퍼)`회를 넘지 않습니다. Go `Write`/`Read`의 error는 `*StreamError`(`Unwrap`으로
  원 error, `errors.Is` 가능)로 돌아오고 native 상태 코드보다 우선하며, Go panic은 기존
  `*CallbackPanicError` 경로로 재전파되고, `nil` 스트림은 `ErrNilStream`으로 거부됩니다.
  cgo와 purego 모두 지원하며, 새 kind가 늘어난 것이라 기존 바인딩의 ABI는 그대로입니다.
  파라미터 자리 밖(반환, 필드, 콜백 시그니처, 슬라이스 원소, optional)과
  `.retention = .retained`는 `ZIGO023`으로 거부합니다. (계획 70)
- 생성될 Go 이름이 생성 전에 검사됩니다. 등록된 타입 이름, 필드·enum tag 이름, 함수 이름 중
  Go 식별자가 될 수 없는 것이 있으면 `ZIGO021`이 Zig 타입 경로와 함께 거부합니다. 이전에는
  `@typeName`이 `...[0..4])`로 끝나는 comptime 생성 타입의 이름이 그대로 `.go` 파일에 실려
  gofmt에서야 터졌습니다. (계획 69)
- `.allocator`가 설정되어 있으면 값으로 반환하는 `init`(`T`/`!T`)도 생성자로 인정됩니다.
  shim이 `create`/`init`/실패 시 `destroy`를 하고, 짝 `deinit` 래퍼가 `deinit` 뒤에
  `destroy`까지 합니다. Go에서는 다른 handle과 같은 `New…`/`Close` 쌍입니다. (계획 69)
- 바인딩의 `.allocator`와 `.io`로 `std.mem.Allocator`, `std.Io` 파라미터를 주입할 수
  있습니다. 그 파라미터는 C와 Go 시그니처에서 빠지고 shim이 지정한 식을 넘깁니다. 설정
  없이 만나면 `ZIGO022`로 거부합니다. (계획 69)
- `.types`에 `.repr = .enumeration`으로 enum을 등록하고 `.name`으로 Go/C 이름을 지정할 수
  있습니다. `@typeName`이 이름이 아닌 comptime 생성 enum(ghostty의 `lib.Enum(...)`)을 facade
  없이 바인딩할 수 있습니다. 이미 등록된 enum은 signature가 닿을 때 Zig 경로로 조회되므로
  이름이 한 번만 정해집니다. (계획 69)
- 승격된 정수 파라미터를 가진 바인딩의 errors 파일에 `ErrOutOfRange` sentinel과 `RangeError`
  타입이 생성됩니다. `Operation`, `Parameter`, `Type`으로 어떤 인자가 어떤 Zig 폭을 넘겼는지
  알 수 있습니다. (계획 69)

### Changed

- 패키지 doc은 `go_package_doc` → `bindings.zig`의 `//!` → 라이브러리 루트 모듈의 `//!` →
  기본 문장 순으로 정해집니다. 남이 쓴 라이브러리를 바인딩할 때 Zig 사용자를 향해 쓰인 루트
  주석이 Go 패키지 doc이 되지 않도록, 바인딩 작성자가 소유한 파일이 먼저입니다. (계획 69)

## [0.2.0] - 2026-09-02

### Breaking

- `.written = .return`인 out 슬라이스 파라미터는 C 시그니처에서 `_written` out 파라미터를
  더 이상 갖지 않습니다. 쓴 개수는 함수의 반환값 하나로만 전달됩니다. `abi-check`는
  `.all`과 `.return` 사이의 변경을 breaking으로 보고합니다. (계획 68)
- `u21`, `i24` 같은 2의 거듭제곱이 아닌 정수 폭이 C 경계에서 다음 2의 거듭제곱으로
  승격됩니다(`u21` → `uint32_t`, Go `uint32`). 이전에는 거부됐으므로 기존 바인딩의 ABI는
  바뀌지 않지만, `semantic.json`의 `bits`는 원래 폭을 유지하고 폭 변경은 breaking입니다.
  (계획 67)

### Added

- 바인딩 경로가 임의 깊이의 네임스페이스 struct를 따라갑니다. `root.unicode.codepointWidth`
  같은 경로가 동작하며, 네임스페이스는 C 심볼(`zg_unicode_codepoint_width`), raw Go 이름,
  `semantic.json` identity(`unicode.codepointWidth`)에 반영됩니다. 공개 Go 이름은 마지막
  세그먼트만 씁니다. `.discover = .recursive`로 중첩 컨테이너 발견을 켤 수 있고, 기본값
  `.public`은 그대로 1단계입니다. (계획 67)
- 지원되지 않는 타입이 위치 있는 진단으로 보고됩니다. `ZIGO018`(정수·실수 폭),
  `ZIGO019`(타입), `ZIGO020`(IR 버전), `ZIGO021`(이름)이 함수, 파라미터, Zig 타입 철자를
  담아 출력되며 스택 트레이스 대신 진단만 나옵니다. reflection 단계의 `@compileError`도
  함수 경로와 파라미터 이름을 포함합니다. (계획 67)
- 범위를 벗어난 승격 정수 인자는 shim이 검사해 기존 패닉 브리지를 통해 Go
  `NativePanicError`로 돌아옵니다. extern struct 필드, 슬라이스 원소, callback 시그니처의
  비 2의 거듭제곱 폭은 이유를 담은 `ZIGO018`로 계속 거부됩니다. (계획 67)
- `LockOSThread` 비용 벤치마크가 07-event-queue에 추가됐고 결과가 `docs/limitations.md`에
  기록됐습니다. 가벼운 error union 호출에서 약 2%라 패닉 메시지 ABI는 바꾸지 않았습니다.
  (계획 68)

### Changed

- 패키지 doc의 fallback 소스가 `bindings.zig`의 `//!`에서 라이브러리 루트 모듈의 `//!`로
  바뀌었습니다. 순서는 `go_package_doc` 옵션, 루트 모듈 `//!`, 기본 문장입니다. (계획 68)
- handle을 획득하는 호출 경로에서 잉여 `defer runtime.KeepAlive`가 제거됐습니다.
  `defer x.zigoRelease()`가 이미 handle을 함수 끝까지 붙잡습니다. `Close`와 Go 메모리를 C에
  넘기는 경우의 `KeepAlive`는 유지됩니다. (계획 68)
- Go 타입 이름이 선언 폭이 아닌 승격 폭으로 표기됩니다. (계획 67)

## [0.1.0] - 2026-09-02

첫 태그 릴리스입니다. 이 릴리스까지의 주요 내용은 다음과 같습니다.

### Handle 모델

- handle은 잠금 대신 호출 수를 셉니다. `Close`는 표시만 하고 마지막으로 나가는 호출이
  자원을 해제하므로 어떤 호출자도 다른 호출자를 기다리지 않습니다.
- Zig 패닉이 통과한 handle은 poison되어 이후 호출이 `NativePanicError`로 거부되며,
  native 자원은 해제하지 않고 남깁니다.
- 런타임 심볼에 접두어가 붙어 두 바인딩이 한 바이너리를 공유할 수 있습니다.

### 슬라이스와 extern struct

- out 슬라이스 파라미터에 `.written = .return` 힌트가 추가됐습니다. native가 반환한
  개수만 채워지고 그 뒤 원소는 호출 전 값 그대로입니다.
- bool 필드가 없는 extern struct 슬라이스는 cgo에서도 캐스트 한 번으로 넘어가고, Go 쪽
  컴파일 시점 레이아웃 가드가 그 근거를 고정합니다. 반환 경로도 raw 계층이 소유한 할당을
  재해석해 두 번째 복사를 하지 않습니다.
- 에러 유니온 슬라이스 payload, 호출자 소유 슬라이스 반환과 해제 함수, 문자열 슬라이스
  파라미터, sentinel C 문자열을 지원합니다.

### 메타데이터와 문서

- `semantic.json`의 `symbol`이 실제 export 심볼과 일치합니다. `abi-check`는 옛 규칙에서
  새 규칙으로의 1회 정정을 compatible로 봅니다.
- 생성된 Go doc이 식별자로 시작하지 않는 문장을 두 줄 형식으로 내고, `//` 그룹 주석과
  빈 줄 없이 이어진 선언의 doc 공유를 지원합니다. 모든 생성 패키지에 패키지 doc이 있습니다.

[0.4.0]: https://github.com/ironpark/zigo/compare/0.3.3...0.4.0
[0.3.3]: https://github.com/ironpark/zigo/compare/0.3.2...0.3.3
[0.3.2]: https://github.com/ironpark/zigo/compare/0.3.1...0.3.2
[0.3.1]: https://github.com/ironpark/zigo/compare/0.3.0...0.3.1
[0.3.0]: https://github.com/ironpark/zigo/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/ironpark/zigo/compare/0.1.0...0.2.0
[0.1.0]: https://github.com/ironpark/zigo/releases/tag/0.1.0
