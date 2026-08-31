# 예제

`examples/`의 각 디렉터리는 zigo를 `.path = "../.."` 의존성으로 참조하는 독립 프로젝트다.
번호가 커질수록 다루는 범위가 넓어지며, 01~04는 기능 하나씩을 보여주고 05·07·08은
애플리케이션 형태의 통합 예제다.

각 예제는 해당 디렉터리에서 다음으로 실행한다.

```sh
zig build go        # 바인딩 생성 + 네이티브 라이브러리 빌드
cd go && go test ./...
```

purego 패키지도 함께 배선한 예제(04·07·08)는 `zig build purego-go` 로 생성하고
`CGO_ENABLED=0` 로 테스트한다. 10-tagged-union은 `zig build -Dpurego go` 로 백엔드를 바꿔
생성한다. 자세한 절차는 [공유 라이브러리와 purego 백엔드](purego.md)를 참고한다.

| 예제 | 다루는 것 |
|---|---|
| [01-scalar](../examples/01-scalar) | 최소 수직 슬라이스. 자유 함수 `add(i32, i32) i32` 하나. 동위치 raw 패키지와 `-Ddynamic` 로 정적·동적 링크를 함께 확인한다 |
| [02-errors](../examples/02-errors) | 에러 유니온과 슬라이스. `errors.Is(err, ErrDivideByZero)`, `[]const f64` 합산, enum 왕복. raw 패키지를 `support/ffi` 로 옮긴 예 |
| [03-opaque](../examples/03-opaque) | opaque handle 수명주기. `NewContext`/`Close` 멱등성, 할당 카운터, `semantic = .utf8_string` 문자열 왕복 |
| [04-callback](../examples/04-callback) | retained Go 콜백과 generic 구체화(`FloatBuffer`, `IntBuffer`). 콜백 panic이 프로세스를 죽이지 않는지 확인한다. purego 패키지도 함께 생성한다 |
| [05-pipeline](../examples/05-pipeline) | 통합 파이프라인. opaque 상태 + enum + 슬라이스 + typed error + retained 콜백을 한 API에 모으고, `source_root` 로 AST 이름 보강을 켜며 zlib 링크를 cgo 지시자로 전파한다 |
| [06-camel-case](../examples/06-camel-case) | 이름 규칙. 바인딩 이름 `HTTPClient` 가 Go package `http_client`, C 심볼 `zg_*` 로 어떻게 정규화되는지 보여준다 |
| [07-event-queue](../examples/07-event-queue) | 상태를 가진 이벤트 큐. 용량 초과 정책 enum, retained observer 콜백, `auto_cleanup` 안전망, raw 패키지 `bridge/cgo` 배치. `Stats`·`Limits` 로 `extern struct` 를 Go 값처럼 주고받는다. cgo·purego 두 패키지를 동시에 배선한다 |
| [08-telemetry-hub](../examples/08-telemetry-hub) | 가장 넓은 API 표면. `discover = .public` + 경로 항목, enum 3종과 다수의 error set, 필터·통계·in-place 변환. purego 쪽은 `library_loading` 으로 자동 로딩과 비공개 로더를 시험한다 |
| [09-type-relations](../examples/09-type-relations) | 한 문서에서 opaque 타입 2종. `Accumulator.absorb` 가 borrowed `*const Counter` 를 받아 소유권과 타입 참조가 독립임을 보여준다 |
| [10-tagged-union](../examples/10-tagged-union) | union 표현 두 가지. `Value` 는 `.repr = .tagged_union` projection 으로 `TryTag`/`TryAs*` 와 panic 하는 편의 메서드 `Tag`/`As*` 를, `Signal` 은 `.access = .snapshot` 스냅샷으로 `Snapshot()` 한 번에 tag 와 payload 를 제공한다. `-Dpurego` 로 백엔드를 바꿔 생성한다 |

예제는 CI에서 매 커밋 빌드·테스트되므로 문서와 어긋나면 CI가 먼저 실패한다.
개별 예제의 상세 설명은 각 디렉터리의 `README.md`(05·07·08·09·10)에 있다.
