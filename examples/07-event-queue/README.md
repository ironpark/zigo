# 상태를 가진 이벤트 큐

용량 제한이 있는 Zig event queue를 Go에 노출해 객체 수명, 값 type, buffer와 여러 public
package를 함께 확인하는 통합 예제입니다.

## 실행

```sh
zig build test go-check abi-check
zig build go
(cd go && go test -count=1 ./...)

zig build purego-go purego-go-verify
(cd go-purego && CGO_ENABLED=0 go test -count=1 ./...)
```

## 핵심 파일

- [src/root.zig](src/root.zig) — queue, stream과 값 type 구현
- [src/bindings.zig](src/bindings.zig) — type별 Context와 수명 계약
- [build.zig](build.zig) — 여러 package와 raw 경로 설정
- `go/bridge/cgo/cheader` — 생성 header와 Go layout 비교
- `go/event_queue`, `go/event_queue/types` — package 간 type 참조

## 생성되는 동작

- `EventQueue`, retained observer와 명시적 `Close`
- `Stats`, `Limits` 같은 extern struct의 값 전달
- struct slice, NUL 종료 문자열, 문자열 slice와 caller-owned buffer
- member가 아닌 constructor·destructor와 하위 package 간 참조

`EventQueue`는 thread-safe하지 않습니다. 같은 queue를 여러 goroutine에서 사용한다면 호출자가
동기화해야 합니다. `runtime.AddCleanup`은 누락된 정리의 안전망이며 `Close`를 대신하지 않습니다.

## 다음 문서

[객체와 수명](../../docs/authoring/objects-and-lifetimes.md) ·
[값과 데이터](../../docs/authoring/values-and-data.md) · [예제 선택](../../docs/examples.md)
