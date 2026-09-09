# 여러 기능을 조합한 Pipeline

상태 객체, retained 콜백, 열거형, 슬라이스, typed error와 제네릭 구체화를 하나의 라이브러리에서
조합하는 예제입니다.

## 전제 조건

저장소 전체를 받은 뒤 이 예제 디렉터리에서 실행합니다. Zig 0.16.0, Go 1.24 이상,
`gofmt`와 cgo용 C 컴파일러가 필요합니다. zlib 개발 라이브러리도 설치되어 있어야 합니다.
도구 버전과 플랫폼 조건은 [지원 범위](../../docs/reference/support-matrix.md)를 확인하세요.

## 실행

```sh
zig build go
(cd go && go test -count=1 ./...)
(cd go && go test -run '^$' -bench BenchmarkPipelineProcess -benchmem ./pipeline)
```

## 예상 결과

Go 테스트가 통과하고 `BenchmarkPipelineProcess`가 처리 비용을 출력합니다.
벤치마크 수치는 실행 환경에 따라 달라집니다.

## 핵심 파일

- [src/root.zig](src/root.zig) — `Pipeline`과 제네릭 batch 구현
- [src/bindings.zig](src/bindings.zig) — Context 기반 타입별 선언
- [빌드.zig](build.zig) — zlib 링크 입력과 생성 단계
- `go/pipeline` — 생성 API와 수명·동시성 테스트

## 동작과 주의사항

`Pipeline`은 복사한 UTF-8 이름과 retained 콜백을 소유합니다. `IntBatch`와 `FloatBatch`는
같은 제네릭 member 목록을 서로 다른 Zig 타입으로 구체화하며 `Batch` 인터페이스가 두 Context의
타입 reference를 사용합니다. `Close`와 수명 counter로 정리를 검증합니다.

## 관련 문서

[바인딩 작성](../../docs/authoring/README.md) ·
[객체와 수명](../../docs/authoring/objects-and-lifetimes.md) ·
[예제 선택](../../docs/examples.md)
