# zigo

**Zig 라이브러리에서 Go 바인딩을 생성한다.** comptime reflection으로 공개 API를 관측해
C ABI shim · C 헤더 · cgo 바인딩을 만든다.

**Zig 패키지 의존성**으로 추가하고 `zig build go` 로 사용한다.

> 상태: v1 구현 완료. Zig 0.16.0과 Go 1.23 이상에서 네이티브 macOS/Linux 빌드를 지원한다.

---

## 왜

Zig 라이브러리를 Go에서 쓰려면 보통 이런 걸 손으로 쓴다:

- 슬라이스·optional·error union을 C ABI로 낮추는 `export fn` 더미
- 그에 대응하는 C 헤더
- cgo 래퍼, `-L`/`-I` 경로, 포인터 생명주기 관리
- 그리고 Zig API가 바뀔 때마다 **전부 다시**

zigo는 이걸 전부 생성한다. 핵심 아이디어는 **Zig 소스를 파싱하지 않는 것**이다.
Zig 컴파일러가 이미 해결해 놓은 타입 해석·alias·generic 구체화 결과를
`@typeInfo`로 그대로 받아 쓴다.

---

## 사용법

```bash
zig fetch --save git+https://github.com/ironpark/zigo
```

**build.zig** — 유일한 진입점:

```zig
const std  = @import("std");
const zigo = @import("zigo");

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
        .module    = mylib,
        .bindings  = b.path("src/bindings.zig"),
        .go_dir    = b.path("go"),
        .go_module = "github.com/me/mylib/go",
        .target    = target,
        .optimize  = optimize,
    });

    b.step("go",        "Generate Go bindings").dependOn(&go.update.step);
    b.step("go-check",  "Fail if bindings are stale").dependOn(&go.check.step);
    b.step("abi-check", "Fail on breaking ABI change").dependOn(&go.abi_check.step);
}
```

**src/bindings.zig** — 라이브러리는 수정하지 않는다. 노출 의도만 별도로 선언한다:

```zig
const zigo = @import("zigo");
const lib  = @import("mylib");

pub const bindings = zigo.define(.{
    .types = .{
        .{ .type = lib.Context, .repr = .@"opaque" },
    },
    .specializations = .{
        .{ .name = "FloatBuffer", .type = lib.Buffer(f32) },
    },
    .functions = .{
        .{ .@"fn" = lib.Context.process, .params = .{ "input", "output" } },
        .{ .@"fn" = lib.version, .returns = .borrowed, .semantic = .utf8_string },
    },
});
```

```bash
zig build go
cd go && go test ./...
```

CI:
```bash
zig build go-check abi-check
```

---

## 무엇이 생성되는가

입력 Zig:

```zig
pub const Context = struct {
    pub fn init() !Context;
    pub fn process(self: *Context, input: []const f32, output: []f32) !usize;
    pub fn deinit(self: *Context) void;
};
```

Go:

```go
type Context struct{ /* ... */ }

func NewContext() (*Context, error)
func (c *Context) Process(input []float32, output []float32) (int, error)
func (c *Context) Close()
```

사이의 C ABI 경계는 생성물이며 직접 볼 일이 거의 없다:

```c
int32_t zg_context_init(zg_context **out);
int32_t zg_context_process(zg_context *self,
                           const float *input,  size_t input_len,
                           float *output, size_t output_len, size_t *output_written,
                           size_t *out_result);
void    zg_context_deinit(zg_context *self);
```

파일 배치:

```text
src/root.zig            👤 라이브러리 (무수정)
src/bindings.zig        👤 노출 선언 — 공개 API 계약서
zigo/semantic.json      🤖 커밋됨. ABI diff 기준
zigo/errors.lock.json   🤖 커밋됨. 안정 에러코드
go/internal/raw/        🤖 100% 생성
go/mylib/
  mylib_gen.go          🤖 덮어써짐
  custom.go             👤 사용자 확장
zig-out/lib/libmylib_zigo.a
```

생성되는 Go 파일은 package 이름을 snake_case로 정규화한 `<package>_gen.go`를 쓴다.
이전 버전의 `generated.go`와 `internal/raw/cgo.go`가 남아 있다면 업그레이드할 때 한 번
삭제해야 중복 선언을 피할 수 있다.

raw 계층의 기본 위치는 `go/internal/raw/raw_gen.go`다. 필요하면 `addGoBindings`에서
다른 상대 패키지 경로나 public package와 같은 위치를 선택할 수 있다:

```zig
// go/support/ffi/ffi_gen.go
.raw_package = .{ .path = "support/ffi" },

// go/mylib/mylib_cgo_gen.go; package mylib
.raw_package = .colocated,
```

사용자 경로는 `go_dir` 기준이며 각 요소에는 영문자, 숫자, `_`, `-`, `.`만 쓸 수 있고
절대 경로와 `.`/`..` 요소는 허용하지 않는다. 동위치
모드의 low-level 함수는 public wrapper와 충돌하지 않도록 비공개 `zigoRaw*` 이름을 쓴다.
기존 프로젝트에서 모드나 경로를 바꾸면 `zig build go` 실행 후 이전 raw `_gen.go` 파일은
한 번 직접 삭제해야 한다.

