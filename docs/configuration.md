# 설정과 생성물

## `addGoBindings` 옵션

| 옵션 | 필수 | 설명 |
|---|---:|---|
| `name` | 예 | 생성할 라이브러리와 Go 패키지의 기준 이름 |
| `module` | 예 | reflection할 `*std.Build.Module` |
| `bindings` | 예 | `zigo.define` 선언 파일 |
| `source_root` | 아니요 | AST 이름·문서 보강에 사용할 실제 대상 모듈 루트. 생략하면 `bindings` 옆 `root.zig` 탐색 |
| `go_dir` | 예 | 생성된 Go 모듈을 둘 소스 경로 |
| `go_module` | 예 | 생성될 `go.mod`와 import에 사용할 모듈 경로 |
| `target` | 예 | 라이브러리 타깃 |
| `optimize` | 예 | 라이브러리 최적화 모드 |
| `prefix` | 아니요 | C 심볼 접두사. 기본값 `zg` |
| `link` | 아니요 | `.cgo_static`, `.cgo_dynamic`, `.purego` 중 하나. 기본값 `.cgo_static` |
| `library_loading` | 아니요 | purego 전용 런타임 로딩 정책. search path, 환경 변수, 로더 |
| `gofmt` | 아니요 | 생성물 포맷에 사용할 `gofmt` 경로. 생략하면 `PATH`에서 찾는다 |
| `go_package` | 아니요 | 공개 Go 패키지 이름. 생략하면 `name`의 snake_case |
| `cgo_flags` | 아니요 | 자동 계산 대신 사용할 CFLAGS와 LDFLAGS |
| `abi_base` | 아니요 | ABI·바인딩 계약 비교에 사용할 Git ref. 생략하면 검사 비활성화 |
| `raw_package` | 아니요 | `go_dir` 기준 raw Go 패키지 경로. 기본값 `"internal/raw"` |
| `auto_cleanup` | 아니요 | Go 1.24+ `runtime.AddCleanup` 누수 안전망. 기본값 `false` |

`abi_base`는 호환성 정책이 필요한 프로젝트만 지정한다. 생략하면 zigo는 Git을 호출하지
않고 `GoBindings.abi_check`를 `null`로 반환한다. 활성화한 경우 지정한 ref에 커밋된
`zigo/semantic.json`이 비교 기준이다.

## 표준 빌드 스텝과 진단

`addGoBindings`의 반환값에 표준 스텝을 한 번에 등록할 수 있다.

```zig
const bindings = zigo.addGoBindings(b, .{
    // 필수 옵션…
});
_ = bindings.addStandardSteps(b, .{});
```

등록되는 스텝은 `go`, `go-check`, `go-report`, `go-doctor`, `go-lib`, `go-verify`와,
`abi_base`가 설정된 경우의 `abi-check`다. `go-lib`은 네이티브 바인딩 라이브러리를 빌드해
`zig-out/lib`에 설치하고, `go-verify`는 생성물 최신 상태·네이티브 라이브러리·`go-doctor`와
(설정한 경우) `abi-check`를 한 번에 실행하는 집계 스텝이다. 한 빌드에 바인딩 세트가
여러 개면 이름 접두사를 지정한다.

```zig
_ = admin_bindings.addStandardSteps(b, .{ .name_prefix = "admin" });
// admin-go, admin-go-check, admin-go-report, admin-go-doctor,
// admin-go-lib, admin-go-verify, admin-abi-check
```

`go-report`는 최종 Go 이름과 C 심볼, type representation, constructor/Close mapping,
ownership, parameter retention과 이름 출처, 자동 tagged-union projection을 출력한다.
`go-doctor`는 현재 target이 host에서 실행 가능한지, Go 최소 버전, `gofmt`를 검사하고, 선택한
백엔드에 따라 나머지 전제를 확인한다. `.cgo`에서는 `CGO_ENABLED`와 Go가 설정한 C
컴파일러를, `.purego`에서는 호스트 플랫폼 지원 여부, `go.mod`의 purego 요구사항, 설치된
공유 라이브러리의 존재와 실제 로드 가능 여부를 검사한다. gofmt 부재는 경고지만 cross
target, 낮은 Go 버전, 비활성 cgo, 실행할 수 없는 C 컴파일러, 없는 `gofmt`, 지원하지 않는
purego 플랫폼, 없는 purego 요구사항과 로드할 수 없는 공유 라이브러리는 실패다. 자세한 내용은
[공유 라이브러리와 purego 백엔드](purego.md)를 참고한다.

