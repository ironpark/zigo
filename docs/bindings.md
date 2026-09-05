# `bindings.zig` 선언

`bindings.zig`는 Zig API 중 무엇을 Go에 노출할지, 값과 객체를 어떻게 전달할지 정하는 파일입니다.
빌드 연결이 아직 없다면 [시작 가이드](getting-started.md)를 먼저 완료하세요.

## 선언하는 순서

1. `root`에 라이브러리 모듈을 지정합니다.
2. 객체와 값 타입을 `types`에 등록합니다.
3. 공개할 함수를 `functions`에 추가합니다.
4. 문자열 의미, 반환값 소유권, 콜백 수명처럼 타입만으로 알 수 없는 조건을 명시합니다.

## 기본 구조

```zig
const zigo = @import("zigo");
const mylib = @import("mylib");

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

| 그룹 | 역할 |
|---|---|
| `root` | 경로를 해석할 기준 module. 항상 필요 |
| `types` | opaque handle, extern struct 값, enum, tagged union, callback 등록 |
| `functions` | 노출할 함수와 추가 메타데이터 |

`root.<name>`은 module 자유 함수를, `<Type>.<name>`은 등록 타입의 함수를 가리킵니다. 경로가
공개 함수를 가리키지 않으면 compile error입니다. 함수 항목의 `.name`은 경로가 아니라 생성할
Go 이름만 바꿉니다.

중첩 namespace 경로와 이름 충돌의 해결 방법은
[함수 선택, 이름과 패키지](bindings-functions.md#경로와-이름)에 있습니다.

## 타입 등록 선택

`repr`은 타입의 ABI 표현을, `access`는 tagged union 내용을 Go에서 읽는 방법을 선택합니다.
enum 항목의 `exhaustive = false`는 Zig의 non-exhaustive enum을 그대로 공개하는 opt-in입니다.

| `repr` | 용도 |
|---|---|
| `.@"opaque"` | pointer handle과 수명주기 |
| `.value` | 적격한 `extern struct` 또는 정수-backed `packed struct`의 Go 값 mirror |
| `.tagged_union` | tagged union을 handle로 읽거나 지원하는 payload를 값으로 전달 |
| `.materialized` | 포인터를 포함한 결과 트리를 한 번의 caller-owned buffer로 복사 |
| `.enumeration` | enum에 Go 타입 이름을 부여. `.name` 선택 |
| `.callback` | `*const fn` alias에 Go 타입 이름을 부여. `.name` 필수 |

| `access` | 용도 |
|---|---|
| `.projection` | variant별 tag/payload accessor. 기본값 |
| `.snapshot` | tag와 scalar payload를 한 native 호출로 복사. projection도 유지 |

구체화한 generic 타입은 `.name`으로 이름을 지정합니다. `anytype` 함수는 구체 타입을 받는
Zig 래퍼를 작성해 등록하세요. 타입 등록의 상세 조건은 [값 타입과 결과 트리](bindings-types.md)에 있습니다.

## 필요한 기능 추가하기

| 하고 싶은 일 | 읽을 문서 |
|---|---|
| 함수 이름·파라미터·자동 발견·하위 패키지 설정 | [함수 선택, 이름과 패키지](bindings-functions.md) |
| 정수·enum·struct·atomic·중첩 결과 등록 | [값 타입과 결과 트리](bindings-types.md) |
| 생성자·소멸자·부모와 자식·borrowed 객체·인터페이스 선언 | [객체 수명과 Go 인터페이스](bindings-handles.md) |
| 문자열·반환 slice·재사용 버퍼·optional 전달 | [문자열, 슬라이스와 optional](bindings-buffers.md) |
| 콜백 등록·오류 처리·panic 전달 | [콜백과 Go 오류 처리](bindings-callbacks.md) |
| `io.Writer`·`io.Reader`·취소 연결 | [스트림과 취소](bindings-streams.md) |
| `Tag`·`As*`·`Variant`·snapshot 사용 | [Tagged union 읽기와 값 전달](bindings-unions.md) |

## 생성하고 확인하기

프로젝트 루트에서 실행합니다.

```bash
zig build go
zig build go-report
(cd go && go test ./...)
```

`go-report`에서 최종 Go 이름과 소유권·수명 결정을 확인하고, Go 테스트로 실제 호출을 검증하세요.
생성된 파일을 직접 수정하지 말고 `bindings.zig`의 선언을 바꾼 뒤 다시 생성합니다.
커밋과 CI 연결은 [생성물과 CI 관리](generated-code.md), 지원 여부는
[제한사항](limitations.md), `ZIGO...` 오류는 [진단 안내](diagnostics.md)를 참고하세요.
