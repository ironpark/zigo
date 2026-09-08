# 예제

`examples/`의 각 디렉터리는 독립적으로 빌드되는 Zig·Go 프로젝트입니다. 처음에는
[00-quick-start](../examples/00-quick-start/README.md)를 실행하고, 이후 필요한 기능이 있는
예제만 골라 읽으세요.

## 기본 실행

대부분의 cgo 예제는 다음 순서로 검증합니다.

```bash
cd examples/00-quick-start
zig build test go-check
zig build go
(cd go && go test ./...)
```

`go-check`는 커밋된 생성물이 최신인지 검사하고 `go`는 실제로 갱신합니다. 각 README에는
해당 예제에 추가로 필요한 명령이 적혀 있습니다.

## 목적별 선택

| 목적 | 예제 |
|---|---|
| 가장 작은 생성과 Go 호출 | [00-quick-start](../examples/00-quick-start/README.md) |
| C++ 링크 입력과 cgo 동적 링크 | [01-scalar](../examples/01-scalar/README.md) |
| Zig error union을 Go `error`로 사용 | [02-errors](../examples/02-errors/README.md) |
| 객체 생성, 메서드와 `Close` | [03-opaque](../examples/03-opaque/README.md) |
| Go callback, panic 경계와 generic 타입 | [04-callback](../examples/04-callback/README.md) |
| 여러 타입과 callback을 조합 | [05-pipeline](../examples/05-pipeline/README.md) |
| Zig·C·Go 이름 변환 | [06-camel-case](../examples/06-camel-case/README.md) |
| 상태를 가진 애플리케이션과 수명 관리 | [07-event-queue](../examples/07-event-queue/README.md) |
| 큰 API 자동 발견 | [08-telemetry-hub](../examples/08-telemetry-hub/README.md) |
| 여러 opaque 타입 사이의 관계 | [09-type-relations](../examples/09-type-relations/README.md) |
| tagged union과 JSON plugin | [10-tagged-union](../examples/10-tagged-union/README.md) |
| `io.Reader`, `io.Writer`와 취소 | [11-io-streams](../examples/11-io-streams/README.md) |
| 중첩 결과를 한 Go 값으로 materialize | [12-materialized](../examples/12-materialized/README.md) |

## 추천 순서

1. `00-quick-start`에서 전체 생성 흐름을 확인합니다.
2. `02-errors`와 `03-opaque`에서 오류와 객체 수명을 익힙니다.
3. 데이터 흐름에 맞춰 `04-callback`, `11-io-streams` 또는 `12-materialized`를 선택합니다.
4. 큰 API를 설계할 때 `05-pipeline`, `07-event-queue`, `08-telemetry-hub`를 참고합니다.

`01-scalar`와 `06-camel-case`는 특정 링크·이름 문제를 확인하는 예제이므로 처음에는 건너뛰어도
됩니다.

## purego 예제

`03`, `04`, `07`, `08`, `11`, `12`는 별도 `go-purego` module을 생성합니다.

```bash
zig build purego-go purego-go-verify
(cd go-purego && CGO_ENABLED=0 go test ./...)
```

`10-tagged-union`은 같은 step에 `-Dpurego`를 전달합니다.

```bash
zig build go go-verify -Dpurego
(cd go-purego && CGO_ENABLED=0 go test ./...)
```

예제의 `build.zig.zon`은 저장소 루트의 zigo를 상대 경로로 참조합니다. 예제 디렉터리만
복사하면 의존성 경로가 깨지므로, 자신의 프로젝트에는 필요한 `build.zig`와
`src/bindings.zig` 부분만 옮기고 [시작 가이드](getting-started.md)처럼 zigo를 추가하세요.
