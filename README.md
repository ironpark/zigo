# zigo

zigo는 Zig 라이브러리의 공개 API를 관측해 Go 바인딩을 생성한다. Zig의 comptime
reflection 결과를 바탕으로 C ABI shim, C 헤더, cgo 코드와 Go API를 함께 만든다.

> 상태: v1 구현 완료. Zig 0.16.0과 Go 1.23 이상에서 네이티브 macOS/Linux 빌드를 지원한다.

## 주요 기능

- Zig 라이브러리 소스를 수정하지 않고 `bindings.zig`에서 노출할 API를 선언한다.
- 스칼라, 슬라이스, 에러 유니온, opaque 타입, tagged-union accessor, generic specialization과 콜백을 지원한다.
- Go용 raw 계층과 public 계층, C 헤더와 Zig shim을 한 번에 생성한다.
- `go-check`로 생성물 동기화를 검사하고, 필요하면 `abi-check`를 켜 호환성 파괴를 막는다.
- opt-in purego 백엔드로 공유 라이브러리를 런타임에 로드해 `CGO_ENABLED=0` Go 빌드를 지원한다.

## 빠른 시작

요구사항은 Zig 0.16.0, Go 1.23 이상, cgo가 활성화된 네이티브 빌드 환경이다.

```bash
zig fetch --save git+https://github.com/ironpark/zigo
```

라이브러리 모듈과 zigo 빌드 단계를 연결한다.

```zig
// build.zig
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

이전 배포 버전과의 ABI·바인딩 계약을 유지해야 할 때만 `abi_base`를 추가한다.

```zig
// addGoBindings options
.abi_base = "HEAD",

```

`addStandardSteps`는 `go`, `go-check`, `go-report`, `go-doctor`, `go-lib`, `go-verify`와,
`abi_base`가 있을 때 `abi-check`를 등록한다. `go-verify`는 생성물 최신 상태, 네이티브
라이브러리, 툴체인 전제, ABI 검사를 한 번에 실행한다. 바인딩 세트가 여러 개면
`.name_prefix = "admin"`처럼 지정해 `admin-go`, `admin-go-check` 형식의 독립된 스텝을
만든다.

Go에 노출할 선언을 별도 파일에 적는다.

```zig
// src/bindings.zig
const zigo = @import("zigo");
const mylib = @import("mylib");

pub const bindings = zigo.define(.{
    .root = mylib,
    .discover = .public,
});
```

바인딩을 생성하고 Go 테스트를 실행한다.

```bash
zig build go
zig build go-doctor
zig build go-report
cd go && go test ./...
```

생성된 opaque 메서드는 nil·closed handle을 cgo 진입 전에 검사하고 `*HandleError`로
panic한다. Tagged union은 panic하지 않고 처리할 수 있는 `TryTag`와 `TryAs*`도 함께
생성하며, 모든 exported 생성 선언에는 ownership과 실패 계약을 설명하는 GoDoc이 붙는다.

## cgo 없는 빌드

C 컴파일러 없이 Go 애플리케이션을 빌드해야 하면 purego 백엔드를 추가로 등록한다. 공개 Go
API는 그대로이고 네이티브 공유 라이브러리를 실행 시점에 로드한다.

```zig
const purego_bindings = zigo.addGoBindings(b, .{
    // 같은 필수 옵션들…
    .go_dir = b.path("go-purego"),
    .go_module = "example.com/mylib/go-purego",
    .backend = .purego,
    .link_mode = .dynamic,
});
_ = purego_bindings.addStandardSteps(b, .{ .name_prefix = "purego" });
```

```bash
zig build purego-go            # 공유 라이브러리 설치와 Go 소스 생성
zig build purego-go-verify     # 전제, 생성물, 설치된 아티팩트 검증
cd go-purego && CGO_ENABLED=0 go test ./...
```

`library_loading`으로 라이브러리를 찾을 위치와 순서, 첫 호출 자동 로딩, 로더 API 노출
여부를 선언할 수 있다. 공유 라이브러리는 여전히 타깃별 아티팩트이므로 배포 대상
OS·아키텍처마다 빌드해야 한다.
로드 경로, 패키징, 콜백 제약은 [공유 라이브러리와 purego 백엔드](docs/wiki/purego.md)에
정리되어 있다.

## 문서

- [사용자 위키](docs/wiki/README.md)
- [설치와 사용](docs/wiki/getting-started.md)
- [설정과 생성물](docs/wiki/configuration.md)
- [공유 라이브러리와 purego 백엔드](docs/wiki/purego.md)
- [제한사항과 운영 주의사항](docs/wiki/limitations.md)
- [프로젝트 개발](docs/wiki/development.md)
- [설계 문서](docs/design/README.md)
- [통합 파이프라인 예제](examples/05-pipeline/README.md)
- [상태 기반 event queue 예제](examples/07-event-queue/README.md)
- [51개 함수의 대형 telemetry hub 예제](examples/08-telemetry-hub/README.md)
- [두 opaque 타입의 교차 참조 예제](examples/09-type-relations/README.md)
- [tagged union 자동 accessor 예제](examples/10-tagged-union/README.md)