## 자동 cleanup

Go 1.24 이상만 지원해도 되는 프로젝트는 caller-owned opaque wrapper에 best-effort cleanup을
붙일 수 있다.

```zig
.auto_cleanup = true,
```

이 옵션으로 새 `go.mod`를 만들 때 Go 버전은 1.24로 기록된다. 이미 `go.mod`가 있으면
zigo가 수정하지 않으므로 사용자가 `go 1.24` 이상으로 올려야 한다. 생성기는 wrapper와
독립된 native pointer/callback handle 상태를 `runtime.AddCleanup`에 넘기고, 명시적
`Close`에서는 cleanup을 중단한 뒤 같은 해제 함수를 호출한다. native 호출 중 조기 해제를
막기 위해 관련 wrapper에는 `runtime.KeepAlive`도 생성한다.

cleanup 실행 시점과 프로그램 종료 전 실행은 보장되지 않으므로 `Close`가 여전히 기본
수명 계약이다. retained callback이 소유 wrapper를 캡처하면 `cgo.Handle`에서 wrapper로
이어지는 강한 참조 때문에 cleanup이 실행되지 않을 수 있다. cleanup은 임의 goroutine에서
동시에 실행될 수 있으므로 특정 OS thread나 사용자 동기화가 필요한 deinitializer에는 이
옵션을 사용하지 않는다.

## 링크 방식

`link`는 Go가 네이티브 라이브러리에 닿는 방법을 한 축으로 고른다.

| 값 | 뜻 |
|---|---|
| `.cgo_static` | cgo + 정적 아카이브 (기본값) |
| `.cgo_dynamic` | cgo + 공유 라이브러리 |
| `.purego` | cgo 없음. 실행 시점에 공유 라이브러리에서 심볼을 찾는다 |

예전에는 `backend`와 `link_mode`가 따로 있었지만 존재하지 않는 조합을 표현할 수 있었다.
purego는 정적 링크를 하지 않고 cgo를 거치지도 않는다. 한 축으로 접으면 그 조합이 아예
표현되지 않으므로, 빌드 중 `@panic`으로 배우던 제약이 사라진다.

## raw Go 패키지 위치

기본값은 `go/internal/raw/raw_gen.go`다.

```zig
.raw_package = "internal/raw",
```

다른 상대 경로를 지정하면 마지막 경로 요소를 정규화해 Go 패키지 이름으로 사용한다.

```zig
// go/support/ffi/ffi_gen.go
.raw_package = "support/ffi",
```

public 패키지 경로를 그대로 주면 두 패키지가 같은 디렉터리에 놓인다. 동위치 여부는 별도
옵션이 아니라 이 비교에서 파생된다.

```zig
// go/mylib/mylib_cgo_gen.go — go_package 가 "mylib" 일 때
.raw_package = "mylib",
```

사용자 경로는 `go_dir` 기준의 상대 경로여야 한다. 빈 요소, `.`과 `..`, 절대 경로와
역슬래시는 허용하지 않는다. 각 요소에는 ASCII 영문자, 숫자, `_`, `-`, `.`만 쓸 수
있다. 경로나 모드를 바꾼 뒤에는 이전 위치의 `_gen.go` 파일을 직접 삭제해 중복 선언을
방지한다.

## 마이그레이션: 옵션 축 정리

