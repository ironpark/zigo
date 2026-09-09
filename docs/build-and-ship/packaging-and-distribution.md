# 패키징과 배포

이 가이드는 생성된 Go module과 native artifact를 소비자 환경에 전달하는 방법을 백엔드별로
정리합니다.

## 공통 원칙

- Go source와 `zigo/` metadata는 source repository에 커밋합니다.
- 실행 target과 일치하는 native library를 함께 제공합니다.
- binding Go source와 native library는 같은 zigo version과 선언에서 생성합니다.
- native library가 의존하는 다른 library도 배포 계약에 포함합니다.
- target 환경에서 실제 실행 test를 수행합니다.

`go get`은 Zig build를 실행하지 않습니다. Go module만 배포하면서 native artifact 준비 방법을
제공하지 않으면 소비자는 link 또는 load 단계에서 실패합니다.

## cgo static

기본 library는 다음 위치에 설치됩니다.

```text
zig-out/lib/lib<name>_zigo.a
zig-out/include/zigo_<name>.h
```

정적 archive가 module의 모든 native dependency를 하나로 합친다는 뜻은 아닙니다. system
library, framework와 별도 archive도 생성된 cgo link line 또는 배포 환경에서 사용할 수 있어야
합니다.

multi-target tree에서는 다음처럼 platform directory가 추가됩니다.

```text
zig-out/lib/linux_amd64/libmylib_zigo.a
zig-out/lib/windows_amd64/libmylib_zigo.a
```

Windows cgo는 amd64 GNU ABI에서 `CC="zig cc"`를 권장합니다.

```powershell
$env:CGO_ENABLED = "1"
$env:CC = "zig cc"
go test ./...
```

## cgo dynamic

공유 library를 Go 실행 파일과 함께 배포하고 OS loader가 찾을 수 있게 합니다.

| OS | 기본 파일 |
|---|---|
| macOS | `lib<name>_zigo.dylib` |
| Linux | `lib<name>_zigo.so` |
| Windows | `<name>_zigo.dll` |

개발 환경에서는 `DYLD_LIBRARY_PATH` 또는 `LD_LIBRARY_PATH`를 사용할 수 있지만 제품 배포에는
실행 파일 기준 rpath나 설치 프로그램이 관리하는 고정 위치를 권장합니다. build machine의
절대 경로를 rpath로 남기지 마세요.

## purego

purego는 Go build에 C compiler가 필요 없지만 실행 시 공유 library가 반드시 필요합니다.
생성 module은 `github.com/ebitengine/purego v0.10.2`를 사용합니다.

```bash
zig build purego-go
(cd go-purego && go mod tidy)
zig build purego-go-verify
(cd go-purego && CGO_ENABLED=0 go test ./...)
```

기본 명시적 policy에서는 application 시작 시 library를 로드합니다.

```go
if err := mylib.LoadLibrary(path); err != nil {
    return err
}
```

성공적으로 로드한 library는 process 종료까지 유지됩니다. unload와 hot reload는 제공하지
않습니다. 로드 전 binding 호출은 panic하며, 잘못된 library에서 symbol 일부만 찾은 상태를
사용 가능 상태로 남기지 않습니다.

## multi-target purego layout

한 Go tree에 여러 target을 구성하면 다음 layout을 그대로 배포합니다.

```text
app/
├── myapp
└── lib/
    ├── darwin_arm64/libmylib_zigo.dylib
    ├── linux_amd64/libmylib_zigo.so
    └── windows_amd64/mylib_zigo.dll
```

`${EXECUTABLE_DIR}/lib`을 search path로 지정하면 loader가 현재
`runtime.GOOS + "_" + runtime.GOARCH` directory를 선택합니다.

```zig
.library_loading = .{
    .search_paths = &.{"${EXECUTABLE_DIR}/lib"},
    .loader = .automatic,
},
```

명시적 `LoadLibrary(path)`와 환경 변수에 파일 경로를 주면 platform directory를 자동으로
덧붙이지 않습니다.

## cross compile 검사

reflection은 build host에서 실행되고 native library만 target용으로 만들어집니다.

- `c_long`처럼 host와 target에서 폭이 달라지는 타입을 공개 ABI에 사용하지 않습니다.
- target별로 public declaration이 달라진다면 target host에서 생성 결과도 확인합니다.
- foreign target doctor의 load 검사는 `SKIP`될 수 있습니다.
- build 성공은 target에서의 load와 호출 성공을 보장하지 않습니다.

지원 target과 알려진 제약은 [지원 범위](../reference/support-matrix.md)가 정본입니다.
