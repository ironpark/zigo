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
| `link_mode` | 아니요 | `.static` 또는 `.dynamic`. 기본값 `.static` |
| `backend` | 아니요 | `.cgo` 또는 `.purego`. 기본값 `.cgo`. `.purego`는 `.link_mode = .dynamic` 필요 |
| `cgo_flags` | 아니요 | 자동 계산 대신 사용할 CFLAGS와 LDFLAGS |
| `abi_base` | 아니요 | ABI·바인딩 계약 비교에 사용할 Git ref. 생략하면 검사 비활성화 |
| `raw_package` | 아니요 | raw Go 코드 위치. 기본값 `.internal` |
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
`go-doctor`는 현재 target이 host에서 실행 가능한지, Go 최소 버전, gofmt를 검사하고, 선택한
백엔드에 따라 나머지 전제를 확인한다. `.cgo`에서는 `CGO_ENABLED`와 Go가 설정한 C
컴파일러를, `.purego`에서는 호스트 플랫폼 지원 여부, `go.mod`의 purego 요구사항, 설치된
공유 라이브러리의 존재와 실제 로드 가능 여부를 검사한다. gofmt 부재는 경고지만 cross
target, 낮은 Go 버전, 비활성 cgo, 실행할 수 없는 C 컴파일러, 지원하지 않는 purego
플랫폼, 없는 purego 요구사항과 로드할 수 없는 공유 라이브러리는 실패다. 자세한 내용은
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

## raw Go 패키지 위치

기본값은 `go/internal/raw/raw_gen.go`다.

```zig
.raw_package = .internal,
```

다른 상대 경로를 지정하면 마지막 경로 요소를 정규화해 Go 패키지 이름으로 사용한다.

```zig
// go/support/ffi/ffi_gen.go
.raw_package = .{ .path = "support/ffi" },
```

public 패키지와 같은 디렉터리에 둘 수도 있다.

```zig
// go/mylib/mylib_cgo_gen.go
.raw_package = .colocated,
```

사용자 경로는 `go_dir` 기준의 상대 경로여야 한다. 빈 요소, `.`과 `..`, 절대 경로와
역슬래시는 허용하지 않는다. 각 요소에는 ASCII 영문자, 숫자, `_`, `-`, `.`만 쓸 수
있다. 경로나 모드를 바꾼 뒤에는 이전 위치의 `_gen.go` 파일을 직접 삭제해 중복 선언을
방지한다.

## 생성 후 Go 포맷

빌드 환경의 `PATH`에서 `gofmt` 실행 파일을 찾을 수 있으면 raw/cgo, public API, public
error와 private helper 생성 파일을 각각 포맷한 뒤 `go_dir`에 기록한다. `go-check`도 같은
포맷 결과를 비교한다. `gofmt`가 없으면 생성은 실패하지 않고 generator 결과를 그대로
사용한다. generator 원문도 지원하는 생성 형태에 대해서는 gofmt-stable하게 유지하므로
`gofmt` 유무가 `go-check` 결과를 바꾸지 않는다. 사용자 소유 Go 파일은 포맷하지 않는다.

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

명시 모드는 다음 세 그룹을 사용한다.

| 그룹 | 역할 |
|---|---|
| `types` | opaque, tagged-union handle 또는 명시적 representation으로 노출할 타입 |
| `specializations` | comptime generic을 구체화한 named type |
| `functions` | 생성할 함수와 메서드 |

큰 공개 API는 opt-in 자동 발견 모드를 사용할 수 있다.

```zig
pub const bindings = zigo.define(.{
    .root = mylib,
    .discover = .public,
    .types = .{
        .{ .type = mylib.Context, .repr = .@"opaque" },
    },
    .overrides = .{
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

`.discover = .public`은 `types`와 `specializations`에 등록된 컨테이너의 공개 함수부터
발견하고, 이어서 `root` 모듈의 공개 함수를 발견한다. 타입 메서드는
`Context.process`, 루트 함수는 `root.version` 형식의 안정적인 경로로 식별한다.
`overrides`는 이름 변경과 reflection만으로 알 수 없는 의미·소유권 메타데이터를 지정하고,
`exclude`는 바인딩하지 않을 공개 함수를 지정한다. 존재하지 않는 경로, 중복 경로,
override와 exclude의 충돌은 컴파일 오류다.

자동 발견은 명시적으로 선택해야 한다. 이 모드에서는 새 `pub fn`이 C/Go API에도
추가되므로 생성물 stale 검사와, 독립 배포 계약이 있다면 `abi-check`를 함께 사용한다.
세밀하게 선택해야 하는 API와 generic 함수의 구체화는 기존 `functions` 모드를 사용한다.

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

지원 payload는 `void`, bool, 정수, float, enum, 등록된 handle pointer, 숫자 slice다.
숫자 slice는 Zig 메모리 view를 public Go API에 그대로 노출하지 않고 호출마다 복사한다.
handle payload는 union wrapper에 수명이 묶인 borrowed `*TRef`다. union 자체를 함수 인자나
반환값으로 직접 전달하면 `ZIGO006`; pointer로 노출해야 한다.

함수 항목의 주요 필드는 다음과 같다.

| 필드 | 역할 |
|---|---|
| `name` | 공개 함수 이름 |
| `@"fn"` | reflection할 Zig 함수 값 |
| `params` | 파라미터 이름 목록 |
| `param_meta` | 파라미터별 `semantic`과 `retention` 계약 |
| `semantic` | 반환값 의미. 예: `.utf8_string` |
| `returns` | 반환 포인터의 소유권 계약 |

파라미터 이름 우선순위는 명시적인 `params`, 대상 소스 AST, `p0` 형식 fallback 순이다.
`param_meta`를 사용할 때는 해당 이름을 reflection 단계에서 식별할 수 있도록 같은 override에
`params`도 적는다. `source_root`를 설정하면 다른 디렉터리 구조에서도 정확한 대상 소스에서
이름과 문서를 읽는다.

```zig
.{
    .name = "create",
    .@"fn" = mylib.Context.create,
    .params = .{ "name", "callback", "userdata" },
    .param_meta = .{
        .name = .{ .semantic = .utf8_string },
        .callback = .{ .retention = .retained },
    },
}
```

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
