# 생성물과 CI 관리

zigo는 Go 소스와 ABI 메타데이터를 소스 트리에 생성하고, 헤더와 네이티브 라이브러리를
`zig-out/`에 빌드합니다. 이 문서는 어떤 파일을 커밋하고 어떤 스텝을 CI에서 실행할지
설명합니다.

## 표준 빌드 스텝

`addStandardSteps`를 호출하면 다음 스텝이 등록됩니다.

| 스텝 | 소스 트리 수정 | 역할 |
|---|---:|---|
| `go` | 예 | Go 소스·메타데이터 생성, 헤더와 네이티브 라이브러리 설치 |
| `go-check` | 아니요 | 커밋된 Go 생성물이 현재 선언과 같은지 검사 |
| `go-report` | 아니요 | 최종 이름, 심볼, ownership, retention과 타입 표현 설명 |
| `go-doctor` | 아니요 | Go, `gofmt`, 백엔드별 도구·아티팩트 전제 검사 |
| `go-lib` | 아니요 | 네이티브 바인딩 라이브러리를 `zig-out/lib`에 설치 |
| `go-verify` | 아니요 | `go-check`, `go-lib`, `go-doctor`, 선택적 `abi-check` 집계 |
| `abi-check` | 아니요 | `abi_base`가 있을 때 breaking contract 변경 검사 |

여러 바인딩 세트에 `name_prefix`를 사용하면 `admin-go`, `admin-go-check`처럼 이름 앞에
접두사가 붙습니다.

## 진단 사용법

환경 문제는 먼저 doctor로 좁힙니다.

```bash
zig build go-doctor
```

cgo 백엔드에서는 네이티브 타깃, Go 최소 버전, `gofmt`, `CGO_ENABLED`와 `go env CC`의
컴파일러를 검사합니다. purego에서는 cgo 대신 지원 호스트, `go.mod`의 purego 요구사항,
설치된 공유 라이브러리의 존재와 실제 로딩을 검사합니다. 다른 purego 버전은 경고이고,
필수 실행 파일·모듈·아티팩트 문제는 실패입니다.

reflection 결과가 예상과 다르면 report를 사용합니다.

```bash
zig build go-report
```

최종 Go 이름과 C 심볼, 타입 표현, constructor/`Close` mapping, ownership,
파라미터 retention과 이름 보강 출처, tagged union projection 및 purego 로딩 정책을
출력합니다. 두 명령 모두 소스와 생성물을 수정하지 않습니다.

## 생성 파일

기본 cgo 구성의 주요 파일은 다음과 같습니다.

```text
go/go.mod
go/internal/raw/raw_gen.go
go/<package>/<package>_gen.go
go/<package>/<package>_enums_gen.go
go/<package>/<package>_structs_gen.go
go/<package>/<package>_handles_gen.go
go/<package>/<package>_runtime_gen.go
go/<package>/<package>_union_<union>_gen.go
go/<package>/<package>_errors_gen.go
zigo/semantic.json
zigo/errors.lock.json
zig-out/include/zigo_<name>.h
zig-out/lib/lib<name>_zigo.a
```

정적 아카이브 이름은 Windows 타깃에서도 `lib<name>_zigo.a`입니다. Zig 관례라면
`<name>_zigo.lib`가 되겠지만, 생성된 `#cgo LDFLAGS` 줄이 모든 호스트에서 같은 경로를
써야 하므로 설치 시점에 이름을 맞춥니다. `zig cc`는 Windows에서도 `.a` 확장자의 COFF
아카이브를 그대로 링크합니다.

purego는 헤더를 `zigo_<name>_purego.h`, 라이브러리를 macOS의
`lib<name>_zigo.dylib`, Linux의 `lib<name>_zigo.so`, Windows의 `<name>_zigo.dll`로
설치합니다. Windows 파일명에는 관례대로 `lib` 접두사가 붙지 않고, 설치 디렉터리도
`zig-out/lib`이 아니라 Zig 관례에 따라 `zig-out/bin`입니다(`lib`에는 import
라이브러리가 들어갑니다). `GoBindings.library_path`가 실제 설치 경로입니다. cgo와 purego를
한 `zig-out`에 빌드해도 서로 덮어쓰지 않습니다.

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

