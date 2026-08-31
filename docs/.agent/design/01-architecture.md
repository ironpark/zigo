# zigo 아키텍처

> Zig 라이브러리의 공개 API를 comptime reflection으로 관측해 **Go 바인딩을 생성**한다.
> **Zig 패키지 의존성 + build.zig 스텝**으로 동작한다.

---

## 1. 설계 원칙

1. **Zig 소스를 파싱하지 않는다.** 타입 정보는 전부 comptime reflection에서 나온다.
   (예외: 파라미터 *이름* 추출 시에만 `std.zig.Ast`를 문법 수준으로 사용.)
2. **라이브러리 소스를 오염시키지 않는다.** `export`·어노테이션 없음. 바인딩 의도는 `bindings.zig`에.
3. **사용자 표면은 `addGoBindings` 하나다.** `zig fetch --save` 후 `zig build go` 로 끝난다.
4. **생성물은 소스 트리에 커밋된다.** `zig-cache`가 아니다. Go 도구체인·gopls·`go get`이 그것을 요구한다.
5. **불확실하면 좁게 노출한다.** 추론이 애매하면 생성 실패시키고 명시를 요구한다.
6. **생성기가 완벽할 필요가 없다.** raw 계층은 100% 생성, public 계층은 사람이 덧쓰기 가능.

---

## 2. 사용자 관점 전체 흐름

```bash
zig fetch --save git+https://github.com/ironpark/zigo
```

```zig
// 사용자의 build.zig
const std  = @import("std");
const zigo = @import("zigo");          // 의존성의 build.zig가 모듈로 노출됨

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mylib = b.addModule("mylib", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const go = zigo.addGoBindings(b, .{
        .name      = "mylib",
        .module    = mylib,                        // 관측 대상
        .bindings  = b.path("src/bindings.zig"),   // 유일한 사용자 작성 입력
        .go_dir    = b.path("go"),                 // 생성물이 커밋될 위치
        .go_module = "github.com/me/mylib/go",     // cgo import path 계산용
        .target    = target,
        .optimize  = optimize,
        .abi_base  = "HEAD",                     // 계약 검사를 쓸 때만 지정
    });

    // 관용적 스텝 집합: go, go-check, go-report, go-doctor, go-lib, go-verify
    // (+ abi_base를 준 경우 abi-check). 직접 배선하려면 반환 필드를 그대로 쓴다.
    _ = go.addStandardSteps(b, .{});
}
```

```bash
zig build go          # 생성 + 네이티브 라이브러리 빌드
cd go && go test ./...
```

CI에서는:
```bash
zig build go-verify   # 생성물 최신 여부 + 툴체인 + 네이티브 라이브러리 (+ abi-check)
```

`addStandardSteps(b, .{ .name_prefix = "purego" })` 처럼 접두사를 주면 한 프로젝트가
여러 binding set(예: cgo와 purego)을 동시에 배선할 수 있다.

내부 도구(reflector, generator)는 사용자 빌드 그래프 안에서 컴파일·실행되며
사용자에게 노출되지 않는다.

---

## 3. 패키지가 노출하는 것

zigo 패키지는 3개를 노출한다.

| 이름 | 소비자 | 용도 |
|---|---|---|
| `build.zig`의 `addGoBindings` | 사용자 build.zig | 빌드 스텝 배선 |
| 모듈 `zigo` | 사용자 `bindings.zig` | `zigo.define(...)` DSL |
| (내부) 모듈 `zigo_reflect`, exe `zigo-gen` | zigo 자신 | 사용자에게 비공개 |

사용자가 직접 만지는 표면은 **`addGoBindings` 옵션 구조체와 `zigo.define` 두 개뿐**이다.

---

## 4. 빌드 그래프

`addGoBindings`가 생성하는 스텝들:

