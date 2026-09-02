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
go/internal/raw/zigo_link_inputs_gen.go  # 정적 입력이 있을 때만, machine-local
go/internal/lifecycle/lifecycle_gen.go   # .packages를 선언했을 때
go/<package-path>/<package>_gen.go
go/<package-path>/<package>_enums_gen.go
go/<package-path>/<package>_structs_gen.go
go/<package-path>/<package>_handles_gen.go
go/<package-path>/<package>_runtime_gen.go
go/<package-path>/<package>_union_<union>_gen.go
go/<package-path>/<package>_errors_gen.go
go/<package-path>/<sub-path>/<sub-package>_gen.go
go/<package-path>/<sub-path>/<sub-package>_*_gen.go
zigo/semantic.json
zigo/errors.lock.json
zig-out/include/zigo_<name>.h
zig-out/lib/lib<name>_zigo.a
```

`<package-path>`는 기본적으로 `<package>`와 같습니다. `go_package_path = "."`이면 이 경로
요소가 사라져 `go/<package>_gen.go`처럼 `go_dir` 루트에 생성됩니다. raw 패키지 경로는
별도 `raw_package`가 계속 정합니다. 둘을 같은 경로(루트에서는 둘 다 `"."`)로 두면 raw
구현도 공개 패키지에 colocate됩니다.

`.packages`가 있으면 `internal/lifecycle`이 모든 공개 패키지가 공유하는 handle 계약, pointer
검사와 poison 전파, 오류 형식과 sentinel identity를 소유합니다. 각 공개 패키지는 기존 공개
이름을 type alias와 sentinel 변수로 다시 내보내므로 어느 패키지의 sentinel을 사용해도
`errors.Is`가 같은 error code를 찾습니다. cgo의 C 호출 계층은 `internal/raw`에 남고,
purego의 로더·함수 테이블·callback token registry는 설정한 `internal/native` 같은 raw
패키지에 남습니다. `.packages`가 없는 기존 단일 패키지는 shared lifecycle을 만들지 않아
생성 바이트와 공개 API를 유지합니다.

`zigo_link_inputs_gen.go`는 다른 생성 파일과 달리 commit하지 않습니다. module이 별도 정적
archive를 링크할 때만 build step이 실제 절대 경로로 다시 쓰며, `go-check`는 이 파일을
비교하거나 obsolete로 판정하지 않습니다.

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
API를 작성할 수 있습니다. stale 정리는 생성 marker가 있는 파일만 삭제하므로 루트 발행
중에도 `go.mod`와 marker가 없는 사용자 파일을 보존합니다. 단, 생성될 파일과 **같은
파일명**을 사용하면 갱신 대상이 되므로 피해야 합니다.

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

caller-owned optional slice는 이 포인터 표현에 기존 copy/release 경로를 결합합니다.
`?[]T`와 `!?[]T` 모두 포인터가 non-NULL인 성공 경로에서만 Go 메모리로 복사하고 release
심볼을 호출합니다. 부재나 error에서는 out buffer를 읽거나 release하지 않습니다. 공개 결과는
`([]T, bool)`/`([]T, bool, error)`이고, c_string variant는 `string`을 반환합니다.

purego도 같은 시그니처를 씁니다. scalar child는 `*T`로, `extern struct` child는
`unsafe.Pointer`로 바인딩 테이블에 선언됩니다.

`semantic.json`은 기존 `optional` 노드를 그대로 씁니다. `abi-check`는 `T`와 `?T`의
교체를 breaking으로 봅니다.

## 취소 플래그

`.cancel = .{ .param = "..." }`이 붙은 함수는 C 시그니처에 `const uint32_t *<이름>`을
그대로 유지하고, Go 공개 시그니처에서는 그 파라미터가 사라지고 `ctx context.Context`가
첫 인자로 들어옵니다. shim은 포인터를 `@ptrCast`로 `*const std.atomic.Value(u32)`에
맞춰 대상 함수에 넘길 뿐, 아무것도 만들지 않습니다 — 워드는 Go의 것입니다.

생성된 Go는 호출 프레임에 `var zigoCancel uint32`를 두고, `ctx.Done()`을 기다리는
goroutine이 `atomic.StoreUint32`로 그것을 세웁니다(`zigoStop` 채널로 호출 종료 시 정리).
이미 취소된 ctx는 goroutine 없이 호출 전에 세우고, 취소될 수 없는 ctx는 goroutine을
만들지 않습니다. cgo는 C에 넘긴 Go 포인터를 호출 동안 고정하므로 그대로 넘기고, purego
백엔드는 보장이 없으므로 `runtime.Pinner`로 고정하고 호출 뒤 `runtime.KeepAlive`합니다.

상태 코드가 `Canceled`로 풀리고 `ctx.Err() != nil`이면 공개 래퍼는 `ctx.Err()`를 반환합니다.
`.cancel`이 없는 함수의 생성물은 바이트 그대로입니다.

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
breaking으로 보고합니다.

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
- method receiver는 receiver 타입의 snake_case 이름에서 가장 짧은 접두사를 고릅니다. 길이
  1부터 늘리며 그 함수의 Go 파라미터 이름과 겹치지 않는 첫 접두사를 쓰고, 전체 이름까지
  모두 겹치면 `recv`를 씁니다. 예를 들어 `Terminal.setTitle(t)`는
  `func (te *Terminal) SetTitle(t []byte)`가 됩니다. 충돌이 없으면 이전과 같은 첫 글자를
  유지하며, 한 함수의 header·handle 검사·native 호출 오류·release 경로는 모두 같은 이름을
  씁니다. 파라미터가 없는 lifecycle·projection helper도 첫 글자를 유지합니다.
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

## 메타데이터 계약

`semantic.json`은 reflection 이후 확정된 바인딩 계약이며 `abi-check`의 비교 단위입니다.
`go-check`는 `go_dir`의 Go 생성 파일만 비교하므로 metadata도 `go` 실행 후 같은 commit에
포함되었는지 리뷰에서 확인해야 합니다.

함수의 소속은 두 축입니다. `namespace`는 함수가 **선언된** Zig 컨테이너이고, 심볼과 raw Go
이름이 여기서 나옵니다. Go의 소속은 `go_owner`이며, 타입 밖에 선언된 생성자를
`.constructs`로 짝지었거나 한 handle의 메서드가 다른 handle을 생성할 때처럼 둘이 다를 때만
문서에 나타납니다. 후자의 `receiver`는 호출 대상을, `go_owner`는 반환 handle을 가리킵니다.
shim이 부를 Zig 선언이
`<소유자>.<이름>`으로 적히지 않는 경우(타입 밖에 선언된 소멸자, `.name`으로 이름을 바꾼
함수)에는 `zig_path`가 그 경로를 그대로 적습니다. 둘 다 기본값과 같으면 생략됩니다.
receiver 앞에 주입 파라미터가 선언된 함수(`fn free(gpa: Allocator, self: *T) void`)는
`receiver_at`에 receiver 앞의 `params` 항목 수를 적고, shim은 그 자리에 `self`를 넣어
호출합니다. C와 Go 시그니처는 영향을 받지 않으므로 이 필드도 `abi-diff` 대상이 아닙니다.

주입 파라미터는 C 시그니처에도 Go 시그니처에도 없으므로 `abi-diff`는 그것을 빼고 비교하고,
`go_owner`가 바뀌면 Go 표면이 움직이므로 breaking으로 봅니다.
`child_of_receiver: true`는 설정한 constructor에만 나타납니다. gain/loss는 C signature를
움직이지 않지만 부모 `Close`의 동작과 생성된 Go handle 구조를 바꾸므로 ABI-compatible
Go-surface 변경으로 보고됩니다.
`borrowed_return: true`도 `.returns = .borrowed`를 명시한 함수에만 나타납니다. 생략된
`ownership: borrowed`와 구분되며, borrowed/caller 변경은 공개 Go handle의 cleanup 계약을
바꾸므로 breaking입니다.

하위 패키지가 선언되면 최상위 `packages` 배열은 `{path,name,doc}`을 기록하고, 각 type과
function은 기본 패키지가 아닐 때만 `package` 이름을 기록합니다. 기본 패키지의 필드는 생략되어
기존 단일 패키지 문서는 바이트 단위로 그대로입니다. type이나 function의 `package` 변경은
Go import path가 달라지는 breaking 변경입니다.

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

`addStandardSteps`를 등록한 프로젝트는 plain `zig build`도 native binding library를
설치합니다. 상위 빌드가 설치를 따로 관리하면
`.install_library_by_default = false`를 지정합니다.

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