| 예전 | 지금 |
|---|---|
| `.backend = .cgo, .link_mode = .static` (기본값) | `.link = .cgo_static` (기본값) |
| `.backend = .cgo, .link_mode = .dynamic` | `.link = .cgo_dynamic` |
| `.backend = .purego, .link_mode = .dynamic` | `.link = .purego` |
| `.backend = .purego, .link_mode = .static` | 표현할 수 없다 (예전에는 빌드 중 `@panic`) |
| `.raw_package = .internal` | `.raw_package = "internal/raw"` (기본값) |
| `.raw_package = .{ .path = "support/ffi" }` | `.raw_package = "support/ffi"` |
| `.raw_package = .colocated` | `.raw_package = "<public 패키지 경로>"` |
| `.library_loading = .{}` | 그대로. `loader` 기본값이 `.explicit` |
| `.library_loading = .{ .automatic = true }` | `.library_loading = .{ .loader = .automatic }` |
| `.library_loading = .{ .automatic = true, .exported_api = false }` | `.library_loading = .{ .loader = .automatic_internal }` |
| `.library_loading = .{ .exported_api = false }` | 표현할 수 없다 (아무도 라이브러리를 로드할 수 없다) |

`zigo.Backend`와 `zigo.LinkMode`는 더 이상 공개 타입이 아니다.

## Go 이름 규칙

생성된 Go는 Go 관례를 따른다.

- 공개 파라미터 이름은 Zig의 snake_case를 camelCase로 바꾼다. `source_len`은 `sourceLen`이
  된다. Go에는 named argument가 없으므로 호출자 코드에는 영향이 없다.
- Go 키워드(`type`, `range`, `func` 등)나 생성 코드가 선언하는 지역 변수(`code`, `result`,
  `outResult` 등)와 겹치면 밑줄을 붙여 `type_`, `code_`로 escape한다. 변환 후 두 파라미터
  이름이 같아지면 뒤쪽에 숫자를 붙인다.
- 한 타입의 receiver 이름은 모든 생성 파일에서 동일한 약어를 쓴다.
- Zig doc comment는 Go 식별자 뒤에 한 문장으로 이어 붙인다.

공개 패키지 이름은 기본적으로 `name`의 snake_case이므로 `event_queue`처럼 밑줄이 들어갈 수
있다. Go 관례는 밑줄 없는 패키지 이름이므로 필요하면 바꾼다.

```zig
.name = "event_queue",
.go_package = "eventqueue",
```

`go_package`는 공개 패키지의 이름과 디렉터리만 바꾼다. C 헤더(`zigo_event_queue.h`)와
네이티브 라이브러리(`libevent_queue_zigo.a`)는 `name`을 그대로 쓰므로 아티팩트 위치는
움직이지 않는다. 기본값을 바꾸지 않은 이유는 import 경로가 바뀌는 호환성 파괴이기
때문이다. 유효한 Go 식별자가 아니면 빌드 그래프를 만드는 시점에 실패한다.

## 생성 후 Go 포맷

생성된 raw/cgo, public API, public error, private helper 파일은 `gofmt`로 포맷한 뒤
`go_dir`에 기록하고, `go-check`도 같은 포맷 결과를 비교한다. 사용자 소유 Go 파일은
포맷하지 않는다.

`gofmt`는 **필수**다. 찾지 못하면 생성이 실패하며, `PATH` 대신 특정 실행 파일을 쓰려면
`.gofmt = "/path/to/gofmt"`를 지정한다. `gofmt`는 모든 Go 배포판에 포함되고 zigo는 이미
Go를 요구하므로 추가 의존성이 아니다.

포맷을 generator가 직접 하지 않고 `gofmt`에 맡기는 이유는 정규 형식이 Go 릴리스마다
바뀌기 때문이다. 예를 들어 Go 1.19는 doc comment를 다시 포맷한다. generator가 자체 규칙으로
포맷하면 새 `gofmt`가 생성물을 "미포맷"으로 보고하게 된다. 대신 `gofmt`가 없을 때 조용히
미포맷 결과를 커밋해 머신마다 생성물이 달라지던 동작은 제거했다.

## 링크와 cgo 플래그

zigo는 대상 모듈에 설정된 system library와 framework 링크 정보를 생성된
`#cgo LDFLAGS`로 전달한다. 배포 환경에서 경로를 직접 지정해야 한다면 덮어쓸 수 있다.

```zig
.cgo_flags = .{
    .cflags = &.{"-I/opt/mylib/include"},
    .ldflags = &.{ "-L/opt/mylib/lib", "-lmylib" },
},
```