```text
 [사용자 module: mylib]      [src/bindings.zig]
            │                        │
            └──────────┬─────────────┘
                       │  createModule("bindings")
                       │    imports: mylib, zigo
                       ▼
        ┌──────────────────────────────────┐
        │ (A) Compile: zigo-reflect exe    │   root = zigo/src/reflect/main.zig
        │     @import("bindings")          │   ← 소스 합성 없음. 모듈 배선만
        └──────────────┬───────────────────┘
                       │ addRunArtifact → captureStdOut()
                       ▼
             semantic.json  (LazyPath)
                       │
        ┌──────────────▼───────────────────┐
        │ (B) Run: zigo-gen                │   순수 함수: IR in → 파일 out
        │   validate → lower → emit        │
        └──────────────┬───────────────────┘
                       │ addOutputDirectoryArg → LazyPath
         ┌─────────────┼──────────────┬──────────────┐
         ▼             ▼              ▼              ▼
 shim.zig+panic.c zigo_mylib.h   go/raw package   go/mylib
                              (cgo 또는 purego loader)
         │             │              │              │
         │             └──────────────┴──────────────┘
         │                            │
         │              ┌─────────────▼──────────────┐
         │              │ (B2) gofmt (있으면)         │  → 별도 cache output
         │              └─────────────┬──────────────┘
         │                            │
         │              ┌─────────────▼──────────────┐
         │              │ (C) UpdateSourceFiles       │  → 소스 트리에 기록
         │              │     또는 check 비교          │
         │              └─────────────────────────────┘
         ▼
   ┌──────────────────────────────┐
   │ (D) addLibrary(static/dyn)   │  shim.zig + panic.c + mylib → libmylib_zigo.{a,dylib,so}
   │     installArtifact          │  → zig-out/lib
   └──────────────────────────────┘
                       │
        ┌──────────────▼───────────────────┐
        │ (E) Run: zigo-gen abi-diff       │  git show HEAD:semantic.json 과 비교
        └──────────────────────────────────┘
```

### (A) Reflector — 모듈 배선으로 구성

reflector의 root는 zigo가 소유한 고정 파일이고, `@import("bindings")`가 사용자 코드를
가리킨다. 소스 합성이나 임시 파일이 필요 없다.

```zig
const bindings_mod = b.createModule(.{
    .root_source_file = opts.bindings,
    .target = opts.target,
    .imports = &.{
        .{ .name = "zigo",     .module = zigo_dsl_mod },
        .{ .name = opts.name,  .module = opts.module  },
    },
});

const reflector = b.addExecutable(.{
    .name = "zigo-reflect",
    .root_module = b.createModule(.{
        .root_source_file = zigo_dep.path("src/reflect/main.zig"),
        .target = opts.target,          // ← 레이아웃 정확도를 위해 사용자 타깃
        .optimize = .Debug,
        .imports = &.{ .{ .name = "bindings", .module = bindings_mod } },
    }),
});
```

`opts.module`이 이미 자신의 의존성·컴파일 옵션·타깃을 갖고 있으므로
reflector는 사용자 라이브러리와 정확히 동일한 조건으로 컴파일된다.

> **타깃 제약:** reflector는 컴파일만이 아니라 **실행되어야 한다.**
> 따라서 v1은 네이티브 타깃만 지원한다. 상세는 [`00-constraints.md` §7](00-constraints.md).

### (B) Generator — 순수 함수

`zigo-gen`은 IR 파일을 읽어 출력 디렉터리에 파일을 쓴다. 그 외 부작용이 없다.
내부 프로세스 프로토콜은 `generate`, `check`, `abi-diff`, `report`, `doctor` 서브커맨드와
named argument를 사용한다. 사용자는 이 실행 파일을 직접 호출하지 않고 `addGoBindings`를 통해서만 사용한다.
Zig 컴파일러도, 사용자 코드도 모른다.

이 경계를 지키는 이유는 **테스트 가능성**이다. 생성기 테스트가
"IR 픽스처 → 골든 파일 비교"로 끝나고, 테스트마다 실제 Zig 프로젝트를 세울 필요가 없다.

### (C) 소스 트리 기록 — 왜 zig-cache가 아닌가

Go 생성물은 반드시 사용자 저장소에 커밋되어야 한다:
- `go get`으로 이 패키지를 받는 사람은 Zig를 갖고 있지 않다
- gopls / `go vet` / IDE가 안정된 경로를 요구한다
- `go build`는 캐시 디렉터리를 모듈 경로로 다루지 않는다

따라서 `std.Build.Step.UpdateSourceFiles`로 생성 결과를 `go_dir`에 기록한다.
`go-check` 스텝은 동일 생성을 수행하되 기록 대신 **비교**하고, 다르면 실패한다 (CI 게이트).
현재 생성 집합의 파일 누락·내용 변경뿐 아니라 zigo generated marker를 가진 이전 생성 파일이
소스 트리에만 남은 경우도 obsolete로 실패한다. marker가 없는 사용자 작성 Go 파일은 비교
대상이 아니다.
`gofmt`가 `PATH`에 있으면 생성된 다섯 Go 파일(raw/cgo, public callables, public types,
public errors, private helpers)을 각각 포맷한 별도 cache output이
`UpdateSourceFiles`와 `go-check`의 입력이 된다. 원본 generator cache는 수정하지 않으며,
`gofmt`가 없는 환경에서는 포맷 단계를 생략한다.

