# Scalar와 native 링크

단순 scalar 함수에 C++ 정적 library의 전이 link와 cgo 동적 link를 더한 검증 예제입니다.
외부 native dependency가 없다면 [00-quick-start](../00-quick-start/README.md)가 더 좋은 출발점입니다.

## 실행

```sh
zig build test go-check
zig build go
(cd go && go test ./...)
(cd go && go test ./scalar -run '^$' -bench '^BenchmarkAddCgo$' -benchmem)
```

동적 link 경로는 다음처럼 별도로 생성하고 실행합니다.

```sh
zig build go -Ddynamic
DYLD_LIBRARY_PATH="$PWD/zig-out/lib" sh -c 'cd go && go test ./...'
```

Linux에서는 `DYLD_LIBRARY_PATH` 대신 `LD_LIBRARY_PATH`를 사용합니다. 기본 정적 구성으로
돌아가려면 `zig build go`를 다시 실행하세요.

## 핵심 파일

- [src/root.zig](src/root.zig) — 공개 Zig API
- [src/bindings.zig](src/bindings.zig) — scalar 함수 선언
- [build.zig](build.zig) — C++ support library와 backend option
- `go/scalar` — raw와 공개 Go API를 함께 둔 package

## 생성되는 동작

기본값은 cgo 정적 link입니다. `-Ddynamic`은 같은 공개 Go API를 유지하면서 공유 library를
link합니다. 이 예제의 C++ bridge는 전이 dependency 검사용이며 모든 binding에 필요한 설정은
아닙니다.

## 다음 문서

[설정과 백엔드](../../docs/build-and-ship/configuration-and-backends.md) ·
[패키징과 배포](../../docs/build-and-ship/packaging-and-distribution.md) ·
[예제 선택](../../docs/examples.md)