| 위치 | 소유자 | Git에 커밋 |
|---|---|---:|
| `go/**/*_gen.go` | zigo | 예 |
| `go/go.mod` | 사용자와 zigo | 예 |
| `zigo/semantic.json` | zigo | 예 |
| `zigo/errors.lock.json` | zigo | 예 |
| `zig-out/` | 빌드 캐시/출력 | 아니요 |

생성 파일을 직접 수정하지 마세요. 공개 패키지에 별도 `.go` 파일을 추가해 사용자 편의
API를 작성할 수 있으며, zigo는 marker가 없는 사용자 파일을 덮어쓰지 않습니다.

## `extern struct`에 필드를 더하는 일

`extern struct`에 필드를 추가하면 `abi-check`가 breaking으로 보고합니다. Go에 보이는 것은
값이지만 C 경계는 포인터(`const T*` 또는 `T*`)만 주고받고 크기는 함께 넘기지 않기 때문에,
버퍼를 잡은 쪽과 읽고 쓰는 쪽의 필드 수가 다르면 곧바로 메모리 문제가 됩니다.

- 반환·out 자리에서는 Go가 버퍼를 잡습니다. native만 새 필드를 아는 상태라면 native가 옛
  버퍼의 끝을 넘어 씁니다.
- 입력 자리에서는 native가 옛 버퍼의 끝을 넘어 읽어 새 필드를 쓰레기 값으로 봅니다.
- purego는 미러 struct의 주소를 그대로 넘기므로 이 어긋남이 그대로 드러납니다.

`.cgo_static`은 native archive가 Go 바이너리에 함께 링크되므로 두 쪽이 항상 같이
갱신됩니다. 이 조합만 놓고 보면 필드 추가가 안전하지만, `abi-check`는 링크 방식을 가정하지
않으므로 판정은 계속 breaking입니다. 필드를 더해야 한다면 새 struct와 새 함수를 추가하거나,
소비자와 native를 같은 시점에 배포하세요.

## optional의 C 표현

`?T`는 presence와 값을 함께 나릅니다. 어느 쪽도 값 하나에 겹쳐 넣지 않으므로 부재와
"값이 0인 present"가 언제나 구별됩니다.

- 매개변수는 nullable pointer 하나입니다. `?u32`는 `const int32_t *value`, `?Point`는
  `const zg_point *origin`이 되고, NULL이 부재입니다. scalar에도 별도의 `bool has_x`를
  두지 않는 이유는 포인터 하나가 이미 두 상태를 다 담기 때문이고, 덕분에 `extern struct`
  optional과 lowering이 한 갈래로 유지됩니다.
- 반환은 presence를 C 반환값으로 올립니다. `?T`를 돌려주는 함수는 `uint8_t`를 반환하고
  값은 `T *out_result`로 씁니다. 부재일 때 shim은 `out_result`를 건드리지 않습니다.
- error union과 겹치면 상태 코드가 이미 error에 쓰이므로 presence가 자기 out parameter를
  갖습니다: `int32_t f(..., uint8_t *out_result_has, T *out_result)`.

`?[]T`는 다릅니다. slice는 이미 포인터를 갖고 있으므로 presence 플래그를 더하지 않고
그 포인터의 NULL을 부재로 씁니다. 매개변수는 `const T *x_ptr, size_t x_len` 그대로이고,
반환은 `T **out_result_ptr, size_t *out_result_len`에 NULL을 쓰는 것으로 부재를 알립니다.
길이 0인 **존재하는** slice는 여전히 non-NULL 포인터로 건너가므로 두 상태가 섞이지
않습니다 — 생성된 Go raw 계층이 존재하지만 비어 있는 slice에 대해 자기 자리 표시자 주소를
넘기는 이유입니다.

purego도 같은 시그니처를 씁니다. scalar child는 `*T`로, `extern struct` child는
`unsafe.Pointer`로 바인딩 테이블에 선언됩니다.

`semantic.json`은 기존 `optional` 노드를 그대로 씁니다. `abi-check`는 `T`와 `?T`의
교체를 breaking으로 봅니다.

## Zig가 내주는 스트림

