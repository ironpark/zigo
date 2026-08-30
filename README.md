# zigo

zigo는 Zig 라이브러리의 공개 API를 관측해 Go 바인딩을 생성한다. Zig의 comptime
reflection 결과를 바탕으로 C ABI shim, C 헤더, cgo 코드와 Go API를 함께 만든다.

> 상태: v1 구현 완료. Zig 0.16.0과 Go 1.23 이상에서 네이티브 macOS/Linux 빌드를 지원한다.

## 주요 기능

- Zig 라이브러리 소스를 수정하지 않고 `bindings.zig`에서 노출할 API를 선언한다.
- 스칼라, 슬라이스, 에러 유니온, opaque 타입, generic specialization과 콜백을 지원한다.
- Go용 raw 계층과 public 계층, C 헤더와 Zig shim을 한 번에 생성한다.
- `go-check`로 생성물 동기화를 검사하고, 필요하면 `abi-check`를 켜 호환성 파괴를 막는다.

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
        .go_dir = b.path("go"),
        .go_module = "example.com/mylib/go",
        .target = target,
        .optimize = optimize,
    });
    b.step("go", "Generate Go bindings").dependOn(&bindings.update.step);
    b.step("go-check", "Check generated bindings").dependOn(&bindings.check.step);
}
```

이전 배포 버전과의 ABI·바인딩 계약을 유지해야 할 때만 옵션과 스텝을 추가한다.

```zig
// addGoBindings options
.abi_base = "HEAD",

// after addGoBindings
if (bindings.abi_check) |abi_check|
    b.step("abi-check", "Check ABI compatibility").dependOn(&abi_check.step);
```

Go에 노출할 선언을 별도 파일에 적는다.

```zig
// src/bindings.zig
const zigo = @import("zigo");
const mylib = @import("mylib");

pub const bindings = zigo.define(.{
    .functions = .{.{ .name = "add", .@"fn" = mylib.add }},
});
```

바인딩을 생성하고 Go 테스트를 실행한다.

```bash
zig build go
cd go && go test ./...
```

## 문서

- [사용자 위키](docs/wiki/README.md)
- [설치와 사용](docs/wiki/getting-started.md)
- [설정과 생성물](docs/wiki/configuration.md)
- [제한사항과 운영 주의사항](docs/wiki/limitations.md)
- [프로젝트 개발](docs/wiki/development.md)
- [설계 문서](docs/design/README.md)
- [통합 파이프라인 예제](examples/05-pipeline/README.md)
- [상태 기반 event queue 예제](examples/07-event-queue/README.md)
