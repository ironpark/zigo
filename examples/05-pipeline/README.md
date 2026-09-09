# 여러 기능을 조합한 Pipeline

상태 객체, retained callback, enum, slice, typed error와 generic 구체화를 하나의 library에서
조합하는 예제입니다.

## 실행

```sh
zig build test go-check abi-check
zig build go
(cd go && go test -count=1 ./...)
(cd go && go test -run '^$' -bench BenchmarkPipelineProcess -benchmem ./pipeline)
```

## 핵심 파일

- [src/root.zig](src/root.zig) — `Pipeline`과 generic batch 구현
- [src/bindings.zig](src/bindings.zig) — Context 기반 type별 선언
- [build.zig](build.zig) — zlib link 입력과 생성 step
- `go/pipeline` — 생성 API와 수명·동시성 테스트

## 생성되는 동작

`Pipeline`은 복사한 UTF-8 이름과 retained callback을 소유합니다. `IntBatch`와 `FloatBatch`는
같은 generic member 목록을 서로 다른 Zig type으로 구체화하며 `Batch` interface가 두 Context의
type reference를 사용합니다. `Close`와 수명 counter로 정리를 검증합니다.

## 다음 문서

[바인딩 작성](../../docs/authoring/README.md) ·
[객체와 수명](../../docs/authoring/objects-and-lifetimes.md) ·
[예제 선택](../../docs/examples.md)
