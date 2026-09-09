# 중첩 결과를 Go 값으로 받기

문자열, 슬라이스와 중첩 포인터를 포함한 네이티브 결과를 한 버퍼로 받아 Go가 소유하는 값 tree로
decode하는 예제입니다.

## 전제 조건

저장소 전체를 받은 뒤 이 예제 디렉터리에서 실행합니다. Zig 0.16.0, Go 1.24 이상,
`gofmt`와 cgo용 C 컴파일러가 필요합니다.
purego 테스트도 Zig로 빌드한 공유 라이브러리를 사용합니다. 로드 설정은 이 예제에 포함되어 있습니다.
도구 버전과 플랫폼 조건은 [지원 범위](../../docs/reference/support-matrix.md)를 확인하세요.

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

## 예상 결과

`ExampleSnapshot`은 `materialized 42 true`와 `[alpha beta]`를,
`ExampleFill`은 `2 materialized`를 출력합니다.

## 핵심 파일

- [src/root.zig](src/root.zig) — 중첩 결과와 legacy 접근자 구현
- [src/bindings.zig](src/bindings.zig) — `.materialized()`와 해제 계약
- [Go 사용 예제](go/materialized/example_test.go) — `Snapshot`과 `Fill`
- `go/materialized` — batch, 버퍼 재사용과 수명 테스트

## 동작과 주의사항

`Snapshot`과 `ProbeMany`의 결과는 Go 소유 값이므로 `Close`할 필요가 없습니다. 네이티브 직렬화
버퍼는 생성 런타임이 해제합니다. `Fill`은 호출자가 준 Go 슬라이스를 재사용하지만 중첩 값의
할당까지 없애는 zero-할당 API는 아닙니다. 반대로 `LegacyProbe` 핸들은 명시적으로
닫아야 합니다. benchmark는 서로 읽는 필드 수가 다르므로 보편적인 배속으로 해석하지 마세요.

## 관련 문서

[값과 데이터](../../docs/authoring/values-and-data.md) ·
[Materialized 형식](../../docs/internals/materialized-format.md) ·
[예제 선택](../../docs/examples.md)