## `bindings.zig` 선언

선언은 다음 세 그룹을 사용한다.

| 그룹 | 역할 |
|---|---|
| `root` | 경로가 해석되는 기준 모듈. 항상 필요하다 |
| `types` | opaque, tagged-union handle 또는 명시적 representation으로 노출할 타입 |
| `functions` | 바인딩할 함수와 그 메타데이터 |

선언을 지칭하는 방법은 **경로 하나**다. `root.<name>`은 `root` 모듈의 함수를,
`<Type>.<name>`은 `types`에 등록된 타입의 함수를 가리킨다.

```zig
pub const bindings = zigo.define(.{
    .root = mylib,
    .types = .{
        .{ .type = mylib.Context, .repr = .@"opaque" },
    },
    .functions = .{
        .{ .path = "Context.create", .params = .{"name"} },
        .{ .path = "Context.deinit" },
        .{ .path = "root.version" },
    },
});
```

큰 공개 API는 opt-in 자동 발견 모드를 사용할 수 있다. 같은 `functions` 목록이 쓰이며,
이번에는 발견된 함수에 메타데이터를 붙이는 역할을 한다.

```zig
pub const bindings = zigo.define(.{
    .root = mylib,
    .discover = .public,
    .types = .{
        .{ .type = mylib.Context, .repr = .@"opaque" },
    },
    .functions = .{
        .{
            .path = "Context.create",
            .params = .{ "name", "callback", "userdata" },
            .param_meta = .{
                .name = .{ .semantic = .utf8_string },
                .callback = .{ .retention = .retained },
            },
        },
        .{ .path = "Context.name", .semantic = .utf8_string },
    },
    .exclude = .{"Context.debugState"},
});
```

`.discover = .public`은 `types`에 등록된 컨테이너의 공개 함수부터 발견하고, 이어서 `root`
모듈의 공개 함수를 발견한다. 경로 문법은 명시 모드와 같다. `exclude`는 바인딩하지 않을
공개 함수를 지정하며 자동 발견 모드에서만 쓸 수 있다. 명시 목록에서는 적지 않으면 그만이기
때문이다. 존재하지 않는 경로, 중복 경로, 목록과 exclude의 충돌은 컴파일 오류다.

자동 발견은 명시적으로 선택해야 한다. 이 모드에서는 새 `pub fn`이 C/Go API에도
추가되므로 생성물 stale 검사와, 독립 배포 계약이 있다면 `abi-check`를 함께 사용한다.

generic 구체화는 별도 그룹이 아니다. `types`에 `.name`을 붙여 등록하면 된다.

```zig
.types = .{
    .{ .name = "FloatBuffer", .type = mylib.Buffer(f32), .repr = .@"opaque" },
    .{ .name = "IntBuffer", .type = mylib.Buffer(i32), .repr = .@"opaque" },
},
```

### Extern struct 값 파라미터와 반환

Go에서 struct를 값처럼 주고받으려면 Zig에서 `extern struct`로 선언하고 `.repr = .value`로
등록한다. 일반 struct의 배치는 Zig 명세상 보장되지 않으므로 미러링하지 않는다.

```zig
.types = .{
    .{ .type = mylib.Config, .repr = .value },
},
```

공개 API는 값 타입이다.

```go
cfg := Config{Width: 120, Mode: ModeActive}
Configure(cfg)
current := DefaultConfig()
```

다만 C 경계에서는 값으로 넘어가지 않는다. 파라미터는 `const T*`, 반환은 `T*` out
파라미터로 내려가고 주소를 잡는 일은 생성 코드 안에서만 일어난다. aggregate를 값으로
전달하면 플랫폼별 ABI 규칙이 드러나고 purego는 C struct를 값으로 전달하지 못한다.

적격 조건이 있다. **모든 필드가 bool, 정수/부동소수 스칼라, 등록된 enum, 또는 다시 적격한
`extern struct`** 여야 한다. slice, 포인터, optional, error union, callback, 일반 struct
필드가 있으면 생성이 `ZIGO012`로 실패하며 문제된 필드를 지목한다. 필드가 없는 struct도 C
표현이 없으므로 거부한다. struct는 파라미터·반환·error union payload 자리에서만 쓸 수 있고,
slice 원소나 optional, callback 시그니처 안에 넣으면 `ZIGO013`으로 거부한다. `packed
struct`의 정수 백킹 노출은 지원하지 않으며 `ZIGO003`으로 거부한다.

