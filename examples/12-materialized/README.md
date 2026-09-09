# 중첩 결과를 Go 값으로 받기

string, slice와 중첩 pointer를 포함한 native 결과를 한 buffer로 받아 Go가 소유하는 값 tree로
decode하는 예제입니다.

## 실행

```sh
zig build go
(cd go && go test -run '^Example' -v ./...)
(cd go && go test ./...)

zig build purego-go purego-go-verify
(cd go-purego && CGO_ENABLED=0 go test ./...)
```

성능 특성을 비교하려면 다음 benchmark를 사용합니다.

```sh
(cd go && go test -run '^$' -bench 'Benchmark(MaterializedDecode|AccessorHandles)$' -benchmem ./materialized)
```

## 핵심 파일

- [src/root.zig](src/root.zig) — 중첩 결과와 legacy accessor 구현
- [src/bindings.zig](src/bindings.zig) — `.materialized()`와 release 계약
- [Go 사용 예제](go/materialized/example_test.go) — `Snapshot`과 `Fill`
- `go/materialized` — batch, buffer 재사용과 수명 테스트

## 생성되는 동작

`Snapshot`과 `ProbeMany`의 결과는 Go 소유 값이므로 `Close`할 필요가 없습니다. native 직렬화
buffer는 생성 runtime이 release합니다. `Fill`은 호출자가 준 Go slice를 재사용하지만 중첩 값의
allocation까지 없애는 zero-allocation API는 아닙니다. 반대로 `LegacyProbe` handle은 명시적으로
닫아야 합니다. benchmark는 서로 읽는 field 수가 다르므로 보편적인 배속으로 해석하지 마세요.

## 다음 문서

[값과 데이터](../../docs/authoring/values-and-data.md) ·
[Materialized 형식](../../docs/internals/materialized-format.md) ·
[예제 선택](../../docs/examples.md)
