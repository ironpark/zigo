# 설치와 사용

## 준비 사항

- Zig 0.16.0
- Go 1.23 이상
- cgo가 활성화된 macOS 또는 Linux 네이티브 빌드 환경
- ABI 검사를 위한 Git 저장소

## 1. 의존성 추가

프로젝트 루트에서 zigo를 Zig 패키지 의존성으로 추가한다.

```bash
zig fetch --save git+https://github.com/ironpark/zigo
```

## 2. 빌드 그래프 연결

다음은 `examples/01-scalar`와 같은 최소 구성이다.

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

    b.step("go", "Generate Go bindings").dependOn(&bindings.update.step);
    b.step("go-check", "Check generated bindings").dependOn(&bindings.check.step);
}
```

## 3. 공개 API 선언

라이브러리 구현은 그대로 두고 `src/bindings.zig`에 Go로 노출할 선언만 적는다.
작은 API나 정밀한 allowlist가 필요하면 함수 목록을 명시한다.

```zig
const zigo = @import("zigo");
const mylib = @import("mylib");

pub const bindings = zigo.define(.{
    .types = .{
        .{ .type = mylib.Context, .repr = .@"opaque" },
    },
    .functions = .{
        .{ .name = "create", .@"fn" = mylib.Context.create },
        .{ .name = "process", .@"fn" = mylib.Context.process, .params = .{ "input", "output" } },
        .{ .name = "deinit", .@"fn" = mylib.Context.deinit },
    },
});
```

공개 함수 전체가 바인딩 대상인 큰 API는 자동 발견을 명시적으로 선택할 수 있다.

```zig
pub const bindings = zigo.define(.{
    .root = mylib,
    .discover = .public,
    .types = .{
        .{ .type = mylib.Context, .repr = .@"opaque" },
    },
    .overrides = .{
        .{ .path = "Context.name", .semantic = .utf8_string },
    },
    .exclude = .{"Context.debugState"},
});
```

자동 발견에서 등록 타입의 함수는 `Context.process`, 모듈 함수는 `root.version` 경로로
override하거나 제외한다. 새 공개 함수도 자동으로 ABI에 들어오므로 생성물과 ABI 검사를
통해 변경을 리뷰한다.

Generic 타입은 구체화된 타입을 이름과 함께 등록한다.

```zig
.specializations = .{
    .{ .name = "FloatBuffer", .type = mylib.Buffer(f32) },
},
```

문자열 의미나 retained 콜백처럼 reflection만으로 알 수 없는 계약은 메타데이터로
선언한다. 자세한 필드는 [설정과 생성물](configuration.md)을 참고한다.

## 4. 생성과 검사

```bash
zig build go
cd go && go test ./...
```

`zig build go`는 Zig 라이브러리와 헤더를 설치하고 Go 소스, `semantic.json`, 안정적인
에러 코드 잠금 파일을 갱신한다. 생성된 소스와 `zigo/` 메타데이터는 함께 커밋한다.

CI에서는 기본적으로 생성물 최신 상태와 Go 동작을 검사한다.

```bash
zig build go-check
cd go && go test ./...
```

`go-check`는 생성 결과와 커밋된 파일이 다르면 실패한다.

독립 배포된 이전 버전과의 ABI·바인딩 계약을 유지해야 한다면 명시적으로 활성화한다.

```zig
const bindings = zigo.addGoBindings(b, .{
    // 다른 필수 옵션들…
    .abi_base = "HEAD",
});
if (bindings.abi_check) |abi_check|
    b.step("abi-check", "Check ABI compatibility").dependOn(&abi_check.step);
```

이후 CI에서 `zig build go-check abi-check`를 실행한다. `abi-check`는 지정한 Git ref의
`zigo/semantic.json`과 현재 계약을 비교해 함수·타입·C 심볼·package/prefix·constructor
mapping의 호환성 파괴를 검사한다. `abi_base`를 생략하면 Git baseline 명령과
`abi_check` handle이 만들어지지 않는다.

## 다음 단계

- raw Go 패키지 위치, 링크 방식, cgo 플래그: [설정과 생성물](configuration.md)
- 지원하지 않는 타입과 수명 계약: [제한사항과 운영 주의사항](limitations.md)
- generic과 system library까지 조합한 코드: [통합 파이프라인 예제](../../examples/05-pipeline/README.md)
- 상태, 용량 정책과 callback 수명을 조합한 코드: [event queue 예제](../../examples/07-event-queue/README.md)
- 51개 함수와 여러 계약을 한꺼번에 생성하는 코드: [telemetry hub 예제](../../examples/08-telemetry-hub/README.md)