`fn writer(self) *std.Io.Writer`는 파싱과 lowering 사이에서 연산으로 확장됩니다
(`src/gen/stream_return.zig`): writer는 `write`·`flush` 둘, reader는 `read` 하나입니다.
확장된 함수는 그때부터 평범한 메서드라 헤더·shim·raw·공개 Go가 모두 기존 경로를 씁니다.
`semantic.json`에는 확장 전의 Zig 메서드가 남으므로 `abi-diff`는 Zig 표면을 비교합니다.

| Zig | C | Go |
|---|---|---|
| `fn writer(self) *std.Io.Writer` | `int32_t <p>_<t>_write(T*, const uint8_t*, size_t, ptrdiff_t*)` | `Write([]byte) (int, error)` |
| | `int32_t <p>_<t>_flush(T*)` | `Flush() error` |
| `fn reader(self) *std.Io.Reader` | `int32_t <p>_<t>_read(T*, uint8_t*, size_t, ptrdiff_t*)` | `Read([]byte) (int, error)` |

개수는 `usize`가 아니라 `isize`(`ptrdiff_t`)입니다. Go가 그것을 `int`로 적어야
`io.Writer`·`io.Reader`를 만족하기 때문입니다. shim은 연산마다 헬퍼
(`<symbol>_stream`)를 하나 내고, 그 안에서 접근자를 **다시 불러** 스트림을 얻습니다 —
포인터는 헬퍼 밖으로 나가지 않습니다. `read`는 `readSliceShort`를 쓰므로 스트림 끝이
짧은 개수로 오고, 공개 Go가 0을 `io.EOF`로 옮깁니다.

## 콜백이 돌려주는 Go error

`param_meta.<이름>.go_error`가 켜진 콜백은 Go 타입이 `func(...) (i32, error)`가 되고, C
시그니처는 그대로입니다. trampoline(cgo)과 dispatcher(purego)는 `err != nil`이면 그 error를
`CallbackState`/registry entry의 error 자리에 저장하고 결과로 **`-5`**를 돌려줍니다 —
`-3`(Go panic), `-4`(삭제된 토큰), `-1`(스트림 실패)과 구별되는 값입니다. 저장 자리는 스트림
error와 같은 필드입니다: 저장 규칙이 같고(먼저 온 것이 이긴다, 가져가면 지워진다) 이름만
`TakeStreamError`/`TakeCallbackError`로 갈립니다.

공개 래퍼는 native 상태 코드를 보기 전에 `zigoCallbackError`로 그것을 가져와 `*CallbackError`
로 반환합니다. retained 콜백은 handle의 `callbackHandles`를 순회하므로, error가 일어난 호출이
아니라 그다음 호출에서 나옵니다. 생성자 경로에서 반환할 때는 이미 등록한 retained handle을
먼저 해제합니다.

`go_error`는 파라미터가 아니라 ABI 시그니처의 성질입니다: Go 타입 하나와 purego dispatcher
하나를 시그니처마다 공유하기 때문에, 같은 시그니처를 쓰는 파라미터는 모두 같은 답을 씁니다.

## `std.Io` 스트림 어댑터

`*std.Io.Writer`/`*std.Io.Reader` 파라미터는 고정 시그니처 콜백 하나로 내려갑니다.

| 방향 | 콜백 | 결과 |
|---|---|---|
| writer | `i32 (const uint8_t *ptr, size_t len, size_t userdata)` | `0` 성공, `-1` Go error 저장, `-3` Go panic |
| reader | `i32 (uint8_t *ptr, size_t capacity, size_t userdata)` | `n >= 0` 읽은 바이트(`0`은 스트림 끝), `-1` error, `-3` panic |

cgo에서는 C 시그니처에 userdata만 실리고 shim이 바인딩마다 하나씩 있는 고정 `//export`
심볼(`<prefix>_zigo_stream_write`, `_read`)을 이름으로 참조합니다. purego에서는 dispatcher
포인터가 userdata 앞에 함께 실리고, 진입점은 다른 콜백과 같이 `_purego_v2` 접미사를 받습니다.
reader에는 `(const uint8_t *<name>_data, size_t <name>_data_len)` 한 쌍이 더 붙어 있습니다.
이것이 무콜백 경로입니다: `_data`가 널이 아니면 shim은 `std.Io.Reader.fixed`로 그 슬라이스를
감싸고 트램폴린을 한 번도 부르지 않으며, 널이면 예전처럼 어댑터를 씁니다. 생성된 Go는
`io.Reader`가 `zigoBytes() []byte`나 `Bytes() []byte`를 가질 때만 슬라이스를 채웁니다
(`zigoReaderBytes` 헬퍼). 빈 슬라이스도 "없음"과 구별해야 하므로 길이 0일 때는 raw 계층의
`zigoEmptyStreamData` 주소를 넘겨 포인터가 널이 되지 않게 합니다. 이 경로는 소비한 바이트
수를 되돌려 주지 않으므로 Go reader는 전진하지 않습니다.

