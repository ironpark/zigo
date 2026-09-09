# 패키징과 배포

이 가이드는 생성된 Go 모듈과 네이티브 산출물을 소비자 환경에 전달하는 방법을 백엔드별로
정리합니다.

## 공통 원칙

- Go 소스와 `zigo/` 메타데이터는 소스 저장소에 커밋합니다.
- 실행 대상과 일치하는 네이티브 라이브러리를 함께 제공합니다.
- 바인딩 Go 소스와 네이티브 라이브러리는 같은 zigo version과 선언에서 생성합니다.
- 네이티브 라이브러리가 의존하는 다른 라이브러리도 배포 계약에 포함합니다.
- 대상 환경에서 실제 실행 테스트를 수행합니다.

`go get`은 Zig 빌드를 실행하지 않습니다. Go 모듈만 배포하면서 네이티브 산출물 준비 방법을
제공하지 않으면 소비자는 링크 또는 로드 단계에서 실패합니다.

## 전달할 파일과 소비자 준비

| 방식 | Go 빌드에 필요한 것 | 실행 환경에 필요한 것 |
|---|---|---|
| cgo 정적 링크 | 생성 Go 소스·헤더, 대상별 정적 라이브러리, C 컴파일러와 추가 링크 입력 | 빌드한 Go 실행 파일과 남아 있는 동적 의존성 |
| cgo 동적 링크 | 생성 Go 소스·헤더, 대상별 공유 라이브러리와 C 컴파일러 | Go 실행 파일, 공유 라이브러리와 그 의존성 |
| purego | 생성 Go 소스와 Go 모듈 의존성 | Go 실행 파일, 대상별 공유 라이브러리와 로드 설정 |

가장 먼저 지원할 배포 경로는 저장소를 받은 소비자가 프로젝트 루트에서 `zig build go-lib`를
실행하고 `go/`에서 Go 빌드를 수행하는 방식입니다. 생성물이 커밋되어 있다면 다시 생성할
필요는 없지만, 네이티브 소스와 Zig 도구는 필요합니다.

미리 빌드한 라이브러리를 전달하려면 생성 raw 패키지의 `#cgo`에 기록된 상대 경로를 포함해
디렉터리 구조를 함께 배포하거나, 배포할 경로에 맞춰 `install`과 `cgo_flags`를 설정한 후
재생성합니다. Go 모듈 밖의 `zig-out/`은 Go 모듈 배포에 자동 포함되지 않습니다.
`zigo_link_inputs_gen.go`의 머신별 절대 경로도 그대로 배포할 수 없습니다.
배포 묶음을 별도 디렉터리에 풀고 작성자 환경의 파일 없이 빌드·실행되는지 확인하세요.

## cgo static

기본 라이브러리는 다음 위치에 설치됩니다.

```text
zig-out/lib/lib<name>_zigo.a
zig-out/include/zigo_<name>.h
```

정적 archive가 모듈의 모든 네이티브 의존성를 하나로 합친다는 뜻은 아닙니다. 시스템
라이브러리, 프레임워크와 별도 archive도 생성된 cgo 링크 설정 또는 배포 환경에서 사용할 수 있어야
합니다.

multi-target tree에서는 다음처럼 플랫폼 디렉터리가 추가됩니다.

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

공유 라이브러리를 Go 실행 파일과 함께 배포하고 OS loader가 찾을 수 있게 합니다.

| OS | 기본 파일 |
|---|---|
| macOS | `lib<name>_zigo.dylib` |
| Linux | `lib<name>_zigo.so` |
| Windows | `<name>_zigo.dll` |

개발 환경에서는 `DYLD_LIBRARY_PATH` 또는 `LD_LIBRARY_PATH`를 사용할 수 있지만 제품 배포에는
실행 파일 기준 rpath나 설치 프로그램이 관리하는 고정 위치를 권장합니다. 빌드 머신의
절대 경로를 rpath로 남기지 마세요.

## purego

purego는 Go 빌드에 C 컴파일러가 필요 없지만 실행 시 공유 라이브러리가 반드시 필요합니다.
생성 모듈은 `github.com/ebitengine/purego v0.10.2`를 사용합니다.

[시작 가이드](../getting-started.md)의 `addGoBindings`에 `.link = .purego`를 추가하고,
`go_dir = b.path("go")`와 기본 `addStandardSteps(b, .{})`를 유지한 경우:

```bash
(cd go && go get github.com/ebitengine/purego@v0.10.2)
zig build go
(cd go && go mod tidy)
zig build go-verify
(cd go && CGO_ENABLED=0 go test ./...)
```

테스트에서도 첫 바인딩 호출 전에 아래의 로드 코드를 실행해야 합니다.
별도 바인딩에 `.name_prefix = "purego"`와 `go_dir = b.path("go-purego")`를 설정했다면
단계는 `purego-go`·`purego-go-verify`, Go 작업 디렉터리는 `go-purego`로 바뀝니다.

기본 명시적 정책에서는 애플리케이션 시작 시 라이브러리를 로드합니다.

```go
if err := mylib.LoadLibrary(path); err != nil {
    return err
}
```

성공적으로 로드한 라이브러리는 프로세스 종료까지 유지됩니다. unload와 hot reload는 제공하지
않습니다. 로드 전 바인딩 호출은 panic하며, 잘못된 라이브러리에서 심볼 일부만 찾은 상태를
사용 가능 상태로 남기지 않습니다.

## 여러 대상의 purego 배포 구조

한 Go tree에 여러 대상을 구성하면 다음 배치를 그대로 배포합니다.

```text
app/
├── myapp
└── lib/
    ├── darwin_arm64/libmylib_zigo.dylib
    ├── linux_amd64/libmylib_zigo.so
    └── windows_amd64/mylib_zigo.dll
```

`${EXECUTABLE_DIR}/lib`을 search 경로로 지정하면 loader가 현재
`runtime.GOOS + "_" + runtime.GOARCH` 디렉터리를 선택합니다.

```zig
.library_loading = .{
    .search_paths = &.{"${EXECUTABLE_DIR}/lib"},
    .loader = .automatic,
},
```

명시적 `LoadLibrary(path)`와 환경 변수에 파일 경로를 주면 플랫폼 디렉터리를 자동으로
덧붙이지 않습니다.

## 크로스 컴파일 검사

reflection은 빌드 호스트에서 실행되고 네이티브 라이브러리만 대상용으로 만들어집니다.

- `c_long`처럼 호스트와 대상에서 폭이 달라지는 타입을 공개 ABI에 사용하지 않습니다.
- 대상별로 공개 선언이 달라진다면 대상 호스트에서 생성 결과도 확인합니다.
- 다른 플랫폼의 대상 doctor의 로드 검사는 `SKIP`될 수 있습니다.
- 빌드 성공은 대상에서의 로드와 호출 성공을 보장하지 않습니다.

지원 대상과 알려진 제약은 [지원 범위](../reference/support-matrix.md)가 정본입니다.
