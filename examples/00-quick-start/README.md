# 첫 Zig → Go 호출

처음 실행할 예제입니다. 외부 라이브러리·객체 수명·콜백 없이 Zig 함수 하나를 Go에서
호출합니다. Zig 0.16.0, Go 1.24 이상, cgo용 C 컴파일러가 필요합니다.
Windows 설정은 [시작 가이드](../../docs/getting-started.md#windows에서-cgo-백엔드-쓰기)를 참고하세요.

## 실행

이 디렉터리에서 실행합니다. 셸 명령은 Bash·zsh 기준입니다.

```sh
zig build go
(cd go && go run ./cmd/demo)
(cd go && go test -v ./...)
```

프로그램은 `2 + 3 = 5`를 출력하고 `ExampleAdd`가 반환값을 검증합니다.

## 읽는 순서

1. [src/root.zig](src/root.zig): 원래 Zig 함수
2. [src/bindings.zig](src/bindings.zig): 노출할 함수 선택
3. [build.zig](build.zig): 모듈과 생성 스텝 연결
4. [Go 프로그램](go/cmd/demo/main.go): 외부 패키지에서 import하고 호출
5. [실행 가능한 사용 예제](go/calculator/example_test.go): 기대 출력까지 검사

`go/internal/raw`와 `*_gen.go`는 직접 수정하지 않습니다. `add`의 합은 `i32` 범위 안이어야
합니다. 예상 가능한 실패를 반환하는 방법은 [02-errors](../02-errors/README.md)를 보세요.

## 자신의 프로젝트로 옮기기

이 저장소의 예제는 `build.zig.zon`에서 `../..`의 zigo를 참조합니다. 외부 프로젝트에서는
[시작 가이드](../../docs/getting-started.md)의 `zig fetch`로 의존성을 추가하고,
`go_module`을 자신의 경로로 바꾸세요. `abi_base = "HEAD"`는 저장소 회귀 검사 설정이므로
새 프로젝트의 최소 구성에서는 생략해도 됩니다.

생성물을 수정한 뒤에는 `zig build go`, CI에서는 `zig build go-check go-lib`와
`go test ./...`를 실행합니다. `go get`만으로 native 라이브러리가 빌드되지는 않습니다.

다음 단계는 [오류 처리](../02-errors/README.md), [객체 수명](../03-opaque/README.md),
전체 목록은 [예제 선택 가이드](../../docs/examples.md)에 있습니다.
