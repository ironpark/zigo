# 첫 Go 바인딩 만들기

이 가이드는 기존 Zig 라이브러리에 기본 cgo 정적 바인딩을 연결합니다. 완료하면 Zig의
`add` 함수를 생성된 Go 패키지에서 호출하고 테스트할 수 있습니다.

완성된 프로젝트를 먼저 실행하려면 [00-quick-start](../examples/00-quick-start/README.md)를
사용하세요.

## 준비

다음 도구가 필요합니다.

- Zig 0.16.0
- Go 1.24 이상과 `gofmt`
- cgo에서 사용할 C 컴파일러

Windows에서는 별도 mingw-w64 대신 `CC="zig cc"`를 사용할 수 있습니다. 처음에는 현재
호스트용 빌드부터 완료하고 다른 백엔드와 타깃은
[설정과 백엔드](build-and-ship/configuration-and-backends.md)에서
선택하세요.

## 1. 프로젝트 만들기

기존 프로젝트가 없다면 빈 디렉터리에서 시작합니다.

```bash
mkdir mylib
cd mylib
zig init
zig fetch --save git+https://github.com/ironpark/zigo#0.24.0
mkdir -p go
```

아래 단계에서 파일을 작성하면 핵심 구조는 다음과 같습니다. `zig init`이 만든 다른 파일은
이 가이드에서 사용하지 않습니다.

```text
.
├── build.zig
├── build.zig.zon
├── go/                  # 생성 Go 모듈
└── src
    ├── bindings.zig
    └── root.zig
```

`zig fetch`가 추가한 URL과 hash는 재현 가능한 빌드를 위해 함께 커밋합니다.

## 2. Zig API 작성하기

`src/root.zig`에 Go로 공개할 함수를 만듭니다.

```zig
/// Adds two signed 32-bit integers. The sum must fit in i32.
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

zigo는 Zig 구현을 수정하지 않습니다. 어떤 API를 Go에 공개할지는 별도의 바인딩 선언 파일에서
결정합니다.

## 3. 공개 범위 선언하기

`src/bindings.zig`를 만듭니다.

```zig
const zigo = @import("zigo");
const mylib = @import("mylib");

const api = zigo.scope(mylib);

pub const bindings = zigo.define(.{
    .root = mylib,
    .declarations = &.{
        api.func("add", .{}),
    },
});
```

`zigo.scope(mylib)`는 선언을 선택할 기준점을 만들고 `api.func("add", .{})`는 루트 모듈의
공개 함수 하나를 선택합니다. 더 많은 타입과 함수는 이 목록에 명시적으로 추가할 수 있습니다.

## 4. 빌드 그래프 연결하기

`build.zig`를 다음 내용으로 바꿉니다.

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

프로젝트에 맞게 바꿀 값은 다음 세 가지입니다.

- `mylib`: Zig 모듈과 바인딩 set의 이름
- `go`: 생성할 Go 모듈 디렉터리
- `example.com/mylib/go`: 실제 Go 모듈 경로

`source_root`는 Zig 소스의 파라미터 이름과 문서 주석을 생성 Go API에 보강합니다. 대상
모듈의 루트 파일을 알고 있다면 지정하는 것을 권장합니다.

## 5. 생성하기

프로젝트 루트에서 실행합니다.

```bash
zig build go
```

성공하면 `go/` 아래에 Go 모듈, 공개 `mylib` 패키지와 내부 raw 패키지가 생성됩니다.
프로젝트 루트의 `zigo/`에는 semantic과 ABI 검사용 메타데이터가 생성됩니다.

공개 함수의 import 경로는 기본적으로 `<go_module>/<go_package>`이므로 이 예제에서는
`example.com/mylib/go/mylib`입니다.

## 6. Go에서 호출하기

`go/mylib/add_test.go`를 만듭니다. `_gen.go` 접미사가 없는 파일은 사용자 코드이며 다시
생성해도 보존됩니다.

```go
package mylib_test

import (
    "testing"

    "example.com/mylib/go/mylib"
)

func TestAdd(t *testing.T) {
    if got := mylib.Add(2, 3); got != 5 {
        t.Fatalf("Add(2, 3) = %d, want 5", got)
    }
}
```

테스트를 실행합니다.

```bash
gofmt -w go/mylib/add_test.go
(cd go && go test ./...)
```

성공하면 `ok example.com/mylib/go/mylib`로 시작하는 결과가 나옵니다. 소요 시간과 내부
패키지의 출력은 환경에 따라 다릅니다. 테스트가 통과하면 첫 바인딩이 완성된 것입니다.

## 평소 작업 흐름

Zig API나 `bindings.zig`를 바꾼 뒤 다음 순서로 확인합니다.

```bash
zig build go
zig build go-doctor
(cd go && go test ./...)
```

- `go`: Go 코드, ABI shim과 메타데이터를 갱신합니다.
- `go-doctor`: Go, `gofmt`, cgo와 C 컴파일러 전제를 점검합니다.
- `go-report`: 최종 이름, 소유권과 콜백 retention 결정을 설명합니다.
- `go-check`: 커밋한 생성물이 현재 선언과 같은지 검사합니다.

생성된 Go 소스와 `zigo/semantic.json`, `zigo/errors.lock.json`은 일반적으로 커밋합니다.
정확한 파일 범위와 CI 구성은 [생성물과 CI](build-and-ship/generated-files-and-ci.md)를
참고하세요.

## 다음 단계

- 함수와 타입을 더 공개하려면 [바인딩 작성](authoring/README.md)
- 자신의 API와 가까운 코드를 찾으려면 [예제](examples.md)
- cgo 동적 링크나 purego가 필요하면 [설정과 백엔드](build-and-ship/configuration-and-backends.md)
- 지원하지 않는 타입이나 플랫폼을 확인하려면 [지원 범위](reference/support-matrix.md)
- 생성이 실패했다면 [문제 해결](troubleshooting.md)
