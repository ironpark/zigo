# 객체 생성·사용·Close

상태를 가진 Zig 객체를 Go handle로 사용하며 생성자, method, optional 결과와 수명 종료를
확인하는 예제입니다.

## 실행

```sh
zig build go
(cd go && go test -run '^Example' -v ./...)
(cd go && go test ./...)

zig build purego-go purego-go-verify
(cd go-purego && CGO_ENABLED=0 go test ./...)
```

예제 출력은 `3`, `0 false`입니다. 값이 0인 경우와 결과가 없는 경우를 구분합니다.

## 핵심 파일

- [src/root.zig](src/root.zig) — 상태 객체 구현
- [src/bindings.zig](src/bindings.zig) — opaque type, constructor와 destructor
- [Go 사용 예제](go/opaque/example_test.go) — 생성, 호출과 `defer Close`
- `go/generated_test.go` — borrowed view, handle 인자와 문자열
- `go/poison_test.go` — native panic 뒤 handle 재사용 거부

## 생성되는 동작

소유한 handle은 명시적으로 `Close`해야 합니다. GC cleanup은 안전망일 뿐 실행 시점을
보장하지 않습니다. 객체의 동시 호출 안전성은 원래 Zig 구현에 달려 있습니다. 이 예제는
직접 `api.in()`과 `Entry.members()`를 조합하며 Context 방식은
[05-pipeline](../05-pipeline/src/bindings.zig)에서 비교할 수 있습니다.

## 다음 문서

[객체와 수명](../../docs/authoring/objects-and-lifetimes.md) ·
[지원 범위](../../docs/reference/support-matrix.md) · [예제 선택](../../docs/examples.md)
