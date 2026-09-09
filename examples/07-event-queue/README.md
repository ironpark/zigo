# 상태를 가진 이벤트 큐

용량 제한이 있는 Zig event queue를 Go에 노출해 객체 수명, 값 타입, 버퍼와 여러 공개
패키지를 함께 확인하는 통합 예제입니다.

## 전제 조건

저장소 전체를 받은 뒤 이 예제 디렉터리에서 실행합니다. Zig 0.16.0, Go 1.24 이상,
`gofmt`와 cgo용 C 컴파일러가 필요합니다.
purego 테스트도 Zig로 빌드한 공유 라이브러리를 사용합니다. 로드 설정은 이 예제에 포함되어 있습니다.
도구 버전과 플랫폼 조건은 [지원 범위](../../docs/reference/support-matrix.md)를 확인하세요.

## 실행

```sh
zig build go
(cd go && go test -count=1 ./...)

zig build purego-go purego-go-verify
(cd go-purego && CGO_ENABLED=0 go test -count=1 ./...)
```

## 예상 결과

cgo·purego 테스트가 통과합니다. 수명, 버퍼와 하위 패키지 관계는 테스트의 단언으로 검증하며
별도의 고정된 프로그램 출력은 없습니다.

## 핵심 파일

- [src/root.zig](src/root.zig) — queue, 스트림과 값 타입 구현
- [src/bindings.zig](src/bindings.zig) — 타입별 Context와 수명 계약
- [빌드.zig](build.zig) — 여러 패키지와 raw 경로 설정
- `go/bridge/cgo/cheader` — 생성 헤더와 Go 배치 비교
- `go/event_queue`, `go/event_queue/types` — 패키지 간 타입 참조

## 동작과 주의사항

- `EventQueue`, retained observer와 명시적 `Close`
- `Stats`, `Limits` 같은 extern 구조체의 값 전달
- 구조체 슬라이스, NUL 종료 문자열, 문자열 슬라이스와 caller-owned 버퍼
- member가 아닌 생성자·소멸자와 하위 패키지 간 참조

`EventQueue`는 동시 호출에 안전하지 않습니다. 같은 queue를 여러 goroutine에서 사용한다면 호출자가
동기화해야 합니다. `runtime.AddCleanup`은 누락된 정리의 안전망이며 `Close`를 대신하지 않습니다.

## 관련 문서

[객체와 수명](../../docs/authoring/objects-and-lifetimes.md) ·
[값과 데이터](../../docs/authoring/values-and-data.md) · [예제 선택](../../docs/examples.md)
