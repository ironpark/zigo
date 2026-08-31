# 예제 선택 가이드

모든 예제는 독립적으로 빌드되는 Zig/Go 프로젝트입니다. 처음이라면 `01-scalar`로 생성
흐름을 확인한 뒤, 필요한 기능이 들어 있는 예제로 이동하세요.

## 목적에 맞는 예제 찾기

| 필요한 기능 | 먼저 볼 예제 |
|---|---|
| 가장 작은 설정과 함수 호출 | [01-scalar](../examples/01-scalar) |
| Zig 오류를 Go `error`로 처리 | [02-errors](../examples/02-errors) |
| 객체 생성, 메서드, `Close` | [03-opaque](../examples/03-opaque) |
| Go 콜백 또는 generic 구체화 | [04-callback](../examples/04-callback) |
| 여러 기능을 조합한 라이브러리 | [05-pipeline](../examples/05-pipeline) |
| 실제 애플리케이션 형태의 수명 관리 | [07-event-queue](../examples/07-event-queue) |
| 큰 공개 API 자동 발견 | [08-telemetry-hub](../examples/08-telemetry-hub) |
| 여러 opaque 타입 사이의 참조 | [09-type-relations](../examples/09-type-relations) |
| tagged union | [10-tagged-union](../examples/10-tagged-union) |

## 실행 방법

대부분의 예제는 같은 명령으로 검증할 수 있습니다.

```bash
cd examples/01-scalar
zig build test
zig build go-check
zig build go
(cd go && go test ./...)
```

`go-check`는 커밋된 생성물이 최신인지 확인하고, `go`는 생성물을 실제로 갱신합니다. 예제가
`abi_base`를 설정하므로 저장소 체크아웃 안에서는 `zig build abi-check`도 실행할 수 있습니다.

purego를 포함한 `04-callback`, `07-event-queue`, `08-telemetry-hub`는 별도 Go 모듈을 만듭니다.

```bash
zig build purego-go purego-go-verify
(cd go-purego && CGO_ENABLED=0 go test ./...)
```

`10-tagged-union`은 `-Dpurego` 옵션으로 같은 생성 경로의 백엔드를 바꿉니다. 세부적인 공유
라이브러리 로드 전제는 [purego 가이드](purego.md)를 참고하세요.

## 전체 예제

| 예제 | 보여 주는 내용 |
|---|---|
| [01-scalar](../examples/01-scalar) | 자유 함수 `add(i32, i32) i32`, 동위치 raw 패키지, `-Ddynamic` cgo 동적 링크 |
| [02-errors](../examples/02-errors) | 에러 유니온, `errors.Is`, 슬라이스, enum, `support/ffi` raw 패키지 |
| [03-opaque](../examples/03-opaque) | opaque handle, `NewContext`/`Close`, 문자열 의미와 할당 수명 |
| [04-callback](../examples/04-callback) | retained Go 콜백, 콜백 panic 경계, generic 타입 구체화, purego |
| [05-pipeline](../examples/05-pipeline) | opaque 상태, enum, 슬라이스, typed error, retained 콜백, AST 이름 보강, system library 링크 전파 |
| [06-camel-case](../examples/06-camel-case) | Zig·Go·C 사이의 package, 식별자와 심볼 이름 정규화 |
| [07-event-queue](../examples/07-event-queue) | 이벤트 큐 수명주기, observer 콜백, `auto_cleanup`, extern struct 값, cgo·purego 병행 |
| [08-telemetry-hub](../examples/08-telemetry-hub) | 51개 함수 자동 발견, 여러 enum/error set, purego 자동 로딩과 비공개 로더 |
| [09-type-relations](../examples/09-type-relations) | 한 바인딩 문서의 opaque 타입 2종과 borrowed 타입 간 참조 |
| [10-tagged-union](../examples/10-tagged-union) | projection 방식의 `Tag`/`As*`와 값 snapshot 방식의 `Snapshot()` |

예제를 복사해 시작하기보다, 각 예제의 `build.zig`와 `src/bindings.zig`에서 필요한 부분만
현재 프로젝트로 옮기는 편이 package path와 ABI 정책을 명확하게 유지하기 쉽습니다.
