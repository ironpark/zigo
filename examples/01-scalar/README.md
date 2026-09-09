# Scalar와 네이티브 링크

단순 스칼라 함수에 C++ 정적 라이브러리의 전이 링크와 cgo 동적 링크를 더한 검증 예제입니다.
외부 네이티브 의존성가 없다면 [00-quick-start](../00-quick-start/README.md)가 더 좋은 출발점입니다.

## 전제 조건

저장소 전체를 받은 뒤 이 예제 디렉터리에서 실행합니다. Zig 0.16.0, Go 1.24 이상,
`gofmt`와 cgo용 C 컴파일러가 필요합니다. C++ 지원 코드는 Zig 빌드에 포함됩니다.
도구 버전과 플랫폼 조건은 [지원 범위](../../docs/reference/support-matrix.md)를 확인하세요.

## 실행

```sh
zig build go
(cd go && go test ./...)
(cd go && go test ./scalar -run '^$' -bench '^BenchmarkAddCgo$' -benchmem)
```

동적 링크 경로는 다음처럼 별도로 생성하고 실행합니다.

```sh
zig build go -Ddynamic
DYLD_LIBRARY_PATH="$PWD/zig-out/lib" sh -c 'cd go && go test ./...'
```

Linux에서는 `DYLD_LIBRARY_PATH` 대신 `LD_LIBRARY_PATH`를 사용합니다. 기본 정적 구성으로
돌아가려면 `zig build go`를 다시 실행하세요.

## 예상 결과

Go 테스트가 통과하고 벤치마크는 `BenchmarkAddCgo`의 호출 비용을 출력합니다.
시간과 메모리 수치는 실행 환경에 따라 달라집니다.

## 핵심 파일

- [src/root.zig](src/root.zig) — 공개 Zig API
- [src/bindings.zig](src/bindings.zig) — 스칼라 함수 선언
- [빌드.zig](build.zig) — C++ support 라이브러리와 backend 옵션
- `go/scalar` — raw와 공개 Go API를 함께 둔 패키지

## 동작과 주의사항

기본값은 cgo 정적 링크입니다. `-Ddynamic`은 같은 공개 Go API를 유지하면서 공유 라이브러리를
링크합니다. 이 예제의 C++ bridge는 전이 의존성 검사용이며 모든 바인딩에 필요한 설정은
아닙니다.

## 관련 문서

[설정과 백엔드](../../docs/build-and-ship/configuration-and-backends.md) ·
[패키징과 배포](../../docs/build-and-ship/packaging-and-distribution.md) ·
[예제 선택](../../docs/examples.md)
