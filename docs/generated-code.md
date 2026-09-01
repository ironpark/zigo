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

## 생성 파일의 역할

- `<package>_gen.go`: 공개 함수와 method
- `<package>_enums_gen.go`: enum type, 상수, `String()`
- `<package>_structs_gen.go`: `extern struct` 공개 value type과 raw 변환
- `<package>_handles_gen.go`: opaque handle/Ref type과 lifecycle method
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

callback parameter는 익명 함수가 아니라 생성된 정의 type을 사용합니다. borrowed callback
handle은 호출 후 즉시 해제하고, retained callback handle은 소유 객체의 멱등 `Close`에서
해제합니다.

## Go 이름과 포맷

- Zig snake_case parameter는 camelCase로 바뀝니다.
- Go keyword나 생성 local과 충돌하면 `type_`, `code_`처럼 escape합니다.
- 변환 후 이름이 겹치면 뒤쪽 이름에 숫자를 붙입니다.
- 한 type의 receiver 이름은 모든 생성 파일에서 동일합니다.
- 모든 생성 source는 기록 전 `gofmt`로 포맷됩니다.

`go-check`도 같은 `gofmt` 결과와 비교합니다. 사용자 소유 Go 파일은 포맷하거나 검사하지
않습니다.

## 메타데이터 계약

`semantic.json`은 reflection 이후 확정된 바인딩 계약이며 `abi-check`의 비교 단위입니다.
`go-check`는 `go_dir`의 Go 생성 파일만 비교하므로 metadata도 `go` 실행 후 같은 commit에
포함되었는지 리뷰에서 확인해야 합니다.

`errors.lock.json`은 Zig error set 이름에 배정한 양수 code를 보존하는 append-only
상태입니다. 기존 이름의 삭제·변경·code 재사용은 거부됩니다. 새 오류가 생기면 Go 생성물과
lock 변경을 같은 커밋에 포함하세요.

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
