# zigo

zigo는 Zig 라이브러리에서 타입 안전한 Go 바인딩을 생성합니다. 라이브러리 구현과 분리된
`bindings.zig`에 공개 범위를 선언하면 C ABI shim, Go 패키지와 검증 메타데이터를 함께
만듭니다.

```text
Zig API + bindings.zig
          │
          ▼
        zigo
          │
          ├── Zig C ABI shim과 C header
          ├── Go raw package
          ├── Go public package
          └── ABI·semantic metadata
```

생성된 공개 패키지는 scalar와 slice뿐 아니라 typed error, 객체 수명, callback, stream,
tagged union과 중첩 결과도 Go다운 API로 노출합니다.

## 바로 실행하기

저장소의 최소 예제는 외부 native 라이브러리 없이 생성부터 Go 호출까지 실행됩니다.

```bash
git clone https://github.com/ironpark/zigo.git
cd zigo/examples/00-quick-start
zig build go
(cd go && go test ./... && go run ./cmd/demo)
```

마지막 명령은 테스트를 통과한 뒤 다음을 출력합니다.

```text
2 + 3 = 5
```

자신의 Zig 프로젝트에 연결하려면 [시작 가이드](docs/getting-started.md)를 따라가세요.

## 주요 기능

- 함수, error union, enum, struct와 slice의 타입 안전한 변환
- 생성자, 메서드와 `Close`를 갖는 opaque handle
- Go callback과 Zig `std.Io`의 `io.Reader`·`io.Writer` 연결
- `context.Context` 기반 취소
- tagged union projection, snapshot과 sealed variant
- cgo 정적·동적 링크와 `CGO_ENABLED=0` purego
- 생성물 최신 상태, API coverage와 ABI 호환성 검사
- 생성기 plugin을 통한 Go API 확장

## 지원 환경

- Zig 0.16.0
- Go 1.24 이상
- cgo: macOS와 Linux, Windows amd64 GNU ABI
- purego: macOS, Linux와 Windows의 amd64·arm64

처음에는 기본값인 `.cgo_static`을 사용하세요. 전체 조건과 크로스 컴파일 범위는
[지원 범위](docs/limitations.md)에서 확인할 수 있습니다.

## 문서

- [시작 가이드](docs/getting-started.md) — 첫 바인딩 생성과 Go 호출
- [zigo의 작동 방식](docs/how-zigo-works.md) — 선언에서 생성 패키지까지의 구조
- [예제](docs/examples.md) — 기능별 실행 가능한 프로젝트
- [바인딩 작성](docs/bindings.md) — 함수와 타입을 공개하는 방법
- [빌드 설정](docs/configuration.md) — 백엔드, 패키지와 설치 옵션
- [생성물과 CI](docs/generated-code.md) — 생성, 검사와 커밋 정책
- [전체 사용자 문서](docs/README.md) — 목적별 문서 탐색
- [기여 안내](CONTRIBUTING.md) — zigo 자체의 개발과 검증

## 라이선스

[MIT License](LICENSE)
