# 첫 Zig → Go 호출

외부 라이브러리, 객체 수명과 callback 없이 Zig 함수 하나를 Go에서 호출하는 최소
프로젝트입니다. zigo를 처음 사용한다면 이 예제부터 실행하세요.

## 실행

이 디렉터리에서 실행합니다. Zig 0.16.0, Go 1.24 이상과 cgo용 C compiler가 필요합니다.

```sh
zig build go-check
zig build go
(cd go && go run ./cmd/demo)
(cd go && go test ./...)
```

프로그램은 `2 + 3 = 5`를 출력합니다.

## 핵심 파일

1. [src/root.zig](src/root.zig) — 원래 Zig 함수
2. [src/bindings.zig](src/bindings.zig) — 노출할 함수 선택
3. [build.zig](build.zig) — Zig module과 생성 step 연결
4. [Go 프로그램](go/cmd/demo/main.go) — 생성 package를 import해 호출
5. [Go 예제 테스트](go/calculator/example_test.go) — 반환값과 출력 검증

## 생성되는 동작

`zig build go`는 공개 `calculator` package와 `go/internal/raw`를 생성하고 native library를
빌드합니다. `*_gen.go`와 raw package는 직접 수정하지 않습니다. 외부 프로젝트에서는
`build.zig.zon`의 상대 경로 대신 [시작 가이드](../../docs/getting-started.md)처럼 zigo dependency를
추가하고 `go_module`을 자신의 module path로 바꾸세요.

## 다음 문서

[시작 가이드](../../docs/getting-started.md) · [오류 예제](../02-errors/README.md) ·
[예제 선택](../../docs/examples.md)
