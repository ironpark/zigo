# 첫 Zig → Go 호출

외부 라이브러리, 객체 수명과 콜백 없이 Zig 함수 하나를 Go에서 호출하는 최소
프로젝트입니다. zigo를 처음 사용한다면 이 예제부터 실행하세요.

## 전제 조건

저장소 전체를 받은 뒤 이 예제 디렉터리에서 실행합니다. Zig 0.16.0, Go 1.24 이상,
`gofmt`와 cgo용 C 컴파일러가 필요합니다.
도구 버전과 플랫폼 조건은 [지원 범위](../../docs/reference/support-matrix.md)를 확인하세요.

## 실행

```sh
zig build go
(cd go && go run ./cmd/demo)
(cd go && go test ./...)
```

## 예상 결과

프로그램은 `2 + 3 = 5`를 출력하고 Go 테스트가 통과합니다.

## 핵심 파일

1. [src/root.zig](src/root.zig) — 원래 Zig 함수
2. [src/bindings.zig](src/bindings.zig) — 노출할 함수 선택
3. [빌드.zig](build.zig) — Zig 모듈과 생성 단계 연결
4. [Go 프로그램](go/cmd/demo/main.go) — 생성 패키지를 import해 호출
5. [Go 예제 테스트](go/calculator/example_test.go) — 반환값과 출력 검증

## 동작과 주의사항

`zig build go`는 공개 `calculator` 패키지와 `go/internal/raw`를 생성하고 네이티브 라이브러리를
빌드합니다. `*_gen.go`와 raw 패키지는 직접 수정하지 않습니다. 외부 프로젝트에서는
`build.zig.zon`의 상대 경로 대신 [시작 가이드](../../docs/getting-started.md)처럼 zigo 의존성를
추가하고 `go_module`을 자신의 모듈 경로로 바꾸세요.

## 관련 문서

[시작 가이드](../../docs/getting-started.md) · [오류 예제](../02-errors/README.md) ·
[예제 선택](../../docs/examples.md)