shim은 어댑터 타입 두 개를 파일당 한 번만 내고, 파라미터마다 staging 버퍼와 어댑터를 만들어
`&adapter.interface`를 대상 함수에 넘깁니다. writer 어댑터의 `drain`은 버퍼에 들어가는
조각은 버퍼에 채우고 버퍼보다 큰 조각만 그대로 넘기므로, 경계를 넘는 횟수는 호출자가 몇
번 썼는지가 아니라 총량과 버퍼 크기가 정합니다. 함수가 돌아오기 전에 `defer`로 `flush`합니다.
reader 어댑터의 `stream`은 대상 writer의 쓰기 가능한 영역을 Go가 직접 채우게 하므로 읽기당
복사가 없습니다. `-1`이나 `-3`을 한 번 받은 어댑터는 이후 Go를 다시 부르지 않습니다.

Go 쪽에서는 `CallbackState`(cgo)와 토큰 레지스트리 항목(purego)이 스트림 값과 저장된 error를
함께 들고, 공개 래퍼가 native 호출 뒤 `TakeStreamError`로 그것을 가져와 `*StreamError`로
반환합니다. 이 검사는 native 상태 코드 검사보다 먼저 일어납니다.

## out slice가 채운 개수

`.direction = .out` slice가 얼마나 채워졌는지는 `written` 힌트가 정합니다. 기본값
`.all`은 C 시그니처에 `{name}_written`(`size_t *`) 파라미터를 하나 더 붙이고, shim이
거기에 버퍼 길이를(오류 경로에서는 0을) 씁니다. `.@"return"`은 개수를 함수의 반환값으로
알리므로 파라미터를 붙이지 않고, raw 계층도 그 반환값을 그대로 읽습니다. 두 힌트의 C
시그니처가 다르므로 힌트를 바꾸는 것은 breaking입니다.

## 값 struct slice의 캐스트 경로

bool 필드가 없는 `extern struct`는 Go mirror(`TData`)와 공개 타입 `T`, 그리고 C struct가
모두 같은 배치를 가집니다. 이런 원소의 slice 파라미터는 어느 계층에서도 복사하지 않고
주소만 넘어갑니다.

- 공개 계층: `[]T`를 `unsafe.Slice`로 `[]TData`로 재해석합니다.
- cgo raw 계층: `(*C.x)(unsafe.Pointer(&values[0]))`를 넘깁니다.
- purego raw 계층: 원래부터 mirror의 주소를 넘겼으므로 그대로입니다.

즉 두 백엔드가 같은 경로를 씁니다. native는 호출자의 버퍼에 직접 쓰고, 돌아오는 복사도
없습니다.

반환 방향도 같은 배치를 씁니다. raw 계층은 반환 slice를 Go 힙으로 한 번 복사해
핸들 수명과 끊어 놓고(`.returns = .caller`는 복사한 뒤 release합니다), 공개 계층은 그
결과를 `zigo{T}SliceView`로 `[]T`로 재해석하기만 합니다. 복사는 계층 전체에서 한 번뿐이고,
길이가 0이면 `nil`입니다. bool 필드가 있는 원소만 공개 계층에서 `zigo{T}SliceFromRaw`로
원소별 변환을 계속 씁니다.

배치가 같다는 전제는 생성 코드가 compile 시점에 못 박습니다. shim의 `zigoAbiGuard`가
Zig 타입을 헤더에 대해 고정하고, cgo raw 파일이 `TData`를 `C.x`에 대해, 공개 struct 파일이
`T`를 `TData`에 대해 크기와 필드 offset까지 단정합니다.

```go
var _ = [1]struct{}{}[unsafe.Sizeof(Point{})-unsafe.Sizeof(raw.PointData{})]
var _ = [1]struct{}{}[unsafe.Offsetof(Point{}.X)-unsafe.Offsetof(raw.PointData{}.X)]
```

