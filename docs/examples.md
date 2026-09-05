# 예제 선택 가이드

모든 예제는 독립적으로 빌드되는 Zig/Go 프로젝트입니다. 처음이라면
[00-quick-start](../examples/00-quick-start/README.md)에서 생성·import·실행을 확인하세요.
각 디렉터리의 README는 실행 방법과 먼저 읽을 사용자 코드를 안내합니다.

## 추천 학습 순서

1. **첫 호출**: `00-quick-start`의 `go run ./cmd/demo`
2. **오류와 객체**: `02-errors`, `03-opaque`의 `example_test.go`
3. **필요한 데이터 경로 선택**: 콜백은 `04-callback`, I/O는 `11-io-streams`, 중첩 결과는 `12-materialized`
4. **큰 API에 적용**: `05-pipeline`, `07-event-queue`, `08-telemetry-hub`

`01-scalar`는 C++ 의존성 링크, `06-camel-case`는 이름 정규화의 회귀 검증용입니다.
입문 단계에서는 건너뛰어도 됩니다. 기존 예제는 각자의 회귀 검증 범위가 있어 유지합니다.

## 목적에 맞는 예제 찾기

| 필요한 기능 | 먼저 볼 예제 |
|---|---|
| 가장 작은 설정과 실행 가능한 Go 프로그램 | [00-quick-start](../examples/00-quick-start/README.md) |
| C++ 의존성 전파·cgo 정적/동적 링크 | [01-scalar](../examples/01-scalar/README.md) |
| Zig 오류를 Go `error`로 처리 | [02-errors](../examples/02-errors) |
| 객체 생성, 메서드, `Close` | [03-opaque](../examples/03-opaque) |
| Go 콜백 또는 generic 구체화 | [04-callback](../examples/04-callback) |
| 여러 기능을 조합한 라이브러리 | [05-pipeline](../examples/05-pipeline) |
| 실제 애플리케이션 형태의 수명 관리 | [07-event-queue](../examples/07-event-queue) |
| 타입 밖에 선언된 생성자·소멸자 짝짓기 | [07-event-queue](../examples/07-event-queue) |
| 큰 공개 API 자동 발견 | [08-telemetry-hub](../examples/08-telemetry-hub) |
| 여러 opaque 타입 사이의 참조 | [09-type-relations](../examples/09-type-relations) |
| tagged union | [10-tagged-union](../examples/10-tagged-union) |
| Go `io.Writer`/`io.Reader`로 스트리밍, stdin/stdout CLI | [11-io-streams](../examples/11-io-streams/README.md) |
| 중첩 결과 트리를 한 버퍼로 반환 | [12-materialized](../examples/12-materialized) |

## 실행 방법

대부분의 예제는 같은 명령으로 검증할 수 있습니다.

```bash
cd examples/00-quick-start
zig build test
zig build go-check
zig build go
(cd go && go test ./...)
```

`00`, `02`, `03`, `04`, `11`, `12`에는 외부 패키지에서 공개 API만 사용하는
`example_test.go`가 있습니다. `(cd go && go test -run '^Example' -v ./...)`로 사용 예제만
실행할 수 있으며, `// Output:`과 실제 출력이 다르면 테스트가 실패합니다.
기존의 큰 테스트 파일은 경계 조건과 회귀 검증용이므로 사용 예제부터 읽으세요.

`go-check`는 커밋된 생성물이 최신인지 확인하고, `go`는 생성물을 실제로 갱신합니다. 예제가
`abi_base`를 설정하므로 저장소 체크아웃 안에서는 `zig build abi-check`도 실행할 수 있습니다.

purego를 포함한 `03-opaque`, `04-callback`, `07-event-queue`, `08-telemetry-hub`, `11-io-streams`,
`12-materialized`는 별도 Go
모듈을 만듭니다.

```bash
zig build purego-go purego-go-verify
(cd go-purego && CGO_ENABLED=0 go test ./...)
```

`10-tagged-union`은 `-Dpurego` 옵션을 사용하며, 생성 경로도 `go`에서 `go-purego`로 바뀝니다.

```bash
# 저장소 루트에서 실행
(cd examples/10-tagged-union && zig build go go-verify -Dpurego)
(cd examples/10-tagged-union/go-purego && CGO_ENABLED=0 go test ./...)
```

공유 라이브러리 로드 전제는 [purego 가이드](purego.md)를 참고하세요.

## 전체 예제

| 예제 | 보여 주는 내용 |
|---|---|
| [00-quick-start](../examples/00-quick-start/README.md) | 외부 native 의존성이 없는 최소 설정, Go CLI와 실행 가능한 사용 예제 |
| [01-scalar](../examples/01-scalar) | scalar, C++ 전이 링크, 동위치 raw 패키지, `-Ddynamic` cgo 동적 링크 |
| [02-errors](../examples/02-errors) | 에러 유니온, `errors.Is`, 슬라이스, enum, `support/ffi` raw 패키지 |
| [03-opaque](../examples/03-opaque) | opaque handle, `NewContext`/`Close`, 문자열 의미와 할당 수명 |
| [04-callback](../examples/04-callback) | 모듈 루트 공개 패키지와 colocated cgo raw, retained Go 콜백, 콜백 panic 경계, generic 타입 구체화, purego |
| [05-pipeline](../examples/05-pipeline) | opaque 상태, enum, 슬라이스, typed error, retained 콜백, AST 이름 보강, system library 링크 전파 |
| [06-camel-case](../examples/06-camel-case) | Zig·Go·C 사이의 package, 식별자와 심볼 이름 정규화 |
| [07-event-queue](../examples/07-event-queue) | 이벤트 큐 수명주기, observer 콜백, 강제 GC로 확인하는 cleanup 안전망, extern struct 값, cgo·purego 병행 |
| [08-telemetry-hub](../examples/08-telemetry-hub) | 큰 API 자동 발견, 여러 enum/error set, purego 자동 로딩과 비공개 로더 |
| [09-type-relations](../examples/09-type-relations) | 한 바인딩 문서의 opaque 타입 2종과 borrowed 타입 간 참조 |
| [10-tagged-union](../examples/10-tagged-union) | projection 방식의 `Tag`/`As*`, 값 snapshot 방식의 `Snapshot()`, sealed variant 방식의 `Variant()` |
| [11-io-streams](../examples/11-io-streams) | `*std.Io.Writer`/`*std.Io.Reader` 파라미터가 `io.Writer`/`io.Reader`로, 버퍼 크기와 경계 횡단 횟수, writer error·panic·reader EOF 경로, cgo·purego 병행 |
| [12-materialized](../examples/12-materialized) | 중첩 pointer·slice·string 결과 트리, batch와 out buffer, accessor handle 대비 materialized decode benchmark, cgo·purego 병행 |

예제를 복사해 시작하기보다, 각 예제의 `build.zig`와 `src/bindings.zig`에서 필요한 부분만
현재 프로젝트로 옮기는 편이 package path와 ABI 정책을 명확하게 유지하기 쉽습니다.

예제의 `build.zig.zon`은 저장소 루트의 zigo를 상대 경로로 참조하고 `abi_base = "HEAD"`는
커밋된 메타데이터를 비교합니다. 외부 프로젝트에서는 [시작 가이드](getting-started.md)처럼
의존성을 설치하고, 자신의 모듈 경로와 ABI 기준을 선택하세요. 디렉터리를 단독 복사한 뒤
동일한 명령이 바로 동작한다고 가정하지 마세요.