ABI diff는 필드 추가·삭제·순서 변경·타입 변경을 모두 breaking으로 판정한다. 어느 쪽이든
struct의 크기나 offset이 움직이므로 compatible append는 없다.

### Tagged union accessor

tagged union을 값 ABI로 노출하지 않고 포인터 handle로 사용하려면 한 번 등록한다.

```zig
.types = .{
    .{ .type = mylib.Value, .repr = .tagged_union },
},
```

zigo는 `ValueTag`, `TryTag() (ValueTag, error)`와 편의 메서드 `Tag()`를 만들고 payload가
있는 각 variant에 `TryAs<Variant>() (payload, bool, error)`와
`As<Variant>() (payload, bool)`을 생성한다. 같은 accessor는 borrowed `*ValueRef`에도
생긴다. active tag가 다르면 checked accessor는 payload를 읽거나 out 파라미터를 기록하지
않고 `(zero, false, nil)`을 반환한다. `void` variant는 tag 상수만 가진다.

projection의 내부 status는 mismatch, success, invalid handle/required output, Zig panic을
구분한다. checked accessor는 `*HandleError`, `*NativePanicError` 또는 예기치 않은 status의
`*ProjectionError`를 반환한다. `errors.Is(err, ErrInvalidHandle)`과
`errors.Is(err, ErrNativePanic)`으로 분류할 수 있다. 기존 `Tag`와 `As*`는 source
compatibility를 위해 checked accessor를 호출한 뒤 오류가 있으면 같은 typed error로
panic한다. 같은 handle에 대한 `Close`, variant 변경, accessor 호출을 동시에 수행할 때의
직렬화는 호출자 책임이다.

ABI diff는 기존 순서·tag·payload를 보존한 끝부분 variant 추가를 compatible append로
분류한다. 삭제, 재정렬, 이름 변경, 기존 tag/payload 변경과 projection prefix 변경은
breaking이다.

### Tagged union 값 스냅샷

`Tag()`와 `As*()`는 각각 FFI 왕복이므로, payload가 전부 스칼라인 union을 반복해서 읽는
코드는 왕복 비용을 그대로 지불한다. `.access = .snapshot`을 붙이면 zigo가 값
스냅샷 표현을 하나 더 만든다.

```zig
.types = .{
    .{ .type = mylib.Signal, .repr = .tagged_union, .access = .snapshot },
},
```

`TrySnapshot() (SignalSnapshot, error)`와 `Snapshot()`이 tag와 payload를 **native 호출 한
번**으로 가져오고, 그 뒤의 읽기는 순수 Go다.

```go
snapshot := signal.Snapshot()      // 여기까지가 유일한 native 호출
if ticks, ok := snapshot.Ticks(); ok {
    fmt.Println(snapshot.Tag(), ticks)
}
```

`Tag()`는 스냅샷이 담은 variant를, `<Variant>() (payload, bool)`은 payload와 그 variant가
활성이었는지를 함께 돌려준다. `void` variant는 tag 상수만 가진다. 기존
`Tag`/`As*`/`TryAs*`는 그대로 남으므로 스냅샷은 대체가 아니라 추가 API다. 상태 코드와 오류
타입은 projection과 같다.

zigo는 Zig union의 배치를 복제하지 않고 자기 소유의 `extern struct`를 정의한 뒤 shim이
값을 옮겨 담는다. 그래서 적격 조건이 있다. **모든 variant payload가 void, bool, 정수/부동소수
스칼라, 또는 등록된 enum**이어야 하고, `tag`라는 이름의 variant는 쓸 수 없다. 스냅샷 구조체가
discriminant를 `tag` 멤버로 쓰기 때문이다. slice, opaque handle, 중첩 aggregate, optional,
error union, callback payload가 있으면 생성이 `ZIGO011`로 실패하며 문제가 된 variant와
`.repr = .tagged_union` 대안을 알려준다.