---

## 설계상 중요한 결정들

**진입점은 build.zig 하나다.**
reflector는 사용자 라이브러리를 `@import`해야 하고, 그 모듈의 의존성·컴파일 옵션·타깃은
build.zig에만 있다. 빌드 그래프 안에서는 모듈 배선만으로 해결되고,
프로젝트와 동일한 Zig 컴파일러가 보장되며, cgo의 `-L`/`-I` 경로도 자동으로 계산된다.

**라이브러리 코드에 어노테이션을 넣지 않는다.**
`bindings.zig` 하나가 공개 API 계약서다. 리뷰 대상이 생성된 바인딩이 아니라 이 파일이 된다.

**생성물은 소스 트리에 커밋된다.**
`go get`으로 이 패키지를 받는 사람은 Zig를 갖고 있지 않다. gopls와 `go build`도
안정된 경로를 요구한다. `go-check` 스텝이 최신성을 CI에서 강제한다.

**Go API를 raw/public 두 계층으로 생성한다.**
raw 계층은 기본적으로 `internal/raw`에 생성되며 위치를 바꾸거나 public package에 합칠 수 있다.
public 계층은 사용자가 특정 타입만 직접 작성해 덮어쓸 수 있다.
생성기가 완벽하게 Go다운 API를 만들지 못해도 프로젝트가 막히지 않는다.

**추론이 애매하면 생성하지 않고 진단을 낸다.**
일반 Zig struct는 레이아웃이 명세되어 있지 않으므로 값 전달을 시도하지 않고 opaque로만 노출한다.
`anyerror` 반환, `callconv(.c)` 아닌 함수 포인터, 포인터를 품은 슬라이스도 전부 거부한다.
조용히 깨지는 바인딩보다 빌드 실패가 낫다.

**에러 코드는 `@intFromError`를 쓰지 않는다.**
그 값은 빌드마다 달라질 수 있다. 대신 `errors.lock.json`에 append-only 안정 매핑을 커밋한다.

**시스템 링크 설정도 빌드 그래프에서 가져온다.**
사용자 모듈의 `linkSystemLibrary`와 `linkFramework` 설정은 생성된 `#cgo LDFLAGS`에
전달된다. 배포 경로가 다르면 `cgo_flags`로 CFLAGS/LDFLAGS를 명시적으로 덮어쓸 수 있다.

**Go 전용이다.**
IR은 reflector↔generator 프로세스 경계, ABI diff 기준, generator 테스트 픽스처로 존재한다.
언어 중립성을 위한 추상화 계층은 넣지 않는다.

---

## ABI Diff

`semantic.json`이 커밋되어 있으므로 API 호환성 검사는 거의 공짜다.

```text
$ zig build abi-check
BREAKING: Context.process: signature changed
ADDED: Decoder.flush: function added
ABI COMPATIBLE: Decoder.open: error appended
```

---

## 한계 (알고 시작할 것)

- **Zig panic 이후 정상 처리를 계속하면 안 된다.** C 경계가 panic을 코드 `-2`로 바꾸고
  `zg_last_error_message()`에 메시지를 남기지만, 이는 진단을 위한 격리다. 메시지를 수집한 뒤
  해당 작업을 중단해야 하며 복구된 것으로 간주하면 안 된다.
- **파라미터 이름은 reflection에 없다.** `bindings.zig`의 `.params`로 공급하거나,
  AST에서 추출하거나, `p0/p1` 폴백이 된다.
- **cgo 호출은 싸지 않다.** 호출당 작업량이 작은 API를 1:1로 노출하면 실용성이 떨어진다.
  배치 지향 API 설계를 권장한다.
- **v1은 크로스 컴파일을 지원하지 않는다.** reflector는 *실행*되어야 하므로
  타깃 레이아웃을 뽑을 수 없다 ([상세](docs/00-constraints.md)).
- **`retained` 포인터/콜백은 명시가 필요하다.** Go GC와 충돌하지 않으려면 생명주기를 IR에 적어야 한다.

---

## 문서

| 문서 | 내용 |
|---|---|
| [`docs/00-constraints.md`](docs/00-constraints.md) | 기술적 제약, 하강 실패 조건 9종, 리스크 등록부 |
| [`docs/01-architecture.md`](docs/01-architecture.md) | 빌드 그래프, `addGoBindings` API, 소유권 모델, ABI diff |
| [`docs/02-ir-spec.md`](docs/02-ir-spec.md) | semantic / layout / errors.lock 스키마 |
| [`docs/03-lowering-rules.md`](docs/03-lowering-rules.md) | Zig → C ABI → Go 변환 전체 표, 실패 조건 9종, cgo 지시자 |
| [`docs/04-implementation-plan.md`](docs/04-implementation-plan.md) | M0–M8 마일스톤, 디렉터리 구조, 검증 전략 |

## 요구사항

- Zig 0.16.0
- Go 1.23+ (cgo 활성)

## zigo 자체 개발

```bash
zig build test --summary all

for example in examples/*; do
  (cd "$example" && zig build go-check abi-check)
  (cd "$example/go" && go test ./...)
done
```