generator는 경로 계산, 모든 emitter 렌더링, `errors.lock.json` 직렬화를 먼저 메모리의
prepared set에서 완료한다. 이 준비 단계가 성공한 뒤에만 출력 디렉터리에 쓰므로 semantic
검증, 렌더링, allocation 실패가 기존 출력 트리를 일부만 갱신하지 않는다. 최종 commit
중 발생하는 머신·파일시스템 장애까지 여러 파일에 걸쳐 원자적으로 복구하는 것은 보장하지
않으며, 소스 트리 반영은 생성 프로세스가 성공한 뒤 `UpdateSourceFiles`가 수행한다.

### (D) 정적 라이브러리와 cgo 배선

생성기는 빌드 그래프로부터 install prefix와 `go_dir`을 알고 있으므로 경로를 직접 계산한다.

```go
// go/internal/raw/raw_gen.go  (생성됨)
package raw

/*
#cgo CFLAGS:  -I${SRCDIR}/../../../zig-out/include
#cgo LDFLAGS: -L${SRCDIR}/../../../zig-out/lib -lmylib_zigo
#include "zigo_mylib.h"
*/
import "C"
```

`${SRCDIR}` 기준 상대 경로는 `go_dir`과 install prefix로부터 계산한다.
사용자가 직접 배포용 경로를 쓰고 싶으면 `.cgo_flags` 옵션으로 덮어쓴다.
사용자 모듈의 `linkSystemLibrary`는 `-l...`, `linkFramework`는 Darwin 전용
`-framework ...` 지시자로 함께 전달된다.

---

## 5. `addGoBindings` 옵션

```zig
pub const Options = struct {
    pub const RawPackage = union(enum) {
        internal,                     // go/internal/raw/raw_gen.go
        colocated,                    // go/mylib/mylib_cgo_gen.go
        path: []const u8,             // go/<path>/<basename>_gen.go
    };

    name: []const u8,                 // Zig 모듈 이름 = C 심볼 유도 기반
    module: *std.Build.Module,        // 관측 대상
    bindings: std.Build.LazyPath,     // bindings.zig
    source_root: ?std.Build.LazyPath = null,  // AST 이름 보강용 모듈 루트
    go_dir: std.Build.LazyPath,       // 생성물 커밋 위치
    go_module: []const u8,            // Go module path (import 경로 생성용)
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,

    prefix: []const u8 = "zg",        // C 심볼 접두사
    link_mode: LinkMode = .static,     // static | dynamic
    backend: Backend = .cgo,           // cgo | purego
    cgo_flags: ?CgoFlags = null,      // null이면 빌드 경로에서 자동 계산
    abi_base: ?[]const u8 = null,      // 지정한 경우에만 ABI diff 활성화
    raw_package: RawPackage = .internal,
    auto_cleanup: bool = false,        // Go 1.24+ best-effort cleanup
    gofmt: ?[]const u8 = null,         // null이면 PATH의 gofmt
    go_package: ?[]const u8 = null,    // public Go package 이름 재지정
    library_loading: LibraryLoading = .{},  // purego 전용 런타임 로딩 정책
};

pub const GoBindings = struct {
    update: *std.Build.Step.UpdateSourceFiles,  // 생성 + 소스 트리 기록
    check: *std.Build.Step.Run,                 // 스테일 검사
    abi_check: ?*std.Build.Step.Run,            // abi_base를 준 경우에만
    report: *std.Build.Step.Run,                // 유효 계약 설명
    doctor: *std.Build.Step.Run,                // 툴체인 전제 조건 점검
    lib: *std.Build.Step.Compile,               // 네이티브 바인딩 라이브러리
    install_library: *std.Build.Step.InstallArtifact,
    library_filename: []const u8,               // 타깃별 basename
    semantic_json: std.Build.LazyPath,          // 후처리용 노출

    pub fn addStandardSteps(self: GoBindings, b: *std.Build, options: StandardStepOptions) StandardSteps;
};
```