배열 index가 상수로 평가되므로 배치가 어긋나면 `go build`가 그 자리에서 실패합니다.
bool 필드가 있는 struct는 캐스트하지 않으므로 이 단정도 생성되지 않습니다.

## 생성 파일의 역할

- `<package>_gen.go`: 공개 함수와 method
- `<package>_enums_gen.go`: enum type, 상수, `String()`
- `<package>_structs_gen.go`: `extern struct` 공개 value type과 raw 변환
- `<package>_handles_gen.go`: opaque handle type과 lifecycle method. borrowed `<T>Ref`는
  그것을 내주는 함수나 projection이 있는 type에만 생성된다
- `<package>_runtime_gen.go`: handle interface, projection status, `Must*`
  wrapper, bool 변환, callback type과 handle 등 private runtime support
- `<package>_union_<union>_gen.go`: tagged union 하나마다 projection, snapshot,
  sealed variant type
- `<package>_errors_gen.go`: error type, `Err*` sentinel, code 변환
- raw `_gen.go`: C ABI 또는 purego symbol 호출 계층

선언이 하나도 없는 파일은 생성하지 않습니다. enum이 없으면 `_enums_gen.go`가,
tagged union이 없으면 union 파일이 아예 만들어지지 않습니다.

모든 exported 선언에는 GoDoc이 생성됩니다. Zig source doc이 있으면 AST 보강 결과를 사용하고,
없으면 bound Zig operation과 ownership·lifetime·failure contract를 설명하는 기본 문서를
생성합니다.

GoDoc은 항상 Go 이름으로 시작하므로, Zig doc의 첫 단어가 그 선언의 이름(Zig 이름이든 Go
이름이든, 대소문자 무시)이면 그 단어를 빼고 붙입니다. `/// clone copies the queue.`는
`// Clone clone copies ...`가 아니라 `// Clone copies the queue.`가 됩니다.

호출 중 handle의 수명은 handle 검사가 붙이는 `defer x.zigoRelease()`가 지킵니다. 그
defer가 `x`를 붙잡고 native 호출 뒤에 역참조하므로 함수가 끝날 때까지 살아 있고,
receiver나 handle parameter에 `runtime.KeepAlive`를 따로 걸지 않습니다. 생성 코드에
남는 `runtime.KeepAlive`는 두 가지뿐입니다: `Close`가 `cleanup.Stop()` 뒤 자기 자신을
붙잡는 것과, 문자열·slice 데이터처럼 Go 메모리의 포인터를 native에 넘긴 동안 그 메모리를
붙잡는 것.

callback parameter는 익명 함수가 아니라 생성된 정의 type을 사용합니다. borrowed callback
handle은 호출 후 즉시 해제하고, retained callback handle은 소유 객체의 멱등 `Close`에서
해제합니다.

## Go 이름과 포맷

- Zig snake_case parameter는 camelCase로 바뀝니다.
- Go keyword나 생성 local과 충돌하면 `type_`, `code_`처럼 escape합니다.
- 변환 후 이름이 겹치면 뒤쪽 이름에 숫자를 붙입니다.
- 한 type의 receiver 이름은 모든 생성 파일에서 동일합니다.
- 공개 Go 함수 이름은 namespace를 붙이지 않습니다. 중첩 namespace의 함수도
  `CodepointWidth`처럼 함수 이름만 씁니다.
- C가 이름 붙일 수 없는 정수 폭(`u21`)은 파라미터·반환값에서 다음 폭으로 승격되어
  `uint32`로 나옵니다. 승격된 파라미터가 있는 함수는 공개 시그니처에 `error`가 붙고,
  범위 검사는 cgo 호출 전 Go에서 이뤄져 `*RangeError`를 돌려줍니다.
- 모든 생성 source는 기록 전 `gofmt`로 포맷됩니다.

`go-check`도 같은 `gofmt` 결과와 비교합니다. 사용자 소유 Go 파일은 포맷하거나 검사하지
않습니다.

## 메타데이터 계약

`semantic.json`은 reflection 이후 확정된 바인딩 계약이며 `abi-check`의 비교 단위입니다.
`go-check`는 `go_dir`의 Go 생성 파일만 비교하므로 metadata도 `go` 실행 후 같은 commit에
포함되었는지 리뷰에서 확인해야 합니다.

