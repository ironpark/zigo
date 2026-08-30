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
        .go_dir = b.path("go"),
        .go_module = "example.com/mylib/go",
        .target = target,
        .optimize = optimize,
    });

    b.step("go", "Generate Go bindings").dependOn(&bindings.update.step);
    b.step("go-check", "Check generated bindings").dependOn(&bindings.check.step);
    b.step("abi-check", "Check ABI compatibility").dependOn(&bindings.abi_check.step);
}
```

## 3. 공개 API 선언

라이브러리 구현은 그대로 두고 `src/bindings.zig`에 Go로 노출할 선언만 적는다.
함수 이름은 `.name`으로 명시하는 것이 가장 안정적이다.

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

CI에서는 생성물 최신 상태와 ABI 호환성을 검사한다.

```bash
zig build go-check abi-check
cd go && go test ./...
```

`go-check`는 생성 결과와 커밋된 파일이 다르면 실패한다. `abi-check`는 기본적으로
`HEAD:zigo/semantic.json`을 기준으로 호환성 파괴를 검사하며 기준 ref는 `abi_base`로
바꿀 수 있다.

## 다음 단계

- raw Go 패키지 위치, 링크 방식, cgo 플래그: [설정과 생성물](configuration.md)
- 지원하지 않는 타입과 수명 계약: [제한사항과 운영 주의사항](limitations.md)
- 실제 기능을 조합한 코드: [통합 파이프라인 예제](../../examples/05-pipeline/README.md)
