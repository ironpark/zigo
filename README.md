# zigo

Zig 라이브러리의 공개 API에서 타입 안전한 Go 바인딩을 생성합니다. 라이브러리 구현을
수정하지 않고 별도의 `bindings.zig`에 노출 범위를 선언하면, zigo가 C ABI shim과 헤더,
cgo 코드, 사용하기 편한 Go API를 함께 만듭니다.

> 현재 지원 범위: Zig 0.16.0, Go 1.24 이상. 기본 cgo 백엔드는 macOS/Linux와
> Windows(amd64, `CC="zig cc"`)를, opt-in `.link = .purego`는
> macOS/Linux/Windows의 amd64·arm64를 지원합니다. Windows cgo에는 mingw-w64가
> 필요하지 않습니다. 자세한 내용은 [시작 가이드](docs/getting-started.md)를
> 보세요.

## 어떤 문제를 해결하나요?

- Zig 함수와 타입을 손으로 C ABI에 옮기는 반복 작업을 줄입니다.
- 스칼라, 슬라이스, 에러 유니온, enum, opaque handle, extern struct, tagged union,
  generic specialization과 Go 콜백을 하나의 선언 방식으로 다룹니다.
- 생성된 raw 계층을 감추고 생성자, `Close`, typed error 등 Go다운 공개 API를 제공합니다.
- `go-check`와 선택적인 `abi-check`로 Go 생성물 누락과 호환성 파괴를 CI에서 찾습니다.
- 필요하면 purego 백엔드로 `CGO_ENABLED=0` Go 빌드를 지원합니다.

## 빠른 시작

설정 전에 실행 결과부터 보고 싶다면 [최소 실행 예제](examples/00-quick-start/README.md)를
사용하세요. 외부 native 라이브러리 없이 생성부터 Go 프로그램 실행까지 확인할 수 있습니다.

Zig 라이브러리 프로젝트에서 zigo를 의존성으로 추가합니다.

```bash
zig fetch --save git+https://github.com/ironpark/zigo#0.9.1
```

`build.zig`에 바인딩 생성을 연결합니다. 아래는 기본값인 cgo 정적 링크 구성입니다.

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
        .go_dir = b.path("go"),
        .go_module = "example.com/mylib/go",
        .target = target,
        .optimize = optimize,
    });
    _ = bindings.addStandardSteps(b, .{});
}
```

먼저 `src/root.zig`에 예제에서 노출할 함수를 준비합니다.

```zig
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

다음 선언을 `src/bindings.zig`에 저장합니다.

```zig
const zigo = @import("zigo");
const mylib = @import("mylib");

pub const bindings = zigo.define(.{
    .root = mylib,
    .functions = .{.{ .path = "root.add" }},
});
```

바인딩을 생성하고 Go 테스트를 실행합니다.

```bash
zig build go
(cd go && go test ./...)
```

아직 테스트 파일이 없다면 이 명령은 패키지 빌드만 확인합니다. 실제 호출을 검증하는
테스트는 [시작 가이드](docs/getting-started.md)에 있습니다.

공개 함수는 `example.com/mylib/go/mylib` 패키지의 `mylib.Add(2, 3)`으로 호출합니다.
생성된 Go 소스와 `zigo/` 메타데이터는 저장소에 커밋합니다
([커밋 대상과 예외](docs/generated-code.md#생성-파일)). 실제 Go 호출 테스트와 CI 연결은
[시작 가이드](docs/getting-started.md)에서 이어집니다.

## 백엔드 선택

처음에는 기본값인 `.cgo_static`을 권장합니다.

| 필요한 동작 | `link` 값 | 추가로 알아둘 점 |
|---|---|---|
| 하나의 Go 실행 파일에 정적으로 링크 | `.cgo_static` | 기본값이며 별도 설정이 필요 없습니다 |
| 공유 라이브러리를 cgo로 링크 | `.cgo_dynamic` | 런타임 라이브러리 경로를 배포 환경에서 관리합니다 |
| C 컴파일러 없이 Go 빌드 | `.purego` | OS·아키텍처별 공유 라이브러리를 함께 배포합니다 |

purego를 선택했다면 [공유 라이브러리와 purego](docs/purego.md)를 먼저 읽어 주세요.

## 문서

- [시작 가이드](docs/getting-started.md) — 설치부터 첫 생성, 테스트, CI까지
- [빌드 설정](docs/configuration.md) — 백엔드, 패키지, cleanup과 ABI 옵션
- [`bindings.zig` 선언](docs/bindings.md) — 함수, 타입, 메타데이터와 생성 Go 오류
- [생성물과 CI 관리](docs/generated-code.md) — 빌드 스텝, 생성 파일과 커밋 정책
- [예제 선택 가이드](docs/examples.md) — 기능별로 가장 가까운 실행 가능한 예제 찾기
- [지원 범위와 제한사항](docs/limitations.md) — 타입, ABI, 수명과 플랫폼 제약
- [사용자 문서 전체 목차](docs/README.md) — 목적별 문서 탐색
- [프로젝트 개발](docs/development.md) — 저장소 기여자를 위한 검증 절차

내부 구조가 궁금하다면 [설계 문서](docs/.agent/design/README.md)를 참고하세요.

## 라이선스

[MIT License](LICENSE)
