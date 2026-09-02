# 시작 가이드

이 가이드는 가장 단순하고 배포하기 쉬운 기본 경로인 **cgo 정적 링크**로 첫 바인딩을
만듭니다. 완료하면 Zig 함수가 생성된 Go 패키지에서 호출되고, 생성물 최신 상태를 CI에서
검사할 수 있습니다.

## 준비 사항

- Zig 0.16.0
- Go 1.24 이상과 Go 배포판에 포함된 `gofmt`
- C 컴파일러를 사용할 수 있고 cgo가 활성화된 네이티브 macOS, Linux 또는 Windows 환경.
  Windows에서는 `CC="zig cc"`가 그 C 컴파일러 역할을 하므로 mingw-w64를 따로 설치할
  필요가 없습니다. [Windows에서 cgo 백엔드 쓰기](#windows에서-cgo-백엔드-쓰기)를 보세요.

다음 명령으로 현재 환경을 확인할 수 있습니다.

```bash
zig version
go version
go env CGO_ENABLED CC
```

purego도 Zig 공유 라이브러리를 현재 호스트에서 빌드해야 합니다. 먼저 이 가이드의 기본
경로를 완료한 뒤 [purego 가이드](purego.md)로 이동하는 것을 권장합니다.

### Windows에서 cgo 백엔드 쓰기

Windows의 cgo는 gcc 호환 C 툴체인을 요구합니다. mingw-w64를 설치하는 대신 이미 갖고
있는 Zig를 그대로 쓰면 됩니다. `zig cc`는 gcc 호환 clang 드라이버이고 mingw 헤더와
CRT, 링커를 함께 들고 다닙니다. 추가 `CGO_CFLAGS`나 `CGO_LDFLAGS`는 필요 없습니다.

```powershell
$env:CGO_ENABLED = "1"
$env:CC = "zig cc"
zig build go
cd go
go test ./...
```

POSIX 호스트에서 Windows용으로 크로스 빌드할 수도 있습니다. 정적 아카이브를 타깃으로
빌드한 다음 같은 타깃을 `CC`에 실어 링크합니다.

```bash
zig build go-lib -Dtarget=x86_64-windows-gnu
cd go
CGO_ENABLED=1 GOOS=windows GOARCH=amd64 \
  CC="zig cc -target x86_64-windows-gnu" go build ./...
```

주의할 점:

- amd64에 gnu ABI 전용입니다. `-target *-windows-msvc`, 386, arm32는 지원하지
  않습니다.
- 정적 아카이브는 Windows 타깃에서도 `zig-out/lib/lib<name>_zigo.a`로 설치됩니다.
  생성된 `#cgo LDFLAGS` 줄이 모든 호스트에서 같은 이름을 쓰기 때문입니다.
- 크로스 빌드에서는 `go-doctor`가 `FAIL target`을 보고합니다. `GOOS`와 `CC` 조합을
  관찰할 수 없어 검증할 방법이 없기 때문이지, 링크가 안 된다는 뜻이 아닙니다. 결과
  실행 파일은 타깃에서 실행해 확인하세요.

## 1. zigo 의존성 추가

Zig 프로젝트 루트에서 실행합니다.

```bash
zig fetch --save git+https://github.com/ironpark/zigo#0.4.1
```

명령이 `build.zig.zon`에 `zigo` 의존성을 추가합니다. 재현 가능한 빌드를 위해 생성된
URL과 해시 변경을 함께 커밋하세요.

## 2. 빌드 그래프 연결

다음 디렉터리 구조를 기준으로 설명합니다.

```text
.
├── build.zig
├── build.zig.zon
└── src
    ├── bindings.zig
    └── root.zig
```

`build.zig`에서 라이브러리 모듈을 만든 뒤 `addGoBindings`를 연결합니다.

```zig
const std = @import("std");
const zigo = @import("zigo");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mylib = b.addModule("mylib", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const bindings = zigo.addGoBindings(b, .{
        .name = "mylib",
        .module = mylib,
        .bindings = b.path("src/bindings.zig"),
        .source_root = b.path("src/root.zig"),
        .go_dir = b.path("go"),
        .go_module = "example.com/mylib/go",
        .target = target,
        .optimize = optimize,
    });

    _ = bindings.addStandardSteps(b, .{});
}
```

바꿔야 하는 값은 세 가지입니다.

- `mylib`: 프로젝트의 Zig 모듈 이름
- `go`: 생성된 Go 모듈을 둘 디렉터리
- `example.com/mylib/go`: 실제로 사용할 Go module path

`source_root`는 함수 파라미터 이름과 문서 주석을 실제 Zig 소스에서 보강합니다. 대상 모듈의
루트 파일을 알고 있다면 지정하는 편이 좋습니다.

## 3. 공개 API 선언

예제의 `src/root.zig`에 다음 함수가 있다고 가정합니다.

```zig
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

`src/bindings.zig`에는 Go에 노출할 선언만 적습니다.

```zig
const zigo = @import("zigo");
const mylib = @import("mylib");

pub const bindings = zigo.define(.{
    .root = mylib,
    .functions = .{
        .{ .path = "root.add" },
    },
});
```

`root.add`는 모듈의 자유 함수를 뜻합니다. 등록한 타입의 메서드는 `Context.process`처럼
`<타입 이름>.<함수 이름>`으로 적습니다.

처음에는 안정적으로 노출할 함수만 `functions`에 명시하는 것을 권장합니다. 공개 Zig API
전체가 곧 바인딩 API인 프로젝트는 나중에 `.discover = .public`을 선택할 수 있습니다.

## 4. 생성하고 테스트

프로젝트 루트에서 바인딩과 네이티브 라이브러리를 생성합니다.

```bash
zig build go
```

처음 실행하면 `go/` 아래에 `go.mod`, 공개 Go 패키지, raw 패키지가 생기고 프로젝트 루트의
`zigo/` 아래에 ABI 메타데이터가 생깁니다. 이어서 Go 테스트를 실행합니다.

```bash
cd go
go test ./...
```

생성된 공개 패키지의 실제 import path는 기본적으로 `<go_module>/<go_package>`입니다.
`go_package_path = "."`이면 `<go_module>`, 다른 경로이면 `<go_module>/<go_package_path>`입니다. `go_package`를
지정하지 않았다면 `name`을 snake_case로 정규화한 값이 사용됩니다.

## 5. 일상 개발 흐름

Zig API나 `bindings.zig`를 바꾼 뒤에는 생성물을 갱신하고 테스트합니다.

```bash
zig build go
zig build go-doctor
(cd go && go test ./...)
```

- `go`는 바인딩과 네이티브 라이브러리를 갱신합니다.
- `go-doctor`는 Go 버전, `gofmt`, cgo와 C compiler 같은 환경 전제를 진단합니다.
- 더 자세한 이름·ownership·retention 결정은 `zig build go-report`로 확인합니다.

생성된 Go 소스와 `zigo/semantic.json`, `zigo/errors.lock.json`을 함께 커밋하세요. 생성 파일을
직접 수정하면 다음 생성 때 덮어써집니다.

## 6. CI에서 생성물 검사

CI에서는 파일을 갱신하는 `go` 대신 읽기 전용 검사인 `go-check`를 사용합니다.

```bash
zig build go-check
(cd go && go test ./...)
```

`go-check`는 다음 상태에서 실패합니다.

- 현재 선언으로 생성한 내용과 커밋된 파일이 다름
- 필요한 Go 생성 파일이 없음
- 더 이상 생성되지 않는 zigo 파일이 이전 경로에 남아 있음

독립 배포된 이전 버전과 ABI 호환성을 유지해야 할 때만 `.abi_base = "HEAD"` 같은 기준을
설정하고 CI에 `zig build abi-check`를 추가합니다. 같은 저장소 안에서 항상 함께 배포하는
코드라면 필수 설정이 아닙니다.

## 문제가 생겼다면

| 증상 | 확인할 것 |
|---|---|
| `gofmt is required` | Go 배포판을 설치하고 `gofmt`가 `PATH`에 있는지 확인 |
| cgo 또는 C compiler 진단 실패 | `go env CGO_ENABLED CC`와 `zig build go-doctor` 출력 확인 |
| 생성물이 오래되었다는 오류 | `zig build go` 후 변경된 생성 파일과 `zigo/`를 함께 커밋 |
| 타입을 지원하지 않는다는 `ZIGO...` 진단 | [지원 범위와 제한사항](limitations.md)의 타입·ABI 규칙 확인 |

## 다음 단계

- 백엔드와 Go 패키지 설정: [빌드 설정](configuration.md)
- 함수 메타데이터와 타입 등록: [`bindings.zig` 선언](bindings.md)
- 생성 파일과 CI 세부 정책: [생성물과 CI 관리](generated-code.md)
- 자신의 API와 가까운 실행 예제: [예제 선택 가이드](examples.md)
- C 컴파일러 없는 Go 빌드: [공유 라이브러리와 purego](purego.md)
- 플랫폼, 타입, ABI와 수명 제약: [지원 범위와 제한사항](limitations.md)