선택 기준은 ABI다. projection union은 끝부분 variant 추가가 compatible append지만, 값
스냅샷 union은 구조체의 크기와 배치가 달라지므로 **breaking**이다. 두 표현 사이의 전환도
breaking이다. variant가 앞으로 늘어날 union은 projection에, 모양이 고정된 작고 뜨거운
union은 값 스냅샷에 두는 편이 낫다.

지원 payload는 `void`, bool, 정수, float, enum, 등록된 handle pointer, 숫자 slice다.
숫자 slice는 Zig 메모리 view를 public Go API에 그대로 노출하지 않고 호출마다 복사한다.
handle payload는 union wrapper에 수명이 묶인 borrowed `*TRef`다. union 자체를 함수 인자나
반환값으로 직접 전달하면 `ZIGO006`; pointer로 노출해야 한다.

함수 항목의 주요 필드는 다음과 같다.

| 필드 | 역할 |
|---|---|
| `path` | 어떤 선언인지. `root.<name>` 또는 `<Type>.<name>` |
| `name` | 공개 함수 이름을 바꾼다. 생략하면 경로의 마지막 요소 |
| `params` | 파라미터 이름 목록 |
| `param_meta` | 파라미터별 `semantic`과 `retention` 계약 |
| `semantic` | 반환값 의미. 예: `.utf8_string` |
| `returns` | 반환 포인터의 소유권 계약 |

파라미터 이름 우선순위는 명시적인 `params`, 대상 소스 AST, `p0` 형식 fallback 순이다.
`param_meta`를 사용할 때는 해당 이름을 reflection 단계에서 식별할 수 있도록 같은 항목에
`params`도 적는다. `source_root`를 설정하면 다른 디렉터리 구조에서도 정확한 대상 소스에서
이름과 문서를 읽는다.

```zig
.{
    .path = "Context.create",
    .params = .{ "name", "callback", "userdata" },
    .param_meta = .{
        .name = .{ .semantic = .utf8_string },
        .callback = .{ .retention = .retained },
    },
}
```

## 타입의 종류와 접근 전략

`repr`은 **타입이 무엇인지**만 말한다.

| 값 | 뜻 |
|---|---|
| `.@"opaque"` | 포인터 handle |
| `.value` | `extern struct` 값 미러 |
| `.tagged_union` | tagged union handle |

`access`는 **Go가 그 내용을 어떻게 읽는지**를 말하며, 기본값은 `.projection`이다.

| 값 | 뜻 |
|---|---|
| `.projection` | variant마다 tag를 확인하는 접근자 |
| `.snapshot` | tag와 스칼라 payload를 한 번의 호출로 담는 스냅샷 구조체 (projection도 그대로 남는다) |

두 축을 나눠 두었으므로 접근 전략이 늘어도 `repr` 이름이 곱해지지 않는다. 예전
`.tagged_union_value`는 "tagged union인데 스냅샷"을 한 이름에 섞은 것이었고, 전략이 하나
더 생길 때마다 새 `repr` 이름이 필요했다.

## 마이그레이션: 선언을 지칭하는 방법

| 예전 | 지금 |
|---|---|
| `.{ .name = "add", .@"fn" = mylib.add }` | `.{ .path = "root.add" }` |
| `.{ .name = "process", .@"fn" = mylib.Context.process }` | `.{ .path = "Context.process" }` |
| `.{ .name = "put", .@"fn" = mylib.Context.set }` | `.{ .path = "Context.set", .name = "put" }` |
| `.overrides = .{ .{ .path = "Context.create", ... } }` | `.functions = .{ .{ .path = "Context.create", ... } }` |
| `.specializations = .{ .{ .name = "FloatBuffer", .type = T } }` | `.types = .{ .{ .name = "FloatBuffer", .type = T, .repr = .@"opaque" } }` |
| (`.root` 는 `discover` 모드에서만 필요) | `.root` 는 항상 필요하다 |
| `.{ .type = T, .repr = .tagged_union_value }` | `.{ .type = T, .repr = .tagged_union, .access = .snapshot }` |