스텝 이름을 zigo가 강제하지 않는다. 필드를 직접 `b.step(...)`에 붙여도 되고,
`addStandardSteps`로 관용적 이름(`go`, `go-check`, `go-report`, `go-doctor`, `go-lib`,
`go-verify`, `abi-check`)을 한 번에 등록해도 된다. `name_prefix`로 이름 충돌을 피한다.

`.backend = .purego`는 `.link_mode = .dynamic`을 요구하며 지원 타깃이 네이티브
macOS/Linux의 amd64·arm64로 좁다. `library_loading`은 purego 백엔드에서만 기본값이
아닌 값을 가질 수 있다.

`raw_package.path`는 `go_dir` 기준 상대 slash 경로다. 경로 요소에는 영문자, 숫자,
`_`, `-`, `.`만 허용하며 절대 경로, 역슬래시, 빈 요소와 `.`/`..` 요소는 거부한다.
마지막 경로 요소를 snake_case로 정규화해 Go package와
파일 이름으로 사용하고, public package와 같은 경로가 필요하면 `.colocated`를 사용한다.
동위치에서는 raw 함수를 비공개 `zigoRaw*`로 생성해 public wrapper 이름과 충돌하지 않는다.

---

## 6. IR을 파일로 두는 이유

1. **프로세스 경계.** reflector(사용자 코드와 링크됨)와 generator(순수 함수)는
   별개의 실행 파일이다. 둘 사이에는 직렬화된 표현이 반드시 필요하다.
2. **선택적 ABI diff.** 호환성 정책을 켠 경우 `semantic.json`을 커밋해야 비교가 성립한다.
3. **테스트 가능성.** generator 테스트가 IR 픽스처만으로 완결되고,
   테스트마다 실제 Zig 프로젝트를 세울 필요가 없다.

스키마는 Go에 필요한 만큼만 유지한다. 언어 중립성을 위한 추상화 계층은 넣지 않는다.
C 헤더는 백엔드가 아니라 **cgo가 요구하는 산출물**이다.

---

## 7. 산출물 레이아웃

```text
<repo>/
  build.zig
  src/
    root.zig            # 사용자 라이브러리 (무수정)
    bindings.zig        # 사용자 작성. 유일한 입력
  zigo/
    semantic.json       # ✅ 커밋. ABI diff 기준
    errors.lock.json    # ✅ 커밋. 안정 에러코드
  go/
    go.mod              # 없으면 1회 생성, 이후 👤 사용자 소유
    internal/raw/       # 🤖 100% 생성. 손대지 말 것
      raw_gen.go        # cgo 지시자 또는 purego loader (backend에 따라)
    mylib/
      mylib_gen.go         # 🤖 public callable API
      mylib_type_gen.go    # 🤖 public type API
      mylib_errors_gen.go  # 🤖 package error API
      mylib_helpers_gen.go # 🤖 private runtime support
      custom.go            # 👤 사용자 소유
  zig-out/
    lib/libmylib_zigo.a
    include/zigo_mylib.h
```

**덧쓰기 규칙:** `internal/raw`는 `raw_gen.go`, public package `mylib`은 callable API용
`mylib_gen.go`, enum·callback·opaque handle/Ref와 그 타입 고유 메서드용
`mylib_type_gen.go`, package error용 `mylib_errors_gen.go`를 사용한다. error 파일은 단일
`Error` 타입, 안정적인 `Err*` 값과 code 변환을 함께 소유하며 Zig error set별로 나누지
않는다. bool ABI 변환과 callback handle 수명 관리는 `mylib_helpers_gen.go`에 둔다. 그
밖의 `custom.go` 같은 파일은 사용자 소유이며 생성기가 수정하지 않는다.

`.raw_package = .{ .path = "support/ffi" }`이면 raw 파일은
`go/support/ffi/ffi_gen.go`에 생성되고 public 파일은 해당 package를 `raw` 별칭으로 import한다.
`.raw_package = .colocated`이면 `go/mylib/mylib_cgo_gen.go`가 public 파일 옆에 생성된다.
`UpdateSourceFiles`는 이전 생성물을 삭제하지 않으므로 모드나 경로를 바꾼 뒤에는 예전 raw
`_gen.go` 파일을 한 번 직접 삭제해야 한다.

---

## 8. 사용자 입력 — `bindings.zig`

