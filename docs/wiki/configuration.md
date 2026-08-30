# 설정과 생성물

## `addGoBindings` 옵션

| 옵션 | 필수 | 설명 |
|---|---:|---|
| `name` | 예 | 생성할 라이브러리와 Go 패키지의 기준 이름 |
| `module` | 예 | reflection할 `*std.Build.Module` |
| `bindings` | 예 | `zigo.define` 선언 파일 |
| `go_dir` | 예 | 생성된 Go 모듈을 둘 소스 경로 |
| `go_module` | 예 | 생성될 `go.mod`와 import에 사용할 모듈 경로 |
| `target` | 예 | 라이브러리 타깃 |
| `optimize` | 예 | 라이브러리 최적화 모드 |
| `prefix` | 아니요 | C 심볼 접두사. 기본값 `zg` |
| `link_mode` | 아니요 | `.static` 또는 `.dynamic`. 기본값 `.static` |
| `cgo_flags` | 아니요 | 자동 계산 대신 사용할 CFLAGS와 LDFLAGS |
| `abi_base` | 아니요 | ABI·바인딩 계약 비교에 사용할 Git ref. 생략하면 검사 비활성화 |
| `raw_package` | 아니요 | raw Go 코드 위치. 기본값 `.internal` |

`abi_base`는 호환성 정책이 필요한 프로젝트만 지정한다. 생략하면 zigo는 Git을 호출하지
않고 `GoBindings.abi_check`를 `null`로 반환한다. 활성화한 경우 지정한 ref에 커밋된
`zigo/semantic.json`이 비교 기준이다.

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

빌드 환경의 `PATH`에서 `gofmt` 실행 파일을 찾을 수 있으면 raw/cgo, public API와 public
error 생성 파일을 각각 포맷한 뒤 `go_dir`에 기록한다. `go-check`도 같은 포맷 결과를
비교한다. `gofmt`가 없으면 생성은 실패하지 않고 generator 결과를 그대로 사용한다.
사용자 소유 Go 파일은 포맷하지 않는다.

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

최상위 선언은 다음 세 그룹을 사용한다.

| 그룹 | 역할 |
|---|---|
| `types` | opaque 또는 명시적 representation으로 노출할 타입 |
| `specializations` | comptime generic을 구체화한 named type |
| `functions` | 생성할 함수와 메서드 |

함수 항목의 주요 필드는 다음과 같다.

| 필드 | 역할 |
|---|---|
| `name` | 공개 함수 이름 |
| `@"fn"` | reflection할 Zig 함수 값 |
| `params` | 파라미터 이름 목록 |
| `param_meta` | 파라미터별 `semantic`과 `retention` 계약 |
| `semantic` | 반환값 의미. 예: `.utf8_string` |
| `returns` | 반환 포인터의 소유권 계약 |

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
go/<package>/<package>_errors_gen.go
zigo/semantic.json
zigo/errors.lock.json
zig-out/include/zigo_<name>.h
zig-out/lib/lib<name>_zigo.a
```

Go 소스와 `zigo/semantic.json`, `zigo/errors.lock.json`은 소스 관리에 포함한다.
`zig-out/`은 빌드 산출물이므로 커밋하지 않는다. public 패키지에서 위 두 생성 파일을
제외한 별도 `.go` 파일은 생성기가 덮어쓰지 않으므로 사용자 편의 API를 추가하는 데
사용할 수 있다. package 단위 error 타입, `Err*` 값과 code 변환은
`<package>_errors_gen.go`에 함께 유지한다.

`errors.lock.json`은 append-only 상태다. zigo는 버전과 예약 음수 코드, 양수 코드의
연속성·유일성을 검사하고 기존 이름의 삭제·이름 변경·재배정을 거부한다. 새 코드 배정은
전체 상태를 준비한 뒤 반영되므로 실패한 생성이 lock 일부만 변경하지 않는다. 충돌을
피하려면 생성 결과와 lock 변경을 같은 커밋으로 반영한다.