semantic IR도 같은 축을 따른다. `union_repr: "value_snapshot"` 은 `access: "snapshot"` 이
되었다. 생성되는 C 심볼과 Go API는 바뀌지 않는다.

`.@"fn"`은 더 이상 받지 않는다. 경로가 함수 값을 대신하며, `.root`와 `types`에서
컨테이너를 찾아 해석한다. 경로가 공개 함수를 가리키지 않으면 컴파일 오류다.
`.name`은 이제 주소가 아니라 이름 바꾸기 전용이다.

## 생성 파일

기본 구성에서 관리되는 주요 파일은 다음과 같다.

```text
go/go.mod
go/internal/raw/raw_gen.go
go/<package>/<package>_gen.go
go/<package>/<package>_type_gen.go
go/<package>/<package>_errors_gen.go
go/<package>/<package>_helpers_gen.go
zigo/semantic.json
zigo/errors.lock.json
zig-out/include/zigo_<name>.h
zig-out/lib/lib<name>_zigo.a
```

`.link = .purego`는 헤더를 `zig-out/include/zigo_<name>_purego.h`로, 라이브러리를
`zig-out/lib/lib<name>_zigo.dylib`(macOS) 또는 `.so`(Linux)로 설치한다. 이름이 겹치지
않으므로 두 백엔드를 한 `zig-out`에 함께 설치해도 서로를 덮어쓰지 않는다.

Go 소스와 `zigo/semantic.json`, `zigo/errors.lock.json`은 소스 관리에 포함한다.
`zig-out/`은 빌드 산출물이므로 커밋하지 않는다. public 패키지에서 위 네 생성 파일을
제외한 별도 `.go` 파일은 생성기가 덮어쓰지 않으므로 사용자 편의 API를 추가하는 데
사용할 수 있다. enum, callback, opaque handle/Ref와 타입 고유 메서드는
`<package>_type_gen.go`에 둔다. package 단위 error 타입, `Err*` 값과 code 변환은
`<package>_errors_gen.go`에 함께 유지한다. bool 변환과 callback handle 수명 관리 같은
비공개 runtime support는 `<package>_helpers_gen.go`에 둔다.

모든 exported 생성 선언에는 GoDoc을 붙인다. Zig source doc이 있으면 AST 보강 결과를
우선 사용하고, 문서가 없는 함수·메서드에는 bound Zig operation을 나타내는 기본 설명을
생성한다. Handle/Ref/Close, callback, enum과 tag, error sentinel, checked projection에는
ownership, lifetime과 실패 방식이 명시된다. internal raw package도 별도로 탐색하거나
디버깅할 때 문맥을 잃지 않도록 C ABI 심볼을 포함한 GoDoc을 생성한다.

콜백 파라미터는 public API에서 익명 `func(...) ...` 대신 생성된 정의 타입을 사용한다.
메서드와 namespace 함수는 기본적으로 `<Owner><ParameterRole>`(예:
`EventQueueObserver`)을 사용하고, 같은 owner에서 역할 이름이 겹치면
`<Owner><Function><ParameterRole>`로 구분한다. 자유 함수는
`<Function><ParameterRole>Callback` 형식을 사용한다. 기존 public 타입과 충돌하면
`Callback` 접미사를 추가한다.

각 콜백 타입에는 `<package>_helpers_gen.go`의 비공개 typed handle 생성기가 대응한다.
이 생성기는 정의 타입을 raw trampoline이 검사하는 익명 함수 타입으로 명시 변환한 뒤
`cgo.Handle`에 저장한다. `borrowed` 콜백의 handle은 호출이 끝나면 즉시 해제하고,
`retained` 콜백의 handle은 소유 객체의 멱등 `Close`에서 해제한다.

`errors.lock.json`은 append-only 상태다. zigo는 버전과 예약 음수 코드, 양수 코드의
연속성·유일성을 검사하고 기존 이름의 삭제·이름 변경·재배정을 거부한다. 새 코드 배정은
전체 상태를 준비한 뒤 반영되므로 실패한 생성이 lock 일부만 변경하지 않는다. 충돌을
피하려면 생성 결과와 lock 변경을 같은 커밋으로 반영한다.
