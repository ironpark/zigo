# Scalar와 native 링크 검증

단순 함수 호출에 C++ 정적 라이브러리의 전이 링크와 cgo 동적 링크 검증을 더한 예제입니다.
처음 zigo를 사용한다면 외부 의존성이 없는 [00-quick-start](../00-quick-start/README.md)를 먼저 보세요.

## 실행

이 디렉터리에서 실행합니다.

```sh
zig build test go-check
zig build go
(cd go && go test -v ./...)
(cd go && go test ./scalar -run '^$' -bench '^BenchmarkAddCgo$' -benchmem)
```

`src/root.zig`는 Zig API, `src/bindings.zig`는 노출 선언입니다.
`build.zig`의 C++ support·bridge 구성은 native 의존성 전파를 검증하기 위한 것이며,
일반적인 바인딩에 모두 필요한 설정은 아닙니다. raw와 공개 Go 코드는 `go/scalar`에 함께 둡니다.

`-Ddynamic`은 cgo 공유 라이브러리 링크를 선택합니다. 실행 시 플랫폼의 공유 라이브러리
검색 경로를 준비해야 합니다. 예를 들어 macOS에서는 `DYLD_LIBRARY_PATH=$PWD/../zig-out/lib go test ./...`
입니다 ([런타임 검색 경로](../../docs/configuration.md#cgo_dynamic의-런타임-검색-경로)).
기본 정적 경로로 돌아갈 때는 `zig build go`를 다시 실행하세요.

[링크 설정](../../docs/configuration.md) · [전체 예제](../../docs/examples.md)