함수의 `symbol` 필드는 그 함수가 export되는 C 심볼 이름입니다. 규칙은 하나뿐이고
(`{prefix}_{owner}_{name}`, owner는 `receiver` 또는 `namespace`, 모두 snake_case로
정규화), 소유 타입이 없으면 `{prefix}_{name}`입니다. `namespace`가 중첩 경로를 담고 있으면
segment마다 따로 정규화해 `_`로 잇습니다 — `unicode.codepointWidth`는
`zg_unicode_codepoint_width`입니다. raw Go 이름도 같은 segment 단위로 Pascal 결합해
`UnicodeCodepointWidth`가 되고, ABI identity는 `unicode.codepointWidth`입니다. 헤더, 링커, 심볼 충돌 검사, 그리고
이 메타데이터가 모두 같은 규칙 함수(`naming.functionSymbolAlloc`)에서 이름을 받습니다.
백엔드가 덧붙이는 장식은 포함하지 않습니다 — purego의 callback 변형이 쓰는 `_purego_v2`
접미는 lowering 단계의 산물이므로 `symbol`에는 나타나지 않습니다.

0.x의 이전 판은 소유 타입을 빠뜨린 `{prefix}_{name}`을 기록해 같은 문서 안에서
`zg_deinit` 같은 이름이 중복됐습니다. `abi-check`는 옛 값이 그 옛 규칙과 일치하고 새 값이
현재 규칙과 일치하는 경우에 한해 이를 `exported C symbol metadata corrected`라는
compatible 변경으로 보고합니다. 실제로 심볼이 옮겨간 변경은 그대로 breaking입니다.

`errors.lock.json`은 Zig error set 이름에 배정한 양수 code를 보존하는 append-only
상태입니다. 기존 이름의 삭제·변경·code 재사용은 거부됩니다. 새 오류가 생기면 Go 생성물과
lock 변경을 같은 커밋에 포함하세요.

함수는 선택 필드 `source: { path, line, column }`을 가질 수 있습니다. `names.zig`가
`bindings.zig`(또는 그것이 `@import`하는 소스)를 AST로 스캔해 함수 선언 이름 토큰의
위치를 채우고, 함수의 각 파라미터에도 선택 필드 `source: { line, column }`(경로는 함수와
같으므로 생략)을 채웁니다. 둘 다 처음 일치한 소스 파일의 값을 쓰고 이후 갱신하지 않으며,
없으면 진단이 지금처럼 `semantic.json`을 가리킵니다. `abi_diff`는 이 필드를 비교하지
않습니다 — ABI가 아니라 진단이 가리키는 위치일 뿐입니다.

생성기는 파일을 모두 메모리에서 준비한 뒤 소스 트리에 반영합니다. validation이나 rendering
실패에는 기존 트리를 유지하지만, 최종 쓰기 중 전원 또는 filesystem 장애까지 하나의
transaction으로 복구하지는 않습니다.

## 일상 개발 순서

```bash
# 1. 현재 커밋 상태가 최신인지 확인
zig build go-check

# 2. Zig API나 bindings.zig 변경 후 생성
zig build go

# 3. 환경과 Go 동작 확인
zig build go-doctor
(cd go && go test ./...)

# 4. Go 소스와 zigo 메타데이터를 함께 리뷰·커밋
git status --short
```

raw 패키지 경로 또는 모드를 바꾸면 이전 `_gen.go`를 직접 삭제해야 합니다. `go-check`는 zigo
marker가 있는 이전 파일을 오래된 파일로 보고합니다.

## CI 권장 구성

기본 검사:

```bash
zig build go-check
(cd go && go test ./...)
```

도구와 네이티브 아티팩트까지 묶어 확인하려면:

```bash
zig build go-verify
(cd go && go test ./...)
```

`abi_base`를 설정한 독립 배포 프로젝트는 `go-verify`가 `abi-check`도 포함합니다. 개별 실행이
필요하면 다음처럼 사용합니다.

```bash
zig build go-check abi-check
```

CI에서 `go`를 실행한 뒤 `git diff --exit-code`를 검사하는 방식도 가능하지만, 소스 트리를
수정하지 않고 누락·내용 변경·오래된 파일을 구분하는 `go-check`가 의도를 더 직접적으로
표현합니다.