```zig
const zigo = @import("zigo");
const lib  = @import("mylib");

pub const bindings = zigo.define(.{
    .root = lib,
    .discover = .public,
    .types = .{
        .{ .type = lib.Context, .repr = .@"opaque" },
        .{ .type = lib.Format,  .repr = .value },
        .{ .type = lib.Value,   .repr = .tagged_union },
    },
    .specializations = .{
        .{ .name = "FloatBuffer", .type = lib.Buffer(f32) },   // generic 구체화
    },

    .overrides = .{
        .{ .path = "root.version", .returns = .borrowed, .semantic = .utf8_string },
        .{
            .path = "Context.process",
            .params = .{ "input", "output" },
            .param_meta = .{
                .output = .{ .direction = .out },
            },
        },
    },
    .exclude = .{"root.internalProbe"},
});
```

- compiler reflection이 공개 함수의 존재와 타입을 결정하고 AST가 소유자별 파라미터 이름과 문서를 보강한다.
- `.params`는 AST 이름을 고정하거나 `param_meta`의 키를 reflection 단계에서 제공할 때 사용한다.
- 자동 발견이 맞지 않는 정밀 allowlist는 `.functions` 항목
  (`.{ .name = "add", .@"fn" = lib.add }`)을 사용한다. `.overrides`와 `.exclude`의
  `.path`는 `.discover = .public` 모드에서만 유효하다.
- 나머지 메타데이터는 선택적이며, 없으면 보수적 기본값(`in`, `borrowed`, `[]byte`).
- `package`/`prefix`는 build.zig 옵션으로 이동했다 (빌드 배선과 함께 있는 편이 자연스럽다).
- 이 파일이 **공개 API 계약서**다. 리뷰 대상은 생성된 바인딩이 아니라 이 파일이다.

---

## 9. 소유권 모델

모든 포인터/슬라이스는 세 축을 갖는다.

| 축 | 값 | 기본값 |
|---|---|---|
| `direction` | `in` / `out` / `inout` | `in` |
| `retention` | `borrowed` (호출 스코프 한정) / `retained` | `borrowed` |
| `ownership` | `caller` / `callee` | 반환값은 `caller` |

**추론 (90%):**
- `init|create|new|open` + `!*T` 반환 → 호출자가 해제. 대응 `deinit|destroy|close` 탐색 → Go `Close()` 생성
- `*const T` 반환 → `borrowed` 추정 + **경고** (명시 권장)
- 슬라이스 파라미터 → `borrowed`, `in`

**명시 (10%):** 위와 다른 모든 경우. 애매하면 경고를 내고 메타데이터를 요구한다.

---

## 10. 콜백

```text
Go func ──▶ cgo.Handle (uintptr) ──▶ C 트램폴린 ──▶ Zig callconv(.c) fn ptr + userdata
                                       · handle → Go func 복원
                                       · defer recover() → 에러코드 -3
```

- `borrowed` 콜백: 호출 후 Handle 해제
- `retained` 콜백: Handle을 Go 구조체에 보관, `Close()`에서 `Delete()`.
  이 경우 `Close()`를 **강제 생성**하고 미호출 시 누수임을 문서화한다.
- `.auto_cleanup = true`이면 별도 resource state에 native pointer와 Handle을 복사해
  `runtime.AddCleanup`에 등록한다. 이는 Go 1.24+ 누수 안전망이며 `Close()`를 대체하지 않는다.

---

## 11. ABI Diff

`semantic.json`이 커밋되어 있으므로 순수 데이터 비교다.

```text
$ zig build abi-check

BREAKING (2)
  Context.process   param input: []const f32 → []const f64
  Decoder.reset     removed
ADDED (1)
  Decoder.flush() !void
ABI COMPATIBLE (1)
  error Timeout added (code 8)
```

- 함수 제거 / 시그니처 변경 / 에러코드 재배정 → BREAKING
- 함수·타입 추가, 에러 집합 append, 기존 tag를 보존한 enum/tagged-union 끝부분 variant append → COMPATIBLE
- 반환 소유권·retention 변경 → BREAKING (조용한 메모리 버그를 만들므로)

---

## 12. 비범위 (v1)

- Go 외 언어 — 비범위
- 크로스 컴파일 — 미지원 (reflector 실행 제약, §4 (A))
- allocator를 Go에 노출 — 비범위. 라이브러리 내부 고정 allocator 사용
- Windows·모바일·purego Tier 2 타깃 — 미지원

설계 초안에서 v2로 미뤘던 tagged union 변환, 동적 링크 배포, purego 백엔드는
v1에 구현되었다. 상세는 [구현 상태](05-implementation-status.md).
